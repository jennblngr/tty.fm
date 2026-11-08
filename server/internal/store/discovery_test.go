package store

import (
	"context"
	"errors"
	"testing"
	"time"
)

func TestDiscoveries(t *testing.T) {
	db := openTest(t)
	ctx := context.Background()
	seed(t, db,
		TrackFile{Path: "a.flac", Title: "T", Artist: "Sia", Album: "A", Mtime: 1},
		TrackFile{Path: "b.flac", Title: "T", Artist: "Adele", Album: "B", Mtime: 1},
		TrackFile{Path: "c.flac", Title: "T", Artist: "Tove Lo", Album: "C", Mtime: 1},
	)
	now := time.Date(2026, 11, 9, 12, 0, 0, 0, time.UTC)
	artist := map[string]int64{}
	rows, _ := db.r.Query(`SELECT id, name FROM artists`)
	for rows.Next() {
		var id int64
		var n string
		_ = rows.Scan(&id, &n)
		artist[n] = id
	}
	rows.Close()

	// Liked, but no MusicBrainz id yet: nothing to look up.
	for _, n := range []string{"Sia", "Adele"} {
		if err := db.SetFavorite(ctx, "artists", artist[n], true); err != nil {
			t.Fatal(err)
		}
	}
	if jobs, _ := db.DiscoveryQueue(ctx, 10, now); len(jobs) != 0 {
		t.Fatalf("queue without mbids: %+v", jobs)
	}
	sia, adele := "mb-sia", "mb-adele"
	for n, m := range map[string]*string{"Sia": &sia, "Adele": &adele} {
		if err := db.SaveArtistReleases(ctx, artist[n], ReleaseReport{MBID: m}, now); err != nil {
			t.Fatal(err)
		}
	}
	jobs, err := db.DiscoveryQueue(ctx, 10, now)
	if err != nil || len(jobs) != 2 {
		t.Fatalf("queue: %+v %v", jobs, err)
	}

	save := func(name string, items []SimilarRecord) {
		t.Helper()
		if err := db.SaveSimilarArtists(ctx, artist[name], items, now); err != nil {
			t.Fatal(err)
		}
	}
	save("Sia", []SimilarRecord{
		{MBID: "mb-rihanna", Name: "Rihanna", Comment: "Barbadian R&B/pop singer", Score: 6000},
		{MBID: "mb-ellie", Name: "Ellie Goulding", Score: 3000},
		{MBID: "mb-tove", Name: "Tove Lo", Score: 2000}, // in the library (by name): left out
		{MBID: "mb-adele", Name: "Adele", Score: 1000},  // in the library (by mbid): left out
	})
	save("Adele", []SimilarRecord{
		{MBID: "mb-ellie", Name: "Ellie Goulding", Score: 500},
		{MBID: "mb-amy", Name: "Amy Winehouse", Score: 400},
	})
	got, err := db.Discoveries(ctx, 10)
	if err != nil {
		t.Fatal(err)
	}
	// Ellie Goulding: 0.5 (Sia) + 1 (Adele); Rihanna: 1; Amy: 0.8.
	if len(got) != 3 || got[0].Name != "Ellie Goulding" || got[0].Score != 1.5 ||
		got[0].Because[0] != "Adele" || got[0].Because[1] != "Sia" ||
		got[1].Name != "Rihanna" || got[1].Comment != "Barbadian R&B/pop singer" || got[2].Name != "Amy Winehouse" {
		t.Fatalf("discoveries: %+v", got)
	}
	if jobs, _ := db.DiscoveryQueue(ctx, 10, now.Add(time.Hour)); len(jobs) != 0 {
		t.Fatalf("queue after the lookups: %+v", jobs)
	}
	// Unliking Adele drops what came from her.
	if err := db.SetFavorite(ctx, "artists", artist["Adele"], false); err != nil {
		t.Fatal(err)
	}
	if got, _ := db.Discoveries(ctx, 10); len(got) != 2 || got[0].Name != "Rihanna" {
		t.Fatalf("after unliking: %+v", got)
	}
	if err := db.SaveSimilarArtists(ctx, artist["Sia"], []SimilarRecord{{Name: "X"}}, now); !errors.Is(err, ErrInvalid) {
		t.Errorf("no mbid: %v", err)
	}
	if err := db.SaveSimilarArtists(ctx, 999, nil, now); !errors.Is(err, ErrNotFound) {
		t.Errorf("unknown artist: %v", err)
	}
}
