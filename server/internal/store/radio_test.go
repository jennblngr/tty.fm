package store

import (
	"context"
	"errors"
	"testing"
)

func radioTitles(r Radio) []string {
	out := []string{}
	for _, t := range r.Items {
		out = append(out, t.Title)
	}
	return out
}

func TestRadio(t *testing.T) {
	db := openTest(t)
	ctx := context.Background()
	ids := seed(t, db,
		TrackFile{Path: "a/1.flac", Title: "A1", Artist: "X", Album: "A", Mtime: 1},
		TrackFile{Path: "a/2.flac", Title: "A2", Artist: "X", Album: "A", Mtime: 1},
		TrackFile{Path: "a/3.flac", Title: "A3", Artist: "X", Album: "A", Mtime: 1},
		TrackFile{Path: "b/1.flac", Title: "B1", Artist: "X", Album: "B", Mtime: 1},
		TrackFile{Path: "c/1.flac", Title: "C1", Artist: "Y", Album: "C", Mtime: 1},
		TrackFile{Path: "d/1.flac", Title: "D1", Artist: "Z", Album: "D", Mtime: 1},
		TrackFile{Path: "e/1.flac", Title: "E1", Artist: "W", Album: "E", Mtime: 1},
	)
	a1, a2, b1, c1, d1 := ids[0], ids[1], ids[3], ids[4], ids[5]
	bpm := func(v float64) *float64 { return &v }
	for i, e := range [][]float32{
		embedding(0, 1, 0),    // A1, the seed
		embedding(0, 1, 0.05), // A2, closest
		embedding(0, 1, 0.1),  // A3
		embedding(0, 1, 0.15), // B1
		embedding(0, 1, 0.2),  // C1
		embedding(0, 1, 0.3),  // D1
		embedding(0, 2, 1),    // E1, far
	} {
		rep := AnalysisReport{FileMtime: 1, Analyzer: "test/1", Embedding: e}
		if i == 0 || i == 5 { // A1 and D1 mix well: same key, close bpm
			rep.BPM, rep.Key, rep.Scale = bpm(120+float64(i)), "A", "minor"
		}
		if err := db.SaveAnalysis(ctx, ids[i], rep); err != nil {
			t.Fatal(err)
		}
	}

	r, err := db.Radio(ctx, RadioRequest{TrackID: a1, Limit: 4})
	if err != nil {
		t.Fatal(err)
	}
	if r.Mode != "similar" || r.Seed != (RadioSeed{"track", a1, "A1"}) {
		t.Fatalf("radio: %+v", r)
	}
	// D1 jumps ahead thanks to the mix bonus; one track per album (A3 left
	// out), X never twice in a row (B1 waits after C1).
	if got := radioTitles(r); len(got) != 4 || got[0] != "D1" || got[1] != "A2" || got[2] != "C1" || got[3] != "B1" {
		t.Fatalf("batch: %v", got)
	}
	if r.Items[1].Similarity == nil || *r.Items[1].Similarity < 0.99 {
		t.Errorf("similarity: %+v", r.Items[1].Similarity)
	}

	// Next batch: the played and queued tracks are left out, and the last
	// played artist does not come right back.
	r, err = db.Radio(ctx, RadioRequest{TrackID: a1, Recent: []int64{d1, a2}, Exclude: []int64{c1}, Limit: 2})
	if err != nil {
		t.Fatal(err)
	}
	if got := radioTitles(r); len(got) != 2 || got[0] == "A3" || got[0] == "B1" {
		t.Fatalf("next batch: %v", got)
	}
	for _, it := range r.Items {
		if it.ID == d1 || it.ID == a2 || it.ID == c1 || it.ID == a1 {
			t.Errorf("excluded track in the batch: %s", it.Title)
		}
	}

	// A small library: the rules loosen to fill the batch.
	r, _ = db.Radio(ctx, RadioRequest{TrackID: a1, Limit: 10})
	if len(r.Items) != 6 {
		t.Errorf("relaxed batch: %v", radioTitles(r))
	}

	// Hidden tracks are left out.
	if err := db.SetHidden(ctx, b1, true); err != nil {
		t.Fatal(err)
	}
	r, _ = db.Radio(ctx, RadioRequest{TrackID: a1, Limit: 10})
	for _, it := range r.Items {
		if it.ID == b1 {
			t.Errorf("hidden track in the batch")
		}
	}

	// Artist seed: the mean of its tracks.
	r, err = db.Radio(ctx, RadioRequest{ArtistID: r.Items[0].ArtistID, Limit: 3})
	if err != nil || r.Seed.Kind != "artist" || r.Seed.Name == "" || len(r.Items) != 3 || r.Mode != "similar" {
		t.Fatalf("artist radio: %+v, %v", r, err)
	}

	if _, err := db.Radio(ctx, RadioRequest{TrackID: 999}); !errors.Is(err, ErrNotFound) {
		t.Errorf("unknown track: %v", err)
	}
	if _, err := db.Radio(ctx, RadioRequest{ArtistID: 999}); !errors.Is(err, ErrNotFound) {
		t.Errorf("unknown artist: %v", err)
	}
	if _, err := db.Radio(ctx, RadioRequest{}); !errors.Is(err, ErrInvalid) {
		t.Errorf("no seed: %v", err)
	}
}

