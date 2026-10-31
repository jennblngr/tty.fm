// Package api exposes the REST API under /api/v1.
package api

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"selfstream/internal/app"
	"selfstream/internal/auth"
	"selfstream/internal/covers"
	"selfstream/internal/scanner"
	"selfstream/internal/store"
	"selfstream/internal/stream"
)

type Server struct {
	DB       *store.DB
	Auth     *auth.Service
	Scanner  *scanner.Scanner
	Covers   *covers.Cache
	Streamer *stream.Streamer
	Log      *slog.Logger
	// ScanFn starts a background scan (owned by main so it outlives requests).
	ScanFn func(full bool)
}

const prefix = "/api/" + app.APIVersion

// Handler returns the root HTTP handler.
func (s *Server) Handler() http.Handler {
	pub := http.NewServeMux()
	pub.HandleFunc("GET "+prefix+"/health", s.health)
	pub.HandleFunc("POST "+prefix+"/auth/login", s.login)

	priv := http.NewServeMux()
	priv.HandleFunc("GET "+prefix+"/me", s.me)
	priv.HandleFunc("POST "+prefix+"/auth/logout", s.logout)
	priv.HandleFunc("GET "+prefix+"/devices", s.devices)
	priv.HandleFunc("DELETE "+prefix+"/devices/{id}", s.deleteDevice)

	priv.HandleFunc("GET "+prefix+"/home", s.home)
	priv.HandleFunc("GET "+prefix+"/artists", s.artists)
	priv.HandleFunc("GET "+prefix+"/artists/{id}", s.artist)
	priv.HandleFunc("GET "+prefix+"/albums", s.albums)
	priv.HandleFunc("GET "+prefix+"/albums/{id}", s.album)
	priv.HandleFunc("GET "+prefix+"/tracks", s.tracks)
	priv.HandleFunc("GET "+prefix+"/tracks/{id}", s.track)
	priv.HandleFunc("GET "+prefix+"/search", s.search)
	priv.HandleFunc("GET "+prefix+"/covers/{id}", s.cover)
	priv.HandleFunc("GET "+prefix+"/stream/{id}", s.stream)

	priv.HandleFunc("GET "+prefix+"/playlists/tree", s.playlistTree)
	priv.HandleFunc("POST "+prefix+"/folders", s.createFolder)
	priv.HandleFunc("PATCH "+prefix+"/folders/{id}", s.updateFolder)
	priv.HandleFunc("DELETE "+prefix+"/folders/{id}", s.deleteFolder)
	priv.HandleFunc("POST "+prefix+"/playlists", s.createPlaylist)
	priv.HandleFunc("GET "+prefix+"/playlists/{id}", s.playlist)
	priv.HandleFunc("PATCH "+prefix+"/playlists/{id}", s.updatePlaylist)
	priv.HandleFunc("DELETE "+prefix+"/playlists/{id}", s.deletePlaylist)
	priv.HandleFunc("GET "+prefix+"/playlists/{id}/tracks", s.playlistTracks)
	priv.HandleFunc("POST "+prefix+"/playlists/{id}/tracks", s.addPlaylistTracks)
	priv.HandleFunc("PATCH "+prefix+"/playlists/{id}/tracks", s.movePlaylistTrack)
	priv.HandleFunc("DELETE "+prefix+"/playlists/{id}/tracks/{entry}", s.removePlaylistTrack)

	priv.HandleFunc("POST "+prefix+"/plays", s.addPlays)
	priv.HandleFunc("GET "+prefix+"/favorites", s.favorites)
	priv.HandleFunc("PUT "+prefix+"/favorites/{kind}/{id}", s.setFavorite(true))
	priv.HandleFunc("DELETE "+prefix+"/favorites/{kind}/{id}", s.setFavorite(false))

	priv.HandleFunc("POST "+prefix+"/admin/scan", s.startScan)
	priv.HandleFunc("GET "+prefix+"/admin/scan", s.scanStatus)

	pub.Handle(prefix+"/", s.Auth.Middleware(priv))
	return s.logRequests(pub)
}

// --- helpers ---------------------------------------------------------------

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

type apiError struct {
	Error string `json:"error"`
}

func (s *Server) fail(w http.ResponseWriter, r *http.Request, err error) {
	switch {
	case errors.Is(err, store.ErrNotFound):
		writeJSON(w, http.StatusNotFound, apiError{"not found"})
	case errors.Is(err, store.ErrInvalid):
		writeJSON(w, http.StatusBadRequest, apiError{err.Error()})
	case errors.Is(err, auth.ErrBadCredentials):
		writeJSON(w, http.StatusUnauthorized, apiError{"bad credentials"})
	case errors.Is(err, errBadRequest):
		writeJSON(w, http.StatusBadRequest, apiError{err.Error()})
	default:
		if r.Context().Err() == nil {
			s.Log.Error("request failed", "method", r.Method, "path", r.URL.Path, "err", err)
		}
		writeJSON(w, http.StatusInternalServerError, apiError{"internal error"})
	}
}

var errBadRequest = errors.New("bad request")

func pathID(r *http.Request, name string) (int64, error) {
	id, err := strconv.ParseInt(r.PathValue(name), 10, 64)
	if err != nil || id <= 0 {
		return 0, errBadRequest
	}
	return id, nil
}

func queryInt(r *http.Request, name string, def int) int {
	if v, err := strconv.Atoi(r.URL.Query().Get(name)); err == nil {
		return v
	}
	return def
}

func decode(r *http.Request, v any) error {
	r.Body = http.MaxBytesReader(nil, r.Body, 1<<20)
	if err := json.NewDecoder(r.Body).Decode(v); err != nil {
		return errors.Join(errBadRequest, err)
	}
	return nil
}

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (w *statusWriter) WriteHeader(code int) {
	w.status = code
	w.ResponseWriter.WriteHeader(code)
}

// Flush keeps streaming responses flowing through the wrapper.
func (w *statusWriter) Flush() {
	if f, ok := w.ResponseWriter.(http.Flusher); ok {
		f.Flush()
	}
}

func (w *statusWriter) Unwrap() http.ResponseWriter { return w.ResponseWriter }

func (s *Server) logRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		sw := &statusWriter{ResponseWriter: w, status: http.StatusOK}
		w.Header().Set("X-App", app.Name+"/"+app.Version)
		next.ServeHTTP(sw, r)
		s.Log.Debug("http", "method", r.Method, "path", r.URL.Path, "status", sw.status,
			"duration", time.Since(start).Round(time.Microsecond))
	})
}

func (s *Server) health(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok", "app": app.Name, "version": app.Version})
}
