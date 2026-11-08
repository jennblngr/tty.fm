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

func TestListeningStatsTempo(t *testing.T) {
	db := openTest(t)
	ctx := context.Background()
	ids := seed(t, db,
		TrackFile{Path: "a.flac", Title: "Slow", Artist: "X", Album: "A", Mtime: 1},
		TrackFile{Path: "b.flac", Title: "Fast", Artist: "X", Album: "A", Mtime: 1},
		TrackFile{Path: "c.flac", Title: "Mid", Artist: "X", Album: "A", Mtime: 1},
		TrackFile{Path: "d.flac", Title: "Unanalysed", Artist: "X", Album: "A", Mtime: 1},
	)
	for i, bpm := range []float64{78, 150, 110} {
		if err := db.SaveAnalysis(ctx, ids[i], AnalysisReport{FileMtime: 1, Analyzer: "test/1", BPM: &bpm}); err != nil {
			t.Fatal(err)
		}
	}
	loc := time.UTC
	now := time.Date(2026, 11, 1, 22, 0, 0, 0, loc)
	at := func(daysAgo, hour int) int64 { return time.Date(2026, 11, 1-daysAgo, hour, 0, 0, 0, loc).UnixMilli() }
	min := int64(60_000)
	if _, err := db.AddPlays(ctx, 0, []Play{
		{TrackID: ids[1], StartedAt: at(0, 8), ListenedMs: 3 * min},   // morning, 150
		{TrackID: ids[0], StartedAt: at(0, 21), ListenedMs: 1 * min},  // evening, 78
		{TrackID: ids[2], StartedAt: at(0, 21), ListenedMs: 1 * min},  // evening, 110
		{TrackID: ids[3], StartedAt: at(0, 14), ListenedMs: 9 * min},  // not analysed: left out
		{TrackID: ids[2], StartedAt: at(10, 14), ListenedMs: 2 * min}, // previous period, 110
	}); err != nil {
		t.Fatal(err)
	}
	st, err := db.ListeningStats(ctx, 7, now)
	if err != nil {
		t.Fatal(err)
	}
	tp := st.Tempo
	if tp.AnalyzedMs != 5*min || tp.BandMs != [5]int64{1 * min, 0, 1 * min, 0, 3 * min} {
		t.Fatalf("bands: %+v", tp)
	}
	// (150×3 + 78 + 110) / 5 = 127.6
	if tp.AvgBPM == nil || *tp.AvgBPM != 128 || tp.PrevAvgBPM == nil || *tp.PrevAvgBPM != 110 {
		t.Fatalf("average: %v, previous %v", tp.AvgBPM, tp.PrevAvgBPM)
	}
	if tp.MorningBPM == nil || *tp.MorningBPM != 150 || tp.EveningBPM == nil || *tp.EveningBPM != 94 {
		t.Fatalf("morning / evening: %v %v", tp.MorningBPM, tp.EveningBPM)
	}
	if tp.Fastest == nil || tp.Fastest.Title != "Fast" || tp.Slowest == nil || tp.Slowest.Title != "Slow" {
		t.Fatalf("fastest / slowest: %+v %+v", tp.Fastest, tp.Slowest)
	}

	// Nothing analysed listened: an empty tempo, no average.
	empty, err := db.ListeningStats(ctx, 1, now.AddDate(0, 0, 30))
	if err != nil || empty.Tempo.AvgBPM != nil || empty.Tempo.AnalyzedMs != 0 {
		t.Fatalf("empty: %+v %v", empty.Tempo, err)
	}
}

func TestAnalysisEnabled(t *testing.T) {
	db := openTest(t)
	ctx := context.Background()
	seed(t, db, TrackFile{Path: "a.flac", Title: "A", Artist: "X", Album: "A", Mtime: 1})
	st, err := db.AnalysisStatus(ctx)
	if err != nil || !st.Enabled || st.Pending != 1 {
		t.Fatalf("default: %+v %v", st, err)
	}
	if err := db.SetAnalysisEnabled(ctx, false); err != nil {
		t.Fatal(err)
	}
	if st, _ := db.AnalysisStatus(ctx); st.Enabled {
		t.Fatalf("off: %+v", st)
	}
	if err := db.SetAnalysisEnabled(ctx, true); err != nil {
		t.Fatal(err)
	}
	if on, _ := db.AnalysisEnabled(ctx); !on {
		t.Fatal("back on")
	}
}
