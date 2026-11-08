package store

import (
	"context"
	"errors"
	"testing"
)

// embedding returns a vector pointing mostly along axis a, tilted towards
// axis b by tilt.
func embedding(a, b int, tilt float32) []float32 {
	v := make([]float32, EmbeddingDims)
	v[a], v[b] = 1, tilt
	return v
}

func TestSimilarTracks(t *testing.T) {
	db := openTest(t)
	ctx := context.Background()
	ids := seed(t, db,
		TrackFile{Path: "a/1.flac", Title: "One", Artist: "X", Album: "A", Mtime: 1},
		TrackFile{Path: "a/2.flac", Title: "Two", Artist: "X", Album: "A", Mtime: 1},
		TrackFile{Path: "a/3.flac", Title: "Three", Artist: "X", Album: "A", Mtime: 1},
		TrackFile{Path: "a/4.flac", Title: "Four", Artist: "X", Album: "A", Mtime: 1},
		TrackFile{Path: "a/5.flac", Title: "Five", Artist: "X", Album: "A", Mtime: 1},
	)
	save := func(id int64, e []float32) error {
		return db.SaveAnalysis(ctx, id, AnalysisReport{FileMtime: 1, Analyzer: "test/1", Embedding: e})
	}
	for i, e := range [][]float32{
		embedding(0, 1, 0),   // the reference
		embedding(0, 1, 0.2), // close
		embedding(0, 1, 1),   // 45°
		embedding(1, 2, 0),   // orthogonal
	} {
		if err := save(ids[i], e); err != nil {
			t.Fatal(err)
		}
	}
	titles := func(id int64) []string {
		t.Helper()
		got, err := db.SimilarTracks(ctx, id, 10)
		if err != nil {
			t.Fatal(err)
		}
		out := []string{}
		for _, s := range got {
			out = append(out, s.Title)
		}
		return out
	}
	got, err := db.SimilarTracks(ctx, ids[0], 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 3 || got[0].Title != "Two" || got[1].Title != "Three" || got[2].Title != "Four" {
		t.Fatalf("similar: %v", titles(ids[0]))
	}
	if got[0].Similarity < 0.97 || got[1].Similarity != 0.707 || got[2].Similarity != 0 {
		t.Errorf("similarities: %v %v %v", got[0].Similarity, got[1].Similarity, got[2].Similarity)
	}
	if got, _ := db.SimilarTracks(ctx, ids[0], 1); len(got) != 1 {
		t.Errorf("limit: %d", len(got))
	}

	// Not analysed with the models: no neighbours. Unknown track: not found.
	if got := titles(ids[4]); len(got) != 0 {
		t.Errorf("without embedding: %v", got)
	}
	if _, err := db.SimilarTracks(ctx, 999, 10); !errors.Is(err, ErrNotFound) {
		t.Errorf("unknown track: %v", err)
	}

	// Hidden tracks are left out.
	if err := db.SetHidden(ctx, ids[1], true); err != nil {
		t.Fatal(err)
	}
	if got := titles(ids[0]); len(got) != 2 || got[0] != "Three" {
		t.Errorf("with Two hidden: %v", got)
	}
	if err := db.SetHidden(ctx, ids[1], false); err != nil {
		t.Fatal(err)
	}

	// A new analysis replaces the vector; one without (an error) drops it,
	// and so does a reset.
	if err := save(ids[3], embedding(0, 1, 0.1)); err != nil {
		t.Fatal(err)
	}
	if got := titles(ids[0]); got[0] != "Four" {
		t.Errorf("after the new analysis of Four: %v", got)
	}
	if err := db.SaveAnalysis(ctx, ids[3], AnalysisReport{FileMtime: 1, Analyzer: "test/1", Error: "boom"}); err != nil {
		t.Fatal(err)
	}
	if got := titles(ids[0]); len(got) != 2 {
		t.Errorf("after the failed analysis of Four: %v", got)
	}
	if err := db.ResetAnalysis(ctx, ids[2]); err != nil {
		t.Fatal(err)
	}
	if got := titles(ids[0]); len(got) != 1 || got[0] != "Two" {
		t.Errorf("after the reset of Three: %v", got)
	}
	var n int
	if err := db.r.QueryRow(`SELECT COUNT(*) FROM track_embeddings`).Scan(&n); err != nil || n != 2 {
		t.Errorf("after the reset of Three: %d vectors (%v)", n, err)
	}
	// Deleting a track from the library drops its vector with its analysis.
	if _, err := db.w.Exec(`DELETE FROM tracks WHERE id = ?`, ids[1]); err != nil {
		t.Fatal(err)
	}
	if got := titles(ids[0]); len(got) != 0 {
		t.Errorf("after deleting Two: %v", got)
	}
	if err := db.ResetAnalysis(ctx, 0); err != nil {
		t.Fatal(err)
	}
	if err := db.r.QueryRow(`SELECT COUNT(*) FROM track_embeddings`).Scan(&n); err != nil || n != 0 {
		t.Errorf("after the full reset: %d vectors (%v)", n, err)
	}

	// Bad vectors are refused.
	for name, e := range map[string][]float32{
		"short": make([]float32, 3),
		"zeros": make([]float32, EmbeddingDims),
	} {
		if err := save(ids[0], e); !errors.Is(err, ErrInvalid) {
			t.Errorf("%s embedding: %v", name, err)
		}
	}
}
