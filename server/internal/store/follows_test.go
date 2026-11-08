package store

import (
	"context"
	"testing"
	"time"
)

func TestFollowedArtists(t *testing.T) {
	db := openTest(t)
	ctx := context.Background()
	ids := seed(t, db,
		TrackFile{Path: "a.flac", Title: "T", Artist: "Sia", Album: "A", Mtime: 1},
		TrackFile{Path: "b.flac", Title: "T", Artist: "Adele", Album: "B", Mtime: 1},
		TrackFile{Path: "c.flac", Title: "T", Artist: "Tove Lo", Album: "C", Mtime: 1},
	)
	now := time.Date(2026, 11, 9, 12, 0, 0, 0, time.UTC)
	artist := func(name string) int64 {
		t.Helper()
		var id int64
		if err := db.r.QueryRow(`SELECT id FROM artists WHERE name = ?`, name).Scan(&id); err != nil {
			t.Fatal(err)
		}
		return id
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
	// Listening alone follows no one.
	if _, err := db.AddPlays(ctx, 0, []Play{
		{TrackID: ids[0], StartedAt: now.Add(-time.Hour).UnixMilli(), ListenedMs: 3_600_000},
		{TrackID: ids[1], StartedAt: now.Add(-time.Hour).UnixMilli(), ListenedMs: 60_000},
	}); err != nil {
		t.Fatal(err)
	}
	if got := names(); len(got) != 0 {
		t.Fatalf("followed without a like: %v", got)
	}
	// Liked artists are followed, the most listened first.
	for _, n := range []string{"Adele", "Sia"} {
		if err := db.SetFavorite(ctx, "artists", artist(n), true); err != nil {
			t.Fatal(err)
		}
	}
	if got := names(); len(got) != 2 || got[0] != "Sia" || got[1] != "Adele" {
		t.Fatalf("liked: %v", got)
	}
	// A fresh release the library lacks puts the artist first, with it.
	soon := now.AddDate(0, 0, 10).Format("2006-01-02")
	if err := db.SaveArtistReleases(ctx, artist("Adele"), ReleaseReport{Releases: []ReleaseRecord{
		{MBID: "rg1", Title: "Next", Kind: "album", Released: soon},
		{MBID: "rg2", Title: "B", Kind: "album", Released: now.Format("2006-01-02")}, // already in the library
	}}, now); err != nil {
		t.Fatal(err)
	}
	fs, _ := db.FollowedArtists(ctx, now)
	if fs[0].Name != "Adele" || fs[0].NewRelease == nil || fs[0].NewRelease.Title != "Next" || fs[1].NewRelease != nil {
		t.Fatalf("new release first: %+v", fs)
	}
	// Unliking stops following.
	if err := db.SetFavorite(ctx, "artists", artist("Sia"), false); err != nil {
		t.Fatal(err)
	}
	if got := names(); len(got) != 1 || got[0] != "Adele" {
		t.Fatalf("after unliking: %v", got)
	}
}
