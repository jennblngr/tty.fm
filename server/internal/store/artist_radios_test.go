package store

import (
	"context"
	"testing"
	"time"
)

func TestArtistRadios(t *testing.T) {
	db := openTest(t)
	ctx := context.Background()
	ids := seed(t, db,
		TrackFile{Path: "a.flac", Title: "T", Artist: "Sia", Album: "A", Mtime: 1},
		TrackFile{Path: "b.flac", Title: "T", Artist: "Adele", Album: "B", Mtime: 1},
		TrackFile{Path: "c.flac", Title: "T", Artist: "Tove Lo", Album: "C", Mtime: 1},
		TrackFile{Path: "d.flac", Title: "T", Artist: "Lorde", Album: "D", Mtime: 1},
	)
	now := time.Date(2026, 11, 9, 12, 0, 0, 0, time.UTC)
	names := func(limit int) []string {
		t.Helper()
		rs, err := db.ArtistRadios(ctx, now, limit)
		if err != nil {
			t.Fatal(err)
		}
		out := []string{}
		for _, r := range rs {
			out = append(out, r.Name)
		}
		return out
	}
	if got := names(8); len(got) != 0 {
		t.Fatalf("nothing liked or played: %v", got)
	}
	if _, err := db.AddPlays(ctx, 0, []Play{
		{TrackID: ids[0], StartedAt: now.Add(-time.Hour).UnixMilli(), ListenedMs: 60_000},
		{TrackID: ids[1], StartedAt: now.Add(-time.Hour).UnixMilli(), ListenedMs: 600_000},
		{TrackID: ids[2], StartedAt: now.Add(-time.Hour).UnixMilli(), ListenedMs: 300_000},
		// Too old to count.
		{TrackID: ids[3], StartedAt: now.AddDate(0, 0, -40).UnixMilli(), ListenedMs: 900_000},
	}); err != nil {
		t.Fatal(err)
	}
	var sia int64
	if err := db.r.QueryRow(`SELECT id FROM artists WHERE name = 'Sia'`).Scan(&sia); err != nil {
		t.Fatal(err)
	}
	if err := db.SetFavorite(ctx, "artists", sia, true); err != nil {
		t.Fatal(err)
	}
	// Liked first, then the most listened.
	if got := names(8); len(got) != 3 || got[0] != "Sia" || got[1] != "Adele" || got[2] != "Tove Lo" {
		t.Fatalf("radios: %v", got)
	}
	if got := names(2); len(got) != 2 || got[1] != "Adele" {
		t.Fatalf("limit: %v", got)
	}
	rs, _ := db.ArtistRadios(ctx, now, 8)
	if !rs[0].Liked || rs[1].Liked {
		t.Fatalf("liked flags: %+v", rs)
	}
}
