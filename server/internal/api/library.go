package api

import (
	"errors"
	"net/http"
	"os"
	"strconv"
	"time"

	"ttyfm/internal/auth"
	"ttyfm/internal/covers"
	"ttyfm/internal/lyrics"
	"ttyfm/internal/store"
	"ttyfm/internal/stream"
)

// --- auth & devices --------------------------------------------------------

func (s *Server) login(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Username   string `json:"username"`
		Password   string `json:"password"`
		DeviceName string `json:"device_name"`
		Platform   string `json:"platform"`
	}
	if err := decode(r, &req); err != nil {
		s.fail(w, r, err)
		return
	}
	tok, dev, err := s.Auth.Login(r.Context(), req.Username, req.Password, req.DeviceName, req.Platform)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"token": tok, "device": dev})
}

func (s *Server) logout(w http.ResponseWriter, r *http.Request) {
	dev := auth.DeviceFrom(r.Context())
	if err := s.Auth.Revoke(r.Context(), dev.UserID, dev.ID); err != nil {
		s.fail(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) me(w http.ResponseWriter, r *http.Request) {
	tracks, albums, artists, err := s.DB.LibraryStats(r.Context())
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"device":  auth.DeviceFrom(r.Context()),
		"library": map[string]int{"tracks": tracks, "albums": albums, "artists": artists},
	})
}

func (s *Server) devices(w http.ResponseWriter, r *http.Request) {
	ds, err := s.DB.Devices(r.Context(), auth.DeviceFrom(r.Context()).UserID)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": ds})
}

func (s *Server) deleteDevice(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err == nil {
		err = s.Auth.Revoke(r.Context(), auth.DeviceFrom(r.Context()).UserID, id)
	}
	if err != nil {
		s.fail(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// --- library ---------------------------------------------------------------

func (s *Server) home(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	limit := queryInt(r, "limit", 20)
	added, err := s.DB.RecentAdditions(ctx, limit)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	played, err := s.DB.RecentlyPlayed(ctx, limit)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	moments, err := s.DB.Moments(ctx, time.Now())
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"recent_additions": added,
		"recently_played":  played,
		"moments":          moments,
	})
}

func (s *Server) artists(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	page, err := s.DB.Artists(r.Context(), q.Get("cursor"), queryInt(r, "limit", 0), q.Get("album_artists") == "1")
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, page)
}

func (s *Server) artist(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err != nil {
		s.fail(w, r, err)
		return
	}
	a, err := s.DB.Artist(r.Context(), id)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	albums, err := s.DB.ArtistAlbums(r.Context(), id)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"artist": a, "albums": albums})
}

func (s *Server) albums(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	page, err := s.DB.Albums(r.Context(), q.Get("sort"), q.Get("cursor"), queryInt(r, "limit", 0))
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, page)
}

func (s *Server) album(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err != nil {
		s.fail(w, r, err)
		return
	}
	a, err := s.DB.Album(r.Context(), id)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	tracks, err := s.DB.AlbumTracks(r.Context(), id)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"album": a, "tracks": tracks})
}

func (s *Server) tracks(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	page, err := s.DB.Tracks(r.Context(), q.Get("sort"), q.Get("cursor"), queryInt(r, "limit", 0))
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, page)
}

func (s *Server) track(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err != nil {
		s.fail(w, r, err)
		return
	}
	t, err := s.DB.Track(r.Context(), id)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, t)
}

// search: q (prefix words) and optional filters genre, year_min, year_max,
// format, bpm_min, bpm_max and camelot (the last three keep analysed tracks
// only). With filters only, it lists what matches them.
func (s *Server) search(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	f := store.Filter{Genre: q.Get("genre"), YearMin: queryInt(r, "year_min", 0),
		YearMax: queryInt(r, "year_max", 0), Format: q.Get("format"), Camelot: q.Get("camelot")}
	var err error
	if f.BPMMin, err = queryFloat(r, "bpm_min"); err == nil {
		f.BPMMax, err = queryFloat(r, "bpm_max")
	}
	if err == nil {
		err = f.Validate()
	}
	if err != nil {
		s.fail(w, r, err)
		return
	}
	res, err := s.DB.Search(r.Context(), q.Get("q"), f, queryInt(r, "limit", 20))
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, res)
}

func (s *Server) searchFacets(w http.ResponseWriter, r *http.Request) {
	f, err := s.DB.SearchFacets(r.Context())
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, f)
}

func (s *Server) lyrics(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err != nil {
		s.fail(w, r, err)
		return
	}
	info, err := s.DB.TrackFileInfo(r.Context(), id)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	l, err := s.Lyrics.Find(info.Path)
	if errors.Is(err, lyrics.ErrNone) {
		writeJSON(w, http.StatusNotFound, apiError{"no lyrics"})
		return
	}
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, l)
}

// --- media -----------------------------------------------------------------

func (s *Server) cover(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err != nil {
		s.fail(w, r, err)
		return
	}
	hash, err := s.DB.CoverHash(r.Context(), id)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	p := s.Covers.Path(hash, queryInt(r, "size", 300))
	if _, err := os.Stat(p); err != nil {
		writeJSON(w, http.StatusNotFound, apiError{"cover file missing; rescan"})
		return
	}
	// Cover ids are never reused and their content never changes.
	w.Header().Set("Cache-Control", "private, max-age=31536000, immutable")
	w.Header().Set("ETag", `"`+hash+strconv.Itoa(covers.SnapSize(queryInt(r, "size", 300)))+`"`)
	http.ServeFile(w, r, p)
}

// stream serves a track. Without "format", the original file is sent with
// Range support. With format=opus|aac|mp3 (and optional bitrate in kbit/s,
// offset in seconds) it is transcoded.
func (s *Server) stream(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err != nil {
		s.fail(w, r, err)
		return
	}
	info, err := s.DB.TrackFileInfo(r.Context(), id)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	q := r.URL.Query()
	fmtName := q.Get("format")
	if fmtName == "" || fmtName == "original" || fmtName == info.Format {
		s.Streamer.ServeOriginal(w, r, info.Path, info.Format)
		return
	}
	f, ok := stream.Formats[fmtName]
	if !ok {
		writeJSON(w, http.StatusBadRequest, apiError{"unknown format " + strconv.Quote(fmtName)})
		return
	}
	offset, _ := strconv.ParseFloat(q.Get("offset"), 64)
	w.Header().Set("X-Content-Duration", strconv.FormatFloat(float64(info.DurationMs)/1000, 'f', 3, 64))
	s.Streamer.ServeTranscoded(w, r, id, info.Path, info.Mtime, f, stream.ClampBitrate(queryInt(r, "bitrate", 128)), offset)
}
