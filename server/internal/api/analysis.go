package api

import (
	"errors"
	"net/http"
	"strconv"

	"ttyfm/internal/store"
)

// --- audio analysis (phase 3) ----------------------------------------------
//
// The recommender service pulls the queue, analyses the files from its own
// read-only mount of the music folder and reports each result back.

// trackAnalysis returns the analysis of a track and the tracks that chain
// well after it. 404 if the track has not been analysed yet.
func (s *Server) trackAnalysis(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err != nil {
		s.fail(w, r, err)
		return
	}
	a, err := s.DB.TrackAnalysis(r.Context(), id)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	compatible, err := s.DB.CompatibleTracks(r.Context(), id, queryInt(r, "limit", 5))
	if err != nil && !errors.Is(err, store.ErrNotFound) {
		s.fail(w, r, err)
		return
	}
	if compatible == nil {
		compatible = []store.Track{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"analysis": a, "compatible": compatible})
}

// similarTracks lists the tracks that sound closest to a track (embeddings
// sent with the analysis), the foundation of the radio. Empty while the
// track has no embedding; 404 if it is not in the library.
func (s *Server) similarTracks(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err != nil {
		s.fail(w, r, err)
		return
	}
	items, err := s.DB.SimilarTracks(r.Context(), id, queryInt(r, "limit", 20))
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

func (s *Server) saveAnalysis(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err != nil {
		s.fail(w, r, err)
		return
	}
	var req store.AnalysisReport
	if err := decode(r, &req); err != nil {
		s.fail(w, r, err)
		return
	}
	if err := s.DB.SaveAnalysis(r.Context(), id, req); err != nil {
		s.fail(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// resetAnalysis queues one track again ("relancer l'analyse").
func (s *Server) resetAnalysis(w http.ResponseWriter, r *http.Request) {
	id, err := pathID(r, "id")
	if err == nil {
		err = s.DB.ResetAnalysis(r.Context(), id)
	}
	if err != nil {
		s.fail(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// resetAllAnalysis queues the whole library again.
func (s *Server) resetAllAnalysis(w http.ResponseWriter, r *http.Request) {
	if err := s.DB.ResetAnalysis(r.Context(), 0); err != nil {
		s.fail(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// analysisQueue lists the tracks to analyse. The recommender passes its
// analyzer name so that tracks analysed by an older version come back.
func (s *Server) analysisQueue(w http.ResponseWriter, r *http.Request) {
	jobs, err := s.DB.AnalysisQueue(r.Context(), queryInt(r, "limit", 20), r.URL.Query().Get("analyzer"))
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": jobs})
}

func (s *Server) analysisStatus(w http.ResponseWriter, r *http.Request) {
	st, err := s.DB.AnalysisStatus(r.Context())
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, st)
}

// radio returns a batch of tracks to play after a track (?track=) or an
// artist (?artist=). For the next batch the client sends the same seed, the
// tracks played since (?recent=, oldest first: they steer the radio and
// are left out) and those still queued (?exclude=), comma-separated.
func (s *Server) radio(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	req := store.RadioRequest{Limit: queryInt(r, "limit", 20)}
	var err error
	if (q.Get("track") == "") == (q.Get("artist") == "") {
		s.fail(w, r, errBadRequest)
		return
	}
	for _, p := range []struct {
		name string
		dst  *int64
	}{{"track", &req.TrackID}, {"artist", &req.ArtistID}} {
		if q.Get(p.name) == "" {
			continue
		}
		if *p.dst, err = strconv.ParseInt(q.Get(p.name), 10, 64); err != nil || *p.dst <= 0 {
			s.fail(w, r, errBadRequest)
			return
		}
	}
	if req.Recent, err = queryIDs(r, "recent", 1000); err != nil {
		s.fail(w, r, err)
		return
	}
	if req.Exclude, err = queryIDs(r, "exclude", 1000); err != nil {
		s.fail(w, r, err)
		return
	}
	radio, err := s.DB.Radio(r.Context(), req)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, radio)
}
