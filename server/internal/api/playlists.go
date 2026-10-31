package api

import (
	"encoding/json"
	"net/http"

	"selfstream/internal/auth"
	"selfstream/internal/store"
)

func (s *Server) playlistTree(w http.ResponseWriter, r *http.Request) {
	t, err := s.DB.PlaylistTree(r.Context())
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, t)
}

type createReq struct {
	Name     string `json:"name"`
	ParentID *int64 `json:"parent_id"` // folders
	FolderID *int64 `json:"folder_id"` // playlists
}

func (s *Server) createFolder(w http.ResponseWriter, r *http.Request) {
	var req createReq
	if err := decode(r, &req); err != nil {
		s.fail(w, r, err)
		return
	}
	id, err := s.DB.CreateFolder(r.Context(), req.Name, req.ParentID)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]int64{"id": id})
}

func (s *Server) createPlaylist(w http.ResponseWriter, r *http.Request) {
	var req struct {
		createReq
		TrackIDs []int64 `json:"track_ids"`
	}
	if err := decode(r, &req); err != nil {
		s.fail(w, r, err)
		return
	}
	id, err := s.DB.CreatePlaylist(r.Context(), req.Name, req.FolderID)
	if err == nil && len(req.TrackIDs) > 0 {
		err = s.DB.AddTracks(r.Context(), id, req.TrackIDs, nil)
	}
	if err != nil {
		s.fail(w, r, err)
		return
	}
	p, err := s.DB.Playlist(r.Context(), id)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, p)
}

// parseUpdate reads {"name", "parent_id"|"folder_id", "position"}. The
// parent key distinguishes "absent" (no move) from null (move to root).
func parseUpdate(r *http.Request, parentKey string) (store.FolderUpdate, error) {
	var raw map[string]json.RawMessage
	if err := decode(r, &raw); err != nil {
		return store.FolderUpdate{}, err
	}
	var u store.FolderUpdate
	if v, ok := raw["name"]; ok {
		if err := json.Unmarshal(v, &u.Name); err != nil {
			return u, errBadRequest
		}
	}
	if v, ok := raw[parentKey]; ok {
		var parent *int64
		if err := json.Unmarshal(v, &parent); err != nil {
			return u, errBadRequest
		}
		u.MoveTo = &parent
	}
	if v, ok := raw["position"]; ok {
		if err := json.Unmarshal(v, &u.Position); err != nil {
			return u, errBadRequest
		}
	}
	return u, nil
}

func (s *Server) updateFolder(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err != nil {
		s.fail(w, r, err)
		return
	}
	u, err := parseUpdate(r, "parent_id")
	if err == nil {
		err = s.DB.UpdateFolder(r.Context(), id, u)
	}
	if err != nil {
		s.fail(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) deleteFolder(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err == nil {
		err = s.DB.DeleteFolder(r.Context(), id)
	}
	if err != nil {
		s.fail(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) playlist(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err != nil {
		s.fail(w, r, err)
		return
	}
	p, err := s.DB.Playlist(r.Context(), id)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, p)
}

func (s *Server) updatePlaylist(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err != nil {
		s.fail(w, r, err)
		return
	}
	u, err := parseUpdate(r, "folder_id")
	if err == nil {
		err = s.DB.UpdatePlaylist(r.Context(), id, u)
	}
	if err != nil {
		s.fail(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) deletePlaylist(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err == nil {
		err = s.DB.DeletePlaylist(r.Context(), id)
	}
	if err != nil {
		s.fail(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) playlistTracks(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err != nil {
		s.fail(w, r, err)
		return
	}
	es, err := s.DB.PlaylistTracks(r.Context(), id)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": es})
}

func (s *Server) addPlaylistTracks(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err != nil {
		s.fail(w, r, err)
		return
	}
	var req struct {
		TrackIDs   []int64 `json:"track_ids"`
		AtPosition *int    `json:"at_position"`
	}
	if err = decode(r, &req); err == nil {
		err = s.DB.AddTracks(r.Context(), id, req.TrackIDs, req.AtPosition)
	}
	if err != nil {
		s.fail(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) movePlaylistTrack(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err != nil {
		s.fail(w, r, err)
		return
	}
	var req struct {
		EntryID    int64 `json:"entry_id"`
		ToPosition int   `json:"to_position"`
	}
	if err = decode(r, &req); err == nil {
		err = s.DB.MoveEntry(r.Context(), id, req.EntryID, req.ToPosition)
	}
	if err != nil {
		s.fail(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) removePlaylistTrack(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err != nil {
		s.fail(w, r, err)
		return
	}
	entry, err := pathID(r, "entry")
	if err == nil {
		err = s.DB.RemoveEntry(r.Context(), id, entry)
	}
	if err != nil {
		s.fail(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// --- plays, favourites, admin ----------------------------------------------

func (s *Server) addPlays(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Plays []store.Play `json:"plays"`
	}
	if err := decode(r, &req); err != nil {
		s.fail(w, r, err)
		return
	}
	n, err := s.DB.AddPlays(r.Context(), auth.DeviceFrom(r.Context()).ID, req.Plays)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]int{"recorded": n})
}

func (s *Server) favorites(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if r.URL.Query().Get("full") != "1" {
		ids, err := s.DB.FavoriteIDs(ctx)
		if err != nil {
			s.fail(w, r, err)
			return
		}
		writeJSON(w, http.StatusOK, ids)
		return
	}
	tracks, err := s.DB.FavoriteTracks(ctx)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	albums, err := s.DB.FavoriteAlbums(ctx)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"tracks": tracks, "albums": albums})
}

func (s *Server) setFavorite(on bool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id, err := pathID(r, "id")
		if err == nil {
			err = s.DB.SetFavorite(r.Context(), r.PathValue("kind"), id, on)
		}
		if err != nil {
			s.fail(w, r, err)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

func (s *Server) startScan(w http.ResponseWriter, r *http.Request) {
	if s.Scanner.Status().Running {
		writeJSON(w, http.StatusConflict, apiError{"scan already running"})
		return
	}
	s.ScanFn(r.URL.Query().Get("full") == "1")
	writeJSON(w, http.StatusAccepted, s.Scanner.Status())
}

func (s *Server) scanStatus(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, s.Scanner.Status())
}
