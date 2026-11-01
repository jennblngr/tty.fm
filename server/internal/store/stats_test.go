package store

import (
	"context"
	"testing"
	"time"
)

func TestListeningStats(t *testing.T) {
	db := openTest(t)
	ctx := context.Background()
	ids := seed(t, db,
		TrackFile{Path: "a.flac", Title: "Old", Artist: "Veteran", Album: "A", Genre: "Rock"},
		TrackFile{Path: "b.flac", Title: "New", Artist: "Newcomer", Album: "B", Genre: "Pop"},
		TrackFile{Path: "c.flac", Title: "Hit", Artist: "Veteran", Album: "A", Genre: "rock"},
	)
	loc := time.UTC
	now := time.Date(2026, 11, 1, 20, 0, 0, 0, loc) // a Sunday
	at := func(daysAgo, hour int) int64 {
		return time.Date(2026, 11, 1-daysAgo, hour, 0, 0, 0, loc).UnixMilli()
	}
	min := int64(60_000)
	plays := []Play{
		{TrackID: ids[0], StartedAt: at(60, 9), ListenedMs: 10 * min}, // before the period: Veteran is not new
		{TrackID: ids[0], StartedAt: at(10, 23), ListenedMs: 3 * min}, // previous 7-day period
		{TrackID: ids[2], StartedAt: at(0, 23), ListenedMs: 4 * min},  // Sunday 23h
		{TrackID: ids[2], StartedAt: at(0, 23), ListenedMs: 4 * min},
		{TrackID: ids[1], StartedAt: at(1, 8), ListenedMs: 5 * min}, // Saturday, first ever play of Newcomer
	}
	if _, err := db.AddPlays(ctx, 0, plays); err != nil {
		t.Fatal(err)
	}
	st, err := db.ListeningStats(ctx, 7, now)
	if err != nil {
		t.Fatal(err)
	}
	if st.Plays != 3 || st.TotalMs != 13*min || st.DistinctTracks != 2 {
		t.Fatalf("totals: %+v", st)
	}
	if st.PrevTotalMs == nil || *st.PrevTotalMs != 3*min {
		t.Fatalf("previous period: %v", st.PrevTotalMs)
	}
	if st.WeekdayAvgMin[6] != 8 || st.WeekdayAvgMin[5] != 5 || st.WeekdayAvgMin[0] != 0 { // one Sunday, one Saturday in 7 days
		t.Fatalf("weekdays: %v", st.WeekdayAvgMin)
	}
	if st.FavoriteHour == nil || *st.FavoriteHour != 23 {
		t.Fatalf("favorite hour: %v", st.FavoriteHour)
	}
	if len(st.TopArtists) != 2 || st.TopArtists[0].Name != "Veteran" || st.TopArtists[0].Ms != 8*min {
		t.Fatalf("top artists: %+v", st.TopArtists)
	}
	if len(st.TopGenres) != 2 || st.TopGenres[0].Ms != 8*min { // "Rock" and "rock" merged
		t.Fatalf("top genres: %+v", st.TopGenres)
	}
	if len(st.TopTracks) == 0 || st.TopTracks[0].Track.Title != "Hit" || st.TopTracks[0].Count != 2 {
		t.Fatalf("top tracks: %+v", st.TopTracks)
	}
	if st.Discovery == nil || st.Discovery.Name != "Newcomer" {
		t.Fatalf("discovery: %+v", st.Discovery)
	}
	all, err := db.ListeningStats(ctx, 0, now)
	if err != nil || all.Plays != 5 || all.PrevTotalMs != nil || all.Discovery != nil {
		t.Fatalf("all time: %+v %v", all, err)
	}
}