func TestRadioFallback(t *testing.T) {
	db := openTest(t)
	ctx := context.Background()
	ids := seed(t, db,
		TrackFile{Path: "a/1.flac", Title: "Seed", Artist: "X", Album: "A", Genre: "jazz", Mtime: 1},
		TrackFile{Path: "b/1.flac", Title: "Same artist", Artist: "X", Album: "B", Mtime: 1},
		TrackFile{Path: "c/1.flac", Title: "Same genre", Artist: "Y", Album: "C", Genre: "jazz", Mtime: 1},
		TrackFile{Path: "d/1.flac", Title: "Other", Artist: "Z", Album: "D", Genre: "rock", Mtime: 1},
	)
	// Not analysed: nothing to steer by, the radio still plays.
	r, err := db.Radio(ctx, RadioRequest{TrackID: ids[0], Limit: 10})
	if err != nil {
		t.Fatal(err)
	}
	got := radioTitles(r)
	if r.Mode != "fallback" || len(got) != 3 || got[2] != "Other" {
		t.Fatalf("fallback: %s %v", r.Mode, got)
	}
	for _, it := range r.Items {
		if it.Similarity != nil {
			t.Errorf("similarity in fallback: %+v", it)
		}
	}
}

func TestPickDiverse(t *testing.T) {
	tr := func(id, album, artist int64) RadioTrack {
		return RadioTrack{Track: Track{ID: id, AlbumID: album, ArtistID: artist}}
	}
	ids := func(c []RadioTrack, n int) []int64 {
		out := []int64{}
		for _, t := range c[:n] {
			out = append(out, t.ID)
		}
		return out
	}
	// Same album twice, the artist played last (3 waits for 1), a duplicate.
	c := []RadioTrack{tr(1, 10, 100), tr(2, 10, 100), tr(3, 11, 200), tr(3, 11, 200), tr(4, 12, 100), tr(5, 13, 300)}
	n := pickDiverse(c, 10, 200, false)
	if got := ids(c, n); len(got) != 4 || got[0] != 1 || got[1] != 3 || got[2] != 4 || got[3] != 5 {
		t.Errorf("strict: %v", got)
	}
	c = []RadioTrack{tr(1, 10, 100), tr(2, 10, 100), tr(3, 11, 200), tr(3, 11, 200), tr(4, 12, 100), tr(5, 13, 300)}
	if n := pickDiverse(c, 10, 200, true); n != 5 {
		t.Errorf("relaxed: %v", ids(c, n))
	}
}
