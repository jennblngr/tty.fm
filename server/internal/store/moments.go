package store

import (
	"context"
	"strings"
	"time"
)

// Moments are the facts from the listening history behind the home
// header's message of the day, in the server's local time zone.
type Moments struct {
	Streak       Streak       `json:"streak"`
	Anniversary  *Anniversary `json:"anniversary,omitempty"`
	EveningGenre string       `json:"evening_genre,omitempty"`
}

// Streak counts consecutive days with at least one play. The current one
// ends today, or yesterday while nothing has been played today yet.
type Streak struct {
	Days   int `json:"days"`
	Record int `json:"record"` // longest streak before the current one
}

// Anniversary is a top 10 artist first played on this day years ago.
type Anniversary struct {
	ArtistID int64  `json:"artist_id"`
	Artist   string `json:"artist"`
	Years    int    `json:"years"`
}

// eveningMinMs is how much a genre must have been played in the evenings
// of the last 30 days to be suggested.
const eveningMinMs = 30 * 60_000

func (db *DB) Moments(ctx context.Context, now time.Time) (Moments, error) {
	var m Moments
	var err error
	if m.Streak, err = db.streak(ctx, now); err != nil {
		return m, err
	}
	if m.Anniversary, err = db.anniversary(ctx, now); err != nil {
		return m, err
	}
	m.EveningGenre, err = db.eveningGenre(ctx, now)
	return m, err
}

func (db *DB) streak(ctx context.Context, now time.Time) (Streak, error) {
	var st Streak
	rows, err := db.r.QueryContext(ctx, `SELECT started_at FROM plays ORDER BY started_at`)
	if err != nil {
		return st, err
	}
	defer rows.Close()
	loc := now.Location()
	day := func(t time.Time) time.Time { y, m, d := t.In(loc).Date(); return time.Date(y, m, d, 0, 0, 0, 0, loc) }
	var last time.Time
	run := 0
	for rows.Next() {
		var at int64
		if err := rows.Scan(&at); err != nil {
			return st, err
		}
		d := day(time.UnixMilli(at))
		switch {
		case d.Equal(last):
			continue
		case !last.IsZero() && d.Equal(last.AddDate(0, 0, 1)):
			run++
		default:
			st.Record = max(st.Record, run)
			run = 1
		}
		last = d
	}
	if err := rows.Err(); err != nil {
		return st, err
	}
	today := day(now)
	if last.Equal(today) || last.Equal(today.AddDate(0, 0, -1)) {
		st.Days = run
	} else {
		st.Record = max(st.Record, run)
	}
	return st, nil
}

func (db *DB) anniversary(ctx context.Context, now time.Time) (*Anniversary, error) {
	rows, err := db.r.QueryContext(ctx, `
		SELECT t.artist_id, ar.name, MIN(p.started_at)
		FROM plays p JOIN tracks t ON t.id = p.track_id JOIN artists ar ON ar.id = t.artist_id
		GROUP BY t.artist_id ORDER BY SUM(p.listened_ms) DESC, ar.name LIMIT 10`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var a Anniversary
		var first int64
		if err := rows.Scan(&a.ArtistID, &a.Artist, &first); err != nil {
			return nil, err
		}
		f := time.UnixMilli(first).In(now.Location())
		if f.Month() == now.Month() && f.Day() == now.Day() && f.Year() < now.Year() {
			a.Years = now.Year() - f.Year()
			return &a, nil
		}
	}
	return nil, rows.Err()
}

// eveningGenre is the genre most played between 18h and midnight over the
// last 30 days.
func (db *DB) eveningGenre(ctx context.Context, now time.Time) (string, error) {
	rows, err := db.r.QueryContext(ctx, `
		SELECT p.started_at, p.listened_ms, COALESCE(t.genre, '')
		FROM plays p JOIN tracks t ON t.id = p.track_id WHERE p.started_at >= ?`,
		now.AddDate(0, 0, -30).UnixMilli())
	if err != nil {
		return "", err
	}
	defer rows.Close()
	genres := map[string]*NamedTotal{}
	for rows.Next() {
		var at, ms int64
		var genre string
		if err := rows.Scan(&at, &ms, &genre); err != nil {
			return "", err
		}
		genre = strings.TrimSpace(genre)
		if genre == "" || time.UnixMilli(at).In(now.Location()).Hour() < 18 {
			continue
		}
		key := strings.ToLower(genre)
		if g := genres[key]; g != nil {
			g.Ms += ms
		} else {
			genres[key] = &NamedTotal{Name: genre, Ms: ms}
		}
	}
	if err := rows.Err(); err != nil {
		return "", err
	}
	if top := topTotals(genres, 1); len(top) > 0 && top[0].Ms >= eveningMinMs {
		return top[0].Name, nil
	}
	return "", nil
}
