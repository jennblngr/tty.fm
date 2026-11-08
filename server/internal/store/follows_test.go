package store

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"
)

func TestFollowedArtists(t *testing.T) {
	db := openTest(t)
	ctx := context.Background()
	var files []TrackFile
	for i := range 12 {
		files = append(files, TrackFile{Path: fmt.Sprintf("%02d.flac", i), Title: "T", Artist: fmt.Sprintf("A%02d", i),
			Album: fmt.Sprintf("Al%02d", i), Mtime: 1})
	}
	ids := seed(t, db, files...)
	now := time.Date(2026, 11, 9, 12, 0, 0, 0, time.UTC)
	min := int64(60_000)
	var plays []Play
	// A00 to A10 listened 40 min to 30 min; A11 only 5 min (below the bar).
	for i := range 11 {
		plays = append(plays, Play{TrackID: ids[i], StartedAt: now.Add(-time.Hour).UnixMilli(), ListenedMs: int64(40-i) * min})
	}
	plays = append(plays, Play{TrackID: ids[11], StartedAt: now.Add(-time.Hour).UnixMilli(), ListenedMs: 5 * min})
	if _, err := db.AddPlays(ctx, 0, plays); err != nil {
		t.Fatal(err)
	}
	names := func() []string {
		t.Helper()
		fs, err := db.FollowedArtists(ctx, now)
		if err != nil {
			t.Fatal(err)
		}
		out := []string{}
		for _, f := range fs {
			out = append(out, f.Name)
		}
		return out
	}
	// The ten most listened above 30 min: A00…A09 (A10 is the eleventh).
	if got := names(); len(got) != 10 || got[0] != "A00" || got[9] != "A09" {
		t.Fatalf("auto: %v", got)
	}
	artist := func(name string) int64 {
		t.Helper()
		var id int64
		if err := db.r.QueryRow(`SELECT id FROM artists WHERE name = ?`, name).Scan(&id); err != nil {
			t.Fatal(err)
		}
		return id
	}
	// By hand: follow A11, stop following A00 (an automatic one).
	if err := db.SetFollowed(ctx, artist("A11"), true); err != nil {
		t.Fatal(err)
	}
	if err := db.SetFollowed(ctx, artist("A00"), false); err != nil {
		t.Fatal(err)
	}
	got := names()
	if len(got) != 10 || got[0] != "A01" || got[9] != "A11" {
		t.Fatalf("after the choices: %v", got)
	}
	fs, _ := db.FollowedArtists(ctx, now)
	if fs[9].Auto || !fs[0].Auto {
		t.Errorf("auto flags: %+v / %+v", fs[0], fs[9])
	}

	// A fresh release not in the library puts the artist first, with it.
	soon := now.AddDate(0, 0, 10).Format("2006-01-02")
	if err := db.SaveArtistReleases(ctx, artist("A05"), ReleaseReport{Releases: []ReleaseRecord{
		{MBID: "rg1", Title: "Next", Kind: "album", Released: soon},
		{MBID: "rg2", Title: "Al05", Kind: "album", Released: now.Format("2006-01-02")}, // already in the library
	}}, now); err != nil {
		t.Fatal(err)
	}
	fs, _ = db.FollowedArtists(ctx, now)
	if fs[0].Name != "A05" || fs[0].NewRelease == nil || fs[0].NewRelease.Title != "Next" || fs[1].NewRelease != nil {
		t.Fatalf("new release first: %+v", fs[:2])
	}
	// An artist followed by hand is looked up on MusicBrainz too.
	jobs, _ := db.ReleaseQueue(ctx, 50, now)
	found := false
	for _, j := range jobs {
		found = found || j.Name == "A11"
	}
	if !found {
		t.Errorf("A11 not in the release queue: %+v", jobs)
	}
	if err := db.SetFollowed(ctx, 999, true); !errors.Is(err, ErrNotFound) {
		t.Errorf("unknown artist: %v", err)
	}
}
