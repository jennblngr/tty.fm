package store

import (
	"context"
	"testing"
	"time"
)

func TestMoments(t *testing.T) {
	db := openTest(t)
	ctx := context.Background()
	ids := seed(t, db,
		TrackFile{Path: "a.flac", Title: "Old", Artist: "Veteran", Album: "A", Genre: "Jazz"},
		TrackFile{Path: "b.flac", Title: "New", Artist: "Newcomer", Album: "B", Genre: "Lo-Fi"},
	)
	loc := time.UTC
	now := time.Date(2026, 11, 3, 12, 0, 0, 0, loc)
	at := func(y int, m time.Month, d, hour int) int64 {
		return time.Date(y, m, d, hour, 0, 0, 0, loc).UnixMilli()
	}
	min := int64(60_000)
	plays := []Play{
		{TrackID: ids[0], StartedAt: at(2025, 11, 3, 9), ListenedMs: 60 * min}, // Veteran first heard a year ago today
		// A 3-day streak in October, then 4 days up to yesterday.
		{TrackID: ids[0], StartedAt: at(2026, 10, 10, 9), ListenedMs: min},
		{TrackID: ids[0], StartedAt: at(2026, 10, 11, 9), ListenedMs: min},
		{TrackID: ids[0], StartedAt: at(2026, 10, 12, 9), ListenedMs: min},
		{TrackID: ids[1], StartedAt: at(2026, 10, 30, 21), ListenedMs: 20 * min},
		{TrackID: ids[1], StartedAt: at(2026, 10, 31, 22), ListenedMs: 20 * min},
		{TrackID: ids[0], StartedAt: at(2026, 11, 1, 19), ListenedMs: 10 * min},
		{TrackID: ids[0], StartedAt: at(2026, 11, 2, 9), ListenedMs: 90 * min}, // morning: not an evening genre
	}
	if _, err := db.AddPlays(ctx, 0, plays); err != nil {
		t.Fatal(err)
	}
	m, err := db.Moments(ctx, now)
	if err != nil {
		t.Fatal(err)
	}
	if m.Streak != (Streak{Days: 4, Record: 3}) {
		t.Fatalf("streak: %+v", m.Streak)
	}
	if m.Anniversary == nil || m.Anniversary.Artist != "Veteran" || m.Anniversary.Years != 1 {
		t.Fatalf("anniversary: %+v", m.Anniversary)
	}
	if m.EveningGenre != "Lo-Fi" {
		t.Fatalf("evening genre: %q", m.EveningGenre)
	}

	// Two days without a play: the streak is over and becomes the record.
	m, err = db.Moments(ctx, now.AddDate(0, 0, 2))
	if err != nil {
		t.Fatal(err)
	}
	if m.Streak != (Streak{Days: 0, Record: 4}) || m.Anniversary != nil {
		t.Fatalf("later: %+v", m)
	}
}
