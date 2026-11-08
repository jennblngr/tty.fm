// Package api exposes the REST API under /api/v1.
package api

import (
	"encoding/json"
	"errors"
	"log/slog"
	"math"
	"net/http"
	"strconv"
	"strings"
	"time"

	"ttyfm/internal/app"
	"ttyfm/internal/auth"
	"ttyfm/internal/covers"
	"ttyfm/internal/hub"
	"ttyfm/internal/lyrics"
	"ttyfm/internal/scanner"
	"ttyfm/internal/store"
	"ttyfm/internal/stream"
)

type Server struct {
	DB       *store.DB
	Auth     *auth.Service
	Scanner  *scanner.Scanner
	Covers   *covers.Cache
	Streamer *stream.Streamer
	Log      *slog.Logger
	Hub      *hub.Hub
	Lyrics   *lyrics.Finder
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
	priv.HandleFunc("GET "+prefix+"/ws", s.ws)
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
	priv.HandleFunc("GET "+prefix+"/tracks/{id}/lyrics", s.lyrics)
	priv.HandleFunc("GET "+prefix+"/tracks/{id}/analysis", s.trackAnalysis)
	priv.HandleFunc("PUT "+prefix+"/tracks/{id}/analysis", s.saveAnalysis)
	priv.HandleFunc("DELETE "+prefix+"/tracks/{id}/analysis", s.resetAnalysis)
	priv.HandleFunc("GET "+prefix+"/tracks/{id}/similar", s.similarTracks)
	priv.HandleFunc("GET "+prefix+"/radio", s.radio)
	priv.HandleFunc("GET "+prefix+"/mixes", s.mixes)
	priv.HandleFunc("GET "+prefix+"/releases", s.newReleases)
	priv.HandleFunc("GET "+prefix+"/releases/queue", s.releaseQueue)
	priv.HandleFunc("PUT "+prefix+"/artists/{id}/releases", s.saveArtistReleases)
	priv.HandleFunc("GET "+prefix+"/follows", s.follows)
	priv.HandleFunc("PUT "+prefix+"/artists/{id}/follow", s.setFollow)
	priv.HandleFunc("GET "+prefix+"/mixes/{n}", s.mix)
	priv.HandleFunc("GET "+prefix+"/search", s.search)
	priv.HandleFunc("GET "+prefix+"/search/facets", s.searchFacets)
	priv.HandleFunc("GET "+prefix+"/covers/{id}", s.cover)
	priv.HandleFunc("GET "+prefix+"/stream/{id}", s.stream)

	priv.HandleFunc("GET "+prefix+"/playlists/tree", s.playlistTree)
	priv.HandleFunc("POST "+prefix+"/folders", s.notify("playlists", s.createFolder))
	priv.HandleFunc("PATCH "+prefix+"/folders/{id}", s.notify("playlists", s.updateFolder))
	priv.HandleFunc("DELETE "+prefix+"/folders/{id}", s.notify("playlists", s.deleteFolder))
	priv.HandleFunc("POST "+prefix+"/playlists", s.notify("playlists", s.createPlaylist))
	priv.HandleFunc("GET "+prefix+"/playlists/{id}", s.playlist)
	priv.HandleFunc("PATCH "+prefix+"/playlists/{id}", s.notify("playlists", s.updatePlaylist))
	priv.HandleFunc("DELETE "+prefix+"/playlists/{id}", s.notify("playlists", s.deletePlaylist))
	priv.HandleFunc("GET "+prefix+"/playlists/{id}/tracks", s.playlistTracks)
	priv.HandleFunc("POST "+prefix+"/playlists/{id}/tracks", s.notify("playlists", s.addPlaylistTracks))
	priv.HandleFunc("PATCH "+prefix+"/playlists/{id}/tracks", s.notify("playlists", s.movePlaylistTrack))
	priv.HandleFunc("DELETE "+prefix+"/playlists/{id}/tracks/{entry}", s.notify("playlists", s.removePlaylistTrack))

	priv.HandleFunc("POST "+prefix+"/plays", s.addPlays)
	priv.HandleFunc("GET "+prefix+"/stats", s.stats)
	priv.HandleFunc("GET "+prefix+"/favorites", s.favorites)
	priv.HandleFunc("PUT "+prefix+"/favorites/{kind}/{id}", s.notify("favorites", s.setFavorite(true)))
	priv.HandleFunc("DELETE "+prefix+"/favorites/{kind}/{id}", s.notify("favorites", s.setFavorite(false)))
	priv.HandleFunc("GET "+prefix+"/hidden", s.hidden)
	priv.HandleFunc("PUT "+prefix+"/hidden/{id}", s.notify("hidden", s.setHidden(true)))
	priv.HandleFunc("DELETE "+prefix+"/hidden/{id}", s.notify("hidden", s.setHidden(false)))

	priv.HandleFunc("GET "+prefix+"/notifications", s.notifications)
	priv.HandleFunc("GET "+prefix+"/notifications/unread", s.unreadNotifications)
	priv.HandleFunc("POST "+prefix+"/notifications/read", s.notify("notifications", s.readAllNotifications))
	priv.HandleFunc("PATCH "+prefix+"/notifications/{id}", s.notify("notifications", s.updateNotification))
	priv.HandleFunc("GET "+prefix+"/notifications/settings", s.notificationSettings)
	priv.HandleFunc("PATCH "+prefix+"/notifications/settings", s.notify("notifications", s.updateNotificationSettings))

	priv.HandleFunc("POST "+prefix+"/admin/scan", s.startScan)
	priv.HandleFunc("GET "+prefix+"/admin/scan", s.scanStatus)
	priv.HandleFunc("GET "+prefix+"/analysis", s.analysisStatus)
	priv.HandleFunc("PATCH "+prefix+"/analysis", s.updateAnalysis)
	priv.HandleFunc("GET "+prefix+"/analysis/queue", s.analysisQueue)
	priv.HandleFunc("DELETE "+prefix+"/analysis", s.resetAllAnalysis)

	pub.Handle(prefix+"/", s.Auth.Middleware(priv))
	return s.logRequests(pub)
}

