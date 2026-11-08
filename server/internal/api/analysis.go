package api

import (
	"errors"
	"net/http"

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
