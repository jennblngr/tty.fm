package store

import (
	"context"
	"sort"
	"strings"
	"time"
)

// NamedTotal is an artist or genre with its listening time.
type NamedTotal struct {
	ID   int64  `json:"id,omitempty"`
	Name string `json:"name"`
	Ms   int64  `json:"ms"`
}

// TrackCount is a track with how many times it was played.
type TrackCount struct {
	Track Track `json:"track"`
	Count int   `json:"count"`
}

// Stats summarises the listening history over a period.
type Stats struct {
	Days           int          `json:"days"` // 0 = all time
	From           int64        `json:"from"` // ms
	TotalMs        int64        `json:"total_ms"`
	PrevTotalMs    *int64       `json:"prev_total_ms,omitempty"` // same length just before
	Plays          int          `json:"plays"`
	DistinctTracks int          `json:"distinct_tracks"`
	WeekdayAvgMin  [7]int       `json:"weekday_avg_min"` // Monday first: average minutes per day
	HourMs         [24]int64    `json:"hour_ms"`
	FavoriteHour   *int         `json:"favorite_hour,omitempty"`
	TopArtists     []NamedTotal `json:"top_artists"`
	TopGenres      []NamedTotal `json:"top_genres"`
	TopTracks      []TrackCount `json:"top_tracks"`
	Discovery      *NamedTotal  `json:"discovery,omitempty"` // most listened artist first heard in the period
}

// ListeningStats aggregates plays since days ago (0: all time), in the
// server's local time zone (weekdays and hours).
func (db *DB) ListeningStats(ctx context.Context, days int, now time.Time) (Stats, error) {
	loc := now.Location()
	st := Stats{Days: days, TopArtists: []NamedTotal{}, TopGenres: []NamedTotal{}, TopTracks: []TrackCount{}}
	var from time.Time
	if days > 0 {
		y, m, d := now.Date()
		from = time.Date(y, m, d, 0, 0, 0, 0, loc).AddDate(0, 0, -(days - 1))
	}
	rows, err := db.r.QueryContext(ctx, `
		SELECT p.started_at, p.listened_ms, p.track_id, t.artist_id, ar.name, COALESCE(t.genre, '')
		FROM plays p JOIN tracks t ON t.id = p.track_id JOIN artists ar ON ar.id = t.artist_id
		WHERE p.started_at >= ? ORDER BY p.started_at`, from.UnixMilli())
	if err != nil {
		return st, err
	}
	defer rows.Close()

	artists := map[int64]*NamedTotal{}
	genres := map[string]*NamedTotal{}
	trackCounts := map[int64]int{}
	first := time.Time{}
	for rows.Next() {
		var at, ms, trackID, artistID int64
		var artist, genre string
		if err := rows.Scan(&at, &ms, &trackID, &artistID, &artist, &genre); err != nil {
			return st, err
		}
		t := time.UnixMilli(at).In(loc)
		if first.IsZero() {
			first = t
		}
		st.Plays++
		st.TotalMs += ms
		st.HourMs[t.Hour()] += ms
		st.WeekdayAvgMin[(int(t.Weekday())+6)%7] += int(ms / 1000) // seconds for now, averaged below
		trackCounts[trackID]++
		if a := artists[artistID]; a != nil {
			a.Ms += ms
		} else {
			artists[artistID] = &NamedTotal{ID: artistID, Name: artist, Ms: ms}
		}
		if genre = strings.TrimSpace(genre); genre != "" {
			key := strings.ToLower(genre)
			if g := genres[key]; g != nil {
				g.Ms += ms
			} else {
				genres[key] = &NamedTotal{Name: genre, Ms: ms}
			}
		}
	}
	if err := rows.Err(); err != nil {
		return st, err
	}
	if days == 0 {
		from = first
	}
	st.From = from.UnixMilli()
	st.DistinctTracks = len(trackCounts)

	// Average per weekday: seconds on that weekday / number of such days.
	if !from.IsZero() {
		var n [7]int
		y, m, d := from.Date()
		for day := time.Date(y, m, d, 0, 0, 0, 0, loc); !day.After(now); day = day.AddDate(0, 0, 1) {
			n[(int(day.Weekday())+6)%7]++
		}
		for i := range st.WeekdayAvgMin {
			if n[i] > 0 {
				st.WeekdayAvgMin[i] = st.WeekdayAvgMin[i] / 60 / n[i]
			}
		}
	}
	best := -1
	for h, ms := range st.HourMs {
		if ms > 0 && (best < 0 || ms > st.HourMs[best]) {
			best = h
		}
	}
	if best >= 0 {
		st.FavoriteHour = &best
	}

	st.TopArtists = topTotals(artists, 5)
	st.TopGenres = topTotals(genres, 5)

	type tc struct {
		id int64
		n  int
	}
	tcs := make([]tc, 0, len(trackCounts))
	for id, n := range trackCounts {
		tcs = append(tcs, tc{id, n})
	}
	sort.Slice(tcs, func(i, j int) bool { return tcs[i].n > tcs[j].n || (tcs[i].n == tcs[j].n && tcs[i].id < tcs[j].id) })
	for _, x := range tcs[:min(5, len(tcs))] {
		t, err := db.Track(ctx, x.id)
		if err != nil {
			continue // track gone from the library
		}
		st.TopTracks = append(st.TopTracks, TrackCount{Track: t, Count: x.n})
	}

	if days > 0 {
		// Previous period of the same length, for the trend.
		var prev int64
		if err := db.r.QueryRowContext(ctx, `SELECT COALESCE(SUM(listened_ms), 0) FROM plays
			WHERE started_at >= ? AND started_at < ?`,
			from.AddDate(0, 0, -days).UnixMilli(), from.UnixMilli()).Scan(&prev); err != nil {
			return st, err
		}
		st.PrevTotalMs = &prev

		// Discovery: the most listened artist whose first play is in the
		// period (meaningless when the whole history fits in the period).
		var historyStart int64
		if err := db.r.QueryRowContext(ctx, `SELECT COALESCE(MIN(started_at), 0) FROM plays`).Scan(&historyStart); err != nil {
			return st, err
		}
		for _, a := range topTotals(artists, len(artists)) {
			if historyStart >= from.UnixMilli() {
				break
			}
			var firstAt int64
			if err := db.r.QueryRowContext(ctx, `SELECT MIN(p.started_at) FROM plays p
				JOIN tracks t ON t.id = p.track_id WHERE t.artist_id = ?`, a.ID).Scan(&firstAt); err != nil {
				return st, err
			}
			if firstAt >= from.UnixMilli() {
				d := a
				st.Discovery = &d
				break
			}
		}
	}
	return st, nil
}

func topTotals[K comparable](m map[K]*NamedTotal, n int) []NamedTotal {
	out := make([]NamedTotal, 0, len(m))
	for _, v := range m {
		out = append(out, *v)
	}
	sort.Slice(out, func(i, j int) bool {
		return out[i].Ms > out[j].Ms || (out[i].Ms == out[j].Ms && out[i].Name < out[j].Name)
	})
	return out[:min(n, len(out))]
}