// --- live updates ----------------------------------------------------------

func (s *Server) ws(w http.ResponseWriter, r *http.Request) {
	if s.Hub == nil {
		http.NotFound(w, r)
		return
	}
	s.Hub.Serve(w, r, auth.DeviceFrom(r.Context()))
}

// notify wraps a mutation: once it succeeds, the other devices are told
// that what ("playlists", "favorites") changed.
func (s *Server) notify(what string, h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		sw := &statusWriter{ResponseWriter: w, status: http.StatusOK}
		h(sw, r)
		if s.Hub != nil && sw.status < 300 {
			s.Hub.Changed(what, auth.DeviceFrom(r.Context()).ID)
		}
	}
}

// --- helpers ---------------------------------------------------------------

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v) // headers are sent: only the client hanging up can fail here
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

// queryFloat parses an optional number (0 when absent).
func queryFloat(r *http.Request, name string) (float64, error) {
	v := r.URL.Query().Get(name)
	if v == "" {
		return 0, nil
	}
	f, err := strconv.ParseFloat(v, 64)
	if err != nil || math.IsNaN(f) || math.IsInf(f, 0) {
		return 0, errBadRequest
	}
	return f, nil
}

func queryInt(r *http.Request, name string, def int) int {
	if v, err := strconv.Atoi(r.URL.Query().Get(name)); err == nil {
		return v
	}
	return def
}

// queryIDs parses a comma-separated list of ids (at most max of them).
func queryIDs(r *http.Request, name string, max int) ([]int64, error) {
	v := r.URL.Query().Get(name)
	if v == "" {
		return nil, nil
	}
	parts := strings.Split(v, ",")
	if len(parts) > max {
		return nil, errBadRequest
	}
	ids := make([]int64, 0, len(parts))
	for _, p := range parts {
		id, err := strconv.ParseInt(strings.TrimSpace(p), 10, 64)
		if err != nil || id <= 0 {
			return nil, errBadRequest
		}
		ids = append(ids, id)
	}
	return ids, nil
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
		w.Header().Set("X-App", app.Title+"/"+app.Version)
		next.ServeHTTP(sw, r)
		s.Log.Debug("http", "method", r.Method, "path", r.URL.Path, "status", sw.status,
			"duration", time.Since(start).Round(time.Microsecond))
	})
}

func (s *Server) health(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok", "app": app.Title, "version": app.Version})
}
