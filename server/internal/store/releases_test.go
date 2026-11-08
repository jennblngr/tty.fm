package store

import (
	"context"
	"errors"
	"testing"
	"time"
)

func TestNewReleases(t *testing.T) {
	db := openTest(t)
	ctx := context.Background()
	ids := seed(t, db,
		TrackFile{Path: "a/1.flac", Title: "One", Artist: "Adele", Album: "25 (Deluxe Edition)", Mtime: 1},
		TrackFile{Path: "b/1.flac", Title: "Two", Artist: "Sia", Album: "Reasonable Woman", Mtime: 1},
		TrackFile{Path: "c/1.flac", Title: "Three", Artist: "Tove Lo", Album: "Dirt Femme", Mtime: 1},
	)
	now := time.Date(2026, 11, 9, 12, 0, 0, 0, time.UTC)
	// Sia is listened the most: looked up first after never-checked order.
	if _, err := db.AddPlays(ctx, 0, []Play{{TrackID: ids[1], StartedAt: now.UnixMilli(), ListenedMs: 600_000}}); err != nil {
		t.Fatal(err)
	}
	jobs, err := db.ReleaseQueue(ctx, 10, now)
	if err != nil || len(jobs) != 3 || jobs[0].Name != "Sia" || jobs[0].Albums[0] != "Reasonable Woman" || jobs[0].MBID != nil {
		t.Fatalf("queue: %+v %v", jobs, err)
	}
	artist := map[string]int64{}
	for _, j := range jobs {
		artist[j.Name] = j.ArtistID
	}
	mbid := "2f548675-008d-4332-876c-108b0c7ab9c5"
	save := func(name string, r ReleaseReport) {
		t.Helper()
		if err := db.SaveArtistReleases(ctx, artist[name], r, now); err != nil {
			t.Fatal(err)
		}
	}
	save("Adele", ReleaseReport{MBID: &mbid, Releases: []ReleaseRecord{
		{MBID: "rg-25", Title: "25", Kind: "album", Released: "2026-10-20"},        // in the library, as a deluxe
		{MBID: "rg-new", Title: "Easy On Me", Kind: "single", Released: "2026-11"}, // a month only: the 1st
		{MBID: "rg-old", Title: "21", Kind: "album", Released: "2011-01-24"},       // too old
		{MBID: "rg-year", Title: "Live", Kind: "album", Released: "2026"},          // a bare year: too vague
	}})
	save("Sia", ReleaseReport{MBID: nil}) // not on MusicBrainz
	save("Tove Lo", ReleaseReport{Releases: []ReleaseRecord{{MBID: "rg-soon", Title: "Next", Kind: "ep", Released: "2026-12-05"}}})

	got, err := db.NewReleases(ctx, now, 90, 50)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 3 || got[0].Title != "Next" || !got[0].Upcoming || got[1].Title != "Easy On Me" || got[1].Upcoming ||
		got[2].Title != "25" || got[2].AlbumID == nil || got[1].AlbumID != nil || got[2].Artist != "Adele" {
		t.Fatalf("new releases: %+v", got)
	}

	// Checked this week: nobody to look up; a week later, all again.
	if jobs, _ := db.ReleaseQueue(ctx, 10, now.Add(time.Hour)); len(jobs) != 0 {
		t.Fatalf("queue after the lookups: %+v", jobs)
	}
	jobs, _ = db.ReleaseQueue(ctx, 10, now.AddDate(0, 0, 8))
	if len(jobs) != 3 || jobs[0].Name != "Sia" || jobs[1].Name != "Adele" || jobs[1].MBID == nil || *jobs[1].MBID != mbid {
		t.Fatalf("queue a week later (most listened first, known mbid kept): %+v", jobs)
	}

	// A new lookup replaces the releases.
	save("Adele", ReleaseReport{MBID: &mbid})
	if got, _ := db.NewReleases(ctx, now, 90, 50); len(got) != 1 {
		t.Fatalf("after replacing: %+v", got)
	}
	for _, bad := range []ReleaseReport{
		{Releases: []ReleaseRecord{{MBID: "x", Title: "T", Kind: "live", Released: "2026-01-01"}}},
		{Releases: []ReleaseRecord{{MBID: "x", Title: "T", Kind: "album", Released: "soon"}}},
		{Releases: []ReleaseRecord{{MBID: "", Title: "T", Kind: "album", Released: "2026"}}},
	} {
		if err := db.SaveArtistReleases(ctx, artist["Sia"], bad, now); !errors.Is(err, ErrInvalid) {
			t.Errorf("%+v: %v", bad, err)
		}
	}
	if err := db.SaveArtistReleases(ctx, 999, ReleaseReport{}, now); !errors.Is(err, ErrNotFound) {
		t.Errorf("unknown artist: %v", err)
	}
}

func TestReleaseKey(t *testing.T) {
	for a, b := range map[string]string{
		"25 (Deluxe Edition)":           "25",
		"Reasonable Woman [Remastered]": "reasonable woman",
		"Beyoncé!":                      "beyonce",
		"(What's the Story)":            "what s the story",
	} {
		if got := releaseKey(a); got != releaseKey(b) && got != b {
			t.Errorf("releaseKey(%q) = %q, want %q", a, got, b)
		}
	}
}
