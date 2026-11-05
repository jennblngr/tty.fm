package store

import (
	"context"
	"errors"
	"testing"
)

func TestCamelot(t *testing.T) {
	for _, c := range []struct{ key, scale, want, tonic string }{
		{"C", "major", "8B", "C"}, {"A", "minor", "8A", "A"}, {"G", "major", "9B", "G"},
		{"E", "minor", "9A", "E"}, {"B", "major", "1B", "B"}, {"Ab", "minor", "1A", "G#"},
		{"F#", "major", "2B", "F#"}, {"Db", "major", "3B", "C#"}, {"F", "major", "7B", "F"},
		{"C#", "minor", "12A", "C#"}, {"D", "minor", "7A", "D"}, {"E", "major", "12B", "E"},
	} {
		got, tonic, ok := Camelot(c.key, c.scale)
		if !ok || got != c.want || tonic != c.tonic {
			t.Errorf("Camelot(%s %s) = %s %s %v, want %s %s", c.key, c.scale, got, tonic, ok, c.want, c.tonic)
		}
	}
	if _, _, ok := Camelot("H", "major"); ok {
		t.Error("unknown key accepted")
	}
	if got := camelotNeighbours("12A"); got[1] != "1A" || got[2] != "11A" || got[3] != "12B" {
		t.Errorf("neighbours of 12A: %v", got)
	}
	if got := camelotNeighbours("1B"); got[1] != "2B" || got[2] != "12B" || got[3] != "1A" {
		t.Errorf("neighbours of 1B: %v", got)
	}
}

func TestAnalysis(t *testing.T) {
	db := openTest(t)
	ctx := context.Background()
	ids := seed(t, db,
		TrackFile{Path: "a/1.flac", Title: "One", Artist: "X", Album: "A", Mtime: 1},
		TrackFile{Path: "a/2.flac", Title: "Two", Artist: "X", Album: "A", Mtime: 1},
		TrackFile{Path: "a/3.flac", Title: "Three", Artist: "X", Album: "A", Mtime: 1},
		TrackFile{Path: "a/4.flac", Title: "Four", Artist: "X", Album: "A", Mtime: 1},
	)
	if q, _ := db.AnalysisQueue(ctx, 10); len(q) != 4 {
		t.Fatalf("queue: %+v", q)
	}
	if _, err := db.TrackAnalysis(ctx, ids[0]); !errors.Is(err, ErrNotFound) {
		t.Fatalf("not analysed yet: %v", err)
	}

	report := func(id int64, bpm float64, key, scale string) {
		t.Helper()
		err := db.SaveAnalysis(ctx, id, AnalysisReport{FileMtime: 1, Analyzer: "test/1", BPM: &bpm,
			Key: key, Scale: scale, Energy: ptr(0.7), Genres: []GenreShare{{"house", 0.6}, {"disco", 0.4}}})
		if err != nil {
			t.Fatal(err)
		}
	}
	report(ids[0], 124, "A", "minor") // 8A
	report(ids[1], 126, "C", "major") // 8B: relative major, +1.6 %
	report(ids[2], 140, "E", "minor") // 9A: neighbour, but too fast
	if err := db.SaveAnalysis(ctx, ids[3], AnalysisReport{FileMtime: 1, Analyzer: "test/1", Error: "decode failed"}); err != nil {
		t.Fatal(err)
	}

	a, err := db.TrackAnalysis(ctx, ids[0])
	if err != nil || *a.Camelot != "8A" || *a.BPM != 124 || len(a.Genres) != 2 || a.Stale {
		t.Fatalf("analysis: %+v %v", a, err)
	}
	tr, _ := db.Track(ctx, ids[0])
	if tr.BPM == nil || *tr.BPM != 124 || *tr.Camelot != "8A" {
		t.Fatalf("track carries bpm/camelot: %+v", tr)
	}
	comp, err := db.CompatibleTracks(ctx, ids[0], 5)
	if err != nil || len(comp) != 1 || comp[0].ID != ids[1] {
		t.Fatalf("compatible: %+v %v", comp, err)
	}
	if st, _ := db.AnalysisStatus(ctx); st != (AnalysisStatus{Total: 4, Analyzed: 3, Failed: 1}) {
		t.Fatalf("status: %+v", st)
	}
	if q, _ := db.AnalysisQueue(ctx, 10); len(q) != 0 {
		t.Fatalf("queue after analysis (failures are not retried): %+v", q)
	}

	// Bad reports are refused.
	for _, r := range []AnalysisReport{
		{Analyzer: ""},
		{Analyzer: "x", Key: "H", Scale: "major"},
		{Analyzer: "x", BPM: ptr(1000.0)},
		{Analyzer: "x", Energy: ptr(1.5)},
	} {
		if err := db.SaveAnalysis(ctx, ids[0], r); !errors.Is(err, ErrInvalid) {
			t.Errorf("%+v: %v", r, err)
		}
	}
	if err := db.SaveAnalysis(ctx, 999, AnalysisReport{Analyzer: "x"}); !errors.Is(err, ErrNotFound) {
		t.Errorf("unknown track: %v", err)
	}

	// A modified file is queued again and its analysis marked stale.
	if err := db.WriteLibrary(ctx, func(w *LibWriter) error {
		f := TrackFile{Path: "a/1.flac", Title: "One", Artist: "X", Album: "A", Mtime: 2, Format: "flac", DurationMs: 1}
		if _, err := w.UpsertTrack(&f, ids[0]); err != nil {
			return err
		}
		return w.Finalize()
	}); err != nil {
		t.Fatal(err)
	}
	if q, _ := db.AnalysisQueue(ctx, 10); len(q) != 1 || q[0].ID != ids[0] || q[0].FileMtime != 2 {
		t.Fatalf("queue after change: %+v", q)
	}
	if a, _ := db.TrackAnalysis(ctx, ids[0]); !a.Stale {
		t.Fatal("not stale")
	}

	// Reset: one track, then everything.
	if err := db.ResetAnalysis(ctx, ids[1]); err != nil {
		t.Fatal(err)
	}
	if q, _ := db.AnalysisQueue(ctx, 10); len(q) != 2 {
		t.Fatalf("queue after reset: %+v", q)
	}
	if err := db.ResetAnalysis(ctx, 0); err != nil {
		t.Fatal(err)
	}
	if st, _ := db.AnalysisStatus(ctx); st.Pending != 4 {
		t.Fatalf("status after reset: %+v", st)
	}
}
