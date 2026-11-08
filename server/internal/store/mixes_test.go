package store

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"
)

func TestDailyMixes(t *testing.T) {
	db := openTest(t)
	ctx := context.Background()
	// Two sounds (axes 0 and 5), 22 tracks each: 12 listened, 10 never.
	var files []TrackFile
	for g, axis := range []int{0, 5} {
		for i := range 22 {
			files = append(files, TrackFile{
				Path:   fmt.Sprintf("%d/%02d.flac", g, i),
				Title:  fmt.Sprintf("G%d-%02d", g, i),
				Artist: fmt.Sprintf("Artist %d-%d", g, i%6),
				Album:  fmt.Sprintf("Album %d-%d", g, i%8),
				Mtime:  1,
			})
			_ = axis
		}
	}
	ids := seed(t, db, files...)
	group := map[int64]int{}
	for i, id := range ids {
		g, n := i/22, i%22
		axis := []int{0, 5}[g]
		vec := embedding(axis, axis+1, float32(n)/40)
		genres := []GenreShare{{Name: "électro", Share: 0.6}, {Name: []string{"Synthwave", "Ballad"}[g], Share: 0.3}}
		mood := []string{"festif · joyeux", "calme"}[g]
		if err := db.SaveAnalysis(ctx, id, AnalysisReport{FileMtime: 1, Analyzer: "test/1", Embedding: vec, Genres: genres, Mood: mood}); err != nil {
			t.Fatal(err)
		}
		group[id] = g
	}
	now := time.Date(2026, 11, 9, 4, 0, 0, 0, time.UTC)
	var plays []Play
	for i, id := range ids {
		if i%22 < 12 {
			plays = append(plays, Play{TrackID: id, StartedAt: now.Add(-time.Hour).UnixMilli(), ListenedMs: 180_000})
		}
	}
	// The same song twice (an album and its deluxe edition): once in a mix.
	dup := seed(t, db, TrackFile{Path: "0/dup.flac", Title: "G0-13", Artist: "Artist 0-1", Album: "Deluxe", Mtime: 1})[0]
	if err := db.SaveAnalysis(ctx, dup, AnalysisReport{FileMtime: 1, Analyzer: "test/1", Embedding: embedding(0, 1, 13.0/40)}); err != nil {
		t.Fatal(err)
	}
	group[dup] = 0
	// A skipped play and a short one do not count.
	plays = append(plays, Play{TrackID: ids[20], StartedAt: now.Add(-time.Hour).UnixMilli(), ListenedMs: 180_000, Skipped: true},
		Play{TrackID: ids[21], StartedAt: now.Add(-time.Hour).UnixMilli(), ListenedMs: 10_000})
	if _, err := db.AddPlays(ctx, 0, plays); err != nil {
		t.Fatal(err)
	}

	n, err := db.ComputeDailyMixes(ctx, now)
	if err != nil || n != 2 {
		t.Fatalf("computed %d mixes, %v", n, err)
	}
	mixes, err := db.DailyMixes(ctx, true)
	if err != nil || len(mixes) != 2 {
		t.Fatalf("mixes: %d, %v", len(mixes), err)
	}
	seen := map[int64]bool{}
	for i, m := range mixes {
		if m.Name != fmt.Sprintf("mix_%02d", i+1) || m.Day != "2026-11-09" || m.TrackCount != len(m.Tracks) || len(m.Artists) == 0 {
			t.Fatalf("mix %d: %+v", i, m)
		}
		g := group[m.Tracks[0].ID]
		want := []string{"synthwave · festif", "ballad · calme"}[g]
		if m.Description != want {
			t.Errorf("mix %d description %q, want %q", i, m.Description, want)
		}
		fresh := 0
		titles := map[string]bool{}
		for _, tr := range m.Tracks {
			if titles[tr.Title+tr.Artist] {
				t.Errorf("mix %d has %s twice", i, tr.Title)
			}
			titles[tr.Title+tr.Artist] = true
			if group[tr.ID] != g {
				t.Errorf("mix %d mixes the two sounds: %s", i, tr.Title)
			}
			if seen[tr.ID] {
				t.Errorf("%s in two mixes", tr.Title)
			}
			seen[tr.ID] = true
			if tr.ID == ids[g*22+20] || tr.ID == ids[g*22+21] || (tr.Title[len(tr.Title)-2:] >= "12") {
				fresh++
			}
		}
		if fresh == 0 || m.TrackCount < 15 {
			t.Errorf("mix %d: %d tracks, %d never really played", i, m.TrackCount, fresh)
		}
	}

	// Same day, same data: same mixes.
	before := mixes
	if _, err := db.ComputeDailyMixes(ctx, now.Add(time.Hour)); err != nil {
		t.Fatal(err)
	}
	after, _ := db.DailyMixes(ctx, true)
	for i := range before {
		if fmt.Sprint(trackIDs(before[i].Tracks)) != fmt.Sprint(trackIDs(after[i].Tracks)) {
			t.Fatalf("mix %d changed within the day", i)
		}
	}

	// An archived track leaves the mix it is in.
	first := after[0].Tracks[0]
	if err := db.SetHidden(ctx, first.ID, true); err != nil {
		t.Fatal(err)
	}
	m, err := db.DailyMix(ctx, 1)
	if err != nil || m.TrackCount != after[0].TrackCount-1 || len(m.Tracks) == 0 || m.Tracks[0].ID == first.ID {
		t.Fatalf("after archiving: %+v %v", m, err)
	}
	if _, err := db.DailyMix(ctx, 9); !errors.Is(err, ErrNotFound) {
		t.Errorf("unknown mix: %v", err)
	}
	summary, _ := db.DailyMixes(ctx, false)
	if len(summary) != 2 || summary[0].Tracks != nil || len(summary[0].CoverIDs) > 4 || summary[0].DurationMs == 0 {
		t.Errorf("summary: %+v", summary[0])
	}

	// Too little history the next day: no new mixes, yesterday's stay.
	later := now.AddDate(0, 0, 40)
	if n, err := db.ComputeDailyMixes(ctx, later); err != nil || n != 0 {
		t.Fatalf("without history: %d, %v", n, err)
	}
	if has, _ := db.HasMixesFor(ctx, later); has {
		t.Error("mixes for a day without history")
	}
	if got, _ := db.DailyMixes(ctx, false); len(got) != 2 {
		t.Errorf("yesterday's mixes are gone: %d", len(got))
	}
}

func trackIDs(ts []Track) []int64 {
	out := make([]int64, len(ts))
	for i, t := range ts {
		out[i] = t.ID
	}
	return out
}
