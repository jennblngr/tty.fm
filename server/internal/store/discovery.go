package store

import (
	"context"
	"fmt"
	"sort"
	"strings"
	"time"
)

// Discovery: artists similar to the liked ones (ListenBrainz), those the
// library lacks first-hand. The recommender asks which liked artists to
// look up (DiscoveryQueue: their MusicBrainz id is known from the releases
// lookup) and sends what it found (SaveSimilarArtists).

const similarRecheck = 7 * 24 * time.Hour

// SimilarJob is a liked artist to look up on ListenBrainz.
type SimilarJob struct {
	ArtistID int64  `json:"artist_id"`
	Name     string `json:"name"`
	MBID     string `json:"mbid"`
}

// SimilarRecord is an artist ListenBrainz finds similar.
type SimilarRecord struct {
	MBID    string  `json:"mbid"`
	Name    string  `json:"name"`
	Comment string  `json:"comment"`
	Score   float64 `json:"score"`
}

// Discovery is an artist to discover: similar to liked ones, not in the
// library.
type Discovery struct {
	MBID    string   `json:"mbid"`
	Name    string   `json:"name"`
	Comment string   `json:"comment,omitempty"`
	Score   float64  `json:"score"`   // 0..n: the sum of its closeness to each liked artist (1 = the closest)
	Because []string `json:"because"` // the liked artists it is close to, closest first
}

// DiscoveryQueue lists the liked artists with a known MusicBrainz id whose
// similar artists were never fetched or are more than a week old.
func (db *DB) DiscoveryQueue(ctx context.Context, limit int, now time.Time) ([]SimilarJob, error) {
	rows, err := db.r.QueryContext(ctx, `
		SELECT ar.id, ar.name, COALESCE(NULLIF(ar.mbid, ''), l.mbid)
		FROM favorite_artists f JOIN artists ar ON ar.id = f.artist_id
		LEFT JOIN artist_lookups l ON l.artist_id = ar.id
		LEFT JOIN similar_lookups s ON s.artist_id = ar.id
		WHERE COALESCE(NULLIF(ar.mbid, ''), l.mbid) IS NOT NULL
		  AND (s.checked_at IS NULL OR s.checked_at < ?)
		ORDER BY s.checked_at IS NOT NULL, s.checked_at, ar.id LIMIT ?`,
		now.Add(-similarRecheck).Unix(), min(clampLimit(limit), 50))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []SimilarJob{}
	for rows.Next() {
		var j SimilarJob
		if err := rows.Scan(&j.ArtistID, &j.Name, &j.MBID); err != nil {
			return nil, err
		}
		out = append(out, j)
	}
	return out, rows.Err()
}

// SaveSimilarArtists replaces the similar artists of a liked artist.
func (db *DB) SaveSimilarArtists(ctx context.Context, artistID int64, items []SimilarRecord, now time.Time) error {
	for _, it := range items {
		if it.MBID == "" || strings.TrimSpace(it.Name) == "" {
			return fmt.Errorf("%w: a similar artist needs an mbid and a name", ErrInvalid)
		}
	}
	tx, err := db.w.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback() //nolint:errcheck // no-op after Commit
	_, err = tx.ExecContext(ctx, `INSERT INTO similar_lookups (artist_id, checked_at) VALUES (?, ?)
		ON CONFLICT (artist_id) DO UPDATE SET checked_at = excluded.checked_at`, artistID, now.Unix())
	if isFKError(err) {
		return ErrNotFound
	} else if err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `DELETE FROM similar_artists WHERE artist_id = ?`, artistID); err != nil {
		return err
	}
	for _, it := range items {
		if _, err := tx.ExecContext(ctx, `INSERT INTO similar_artists (artist_id, mbid, name, comment, score)
			VALUES (?, ?, ?, ?, ?) ON CONFLICT DO NOTHING`,
			artistID, it.MBID, strings.TrimSpace(it.Name), strings.TrimSpace(it.Comment), it.Score); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// Discoveries ranks the artists similar to the liked ones that the library
// does not have (by MusicBrainz id or by name): each liked artist gives its
// list a weight of 1 for its closest artist, down to 0, and the weights add
// up, so an artist close to several liked ones comes first.
func (db *DB) Discoveries(ctx context.Context, limit int) ([]Discovery, error) {
	// What the library has: names and known MusicBrainz ids.
	have := map[string]bool{}
	rows, err := db.r.QueryContext(ctx, `SELECT ar.name, COALESCE(NULLIF(ar.mbid, ''), l.mbid, '')
		FROM artists ar LEFT JOIN artist_lookups l ON l.artist_id = ar.id`)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var name, mbid string
		if err := rows.Scan(&name, &mbid); err != nil {
			rows.Close()
			return nil, err
		}
		have["name:"+MatchKey(name)] = true
		if mbid != "" {
			have["mbid:"+mbid] = true
		}
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}

	rows, err = db.r.QueryContext(ctx, `
		SELECT s.mbid, s.name, s.comment, s.score / m.top, ar.name
		FROM similar_artists s
		JOIN favorite_artists f ON f.artist_id = s.artist_id
		JOIN artists ar ON ar.id = s.artist_id
		JOIN (SELECT artist_id, MAX(score) AS top FROM similar_artists GROUP BY artist_id) m ON m.artist_id = s.artist_id
		WHERE m.top > 0`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	type acc struct {
		d       Discovery
		because map[string]float64
	}
	byMBID := map[string]*acc{}
	for rows.Next() {
		var mbid, name, comment, seed string
		var w float64
		if err := rows.Scan(&mbid, &name, &comment, &w, &seed); err != nil {
			return nil, err
		}
		if have["mbid:"+mbid] || have["name:"+MatchKey(name)] {
			continue
		}
		a := byMBID[mbid]
		if a == nil {
			a = &acc{d: Discovery{MBID: mbid, Name: name, Comment: comment}, because: map[string]float64{}}
			byMBID[mbid] = a
		}
		a.d.Score += w
		a.because[seed] = w
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	out := make([]Discovery, 0, len(byMBID))
	for _, a := range byMBID {
		for seed := range a.because {
			a.d.Because = append(a.d.Because, seed)
		}
		sort.Slice(a.d.Because, func(i, j int) bool {
			bi, bj := a.because[a.d.Because[i]], a.because[a.d.Because[j]]
			return bi > bj || bi == bj && a.d.Because[i] < a.d.Because[j]
		})
		a.d.Score = float64(int(a.d.Score*1000+0.5)) / 1000
		out = append(out, a.d)
	}
	sort.Slice(out, func(i, j int) bool {
		return out[i].Score > out[j].Score || out[i].Score == out[j].Score && out[i].Name < out[j].Name
	})
	return out[:min(min(clampLimit(limit), 100), len(out))], nil
}
