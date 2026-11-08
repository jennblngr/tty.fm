package store

import (
	"context"
	"database/sql"
	"sort"
	"time"
)

// Followed artists: the most listened ones of the last autoFollowDays,
// with at least autoFollowMinMs of listening (at most autoFollowCount),
// plus those followed by hand, minus those the user stopped following.
const (
	autoFollowCount = 10
	autoFollowDays  = 90
	autoFollowMinMs = 30 * 60_000
	// A release this recent (or upcoming) puts the "•" by the artist.
	freshReleaseDays = 30
)

// FollowedArtist is an artist of "● artistes suivis".
type FollowedArtist struct {
	ID         int64       `json:"id"`
	Name       string      `json:"name"`
	CoverID    *int64      `json:"cover_id,omitempty"`
	Auto       bool        `json:"auto"` // followed for being listened, not by hand
	NewRelease *NewRelease `json:"new_release,omitempty"`
	listenedMs int64
}

// FollowedArtists lists the followed artists, those with a new release
// first, then the most listened.
func (db *DB) FollowedArtists(ctx context.Context, now time.Time) ([]FollowedArtist, error) {
	rows, err := db.r.QueryContext(ctx, `
		WITH listened AS (
			SELECT t.artist_id, SUM(p.listened_ms) AS ms FROM plays p JOIN tracks t ON t.id = p.track_id
			WHERE p.started_at >= ? GROUP BY t.artist_id
		), auto AS (
			SELECT artist_id FROM listened WHERE ms >= ? ORDER BY ms DESC, artist_id LIMIT ?
		)
		SELECT ar.id, ar.name,
		       (SELECT al.cover_id FROM albums al WHERE al.album_artist_id = ar.id AND al.cover_id IS NOT NULL
		        ORDER BY al.year DESC LIMIT 1),
		       f.followed IS NULL, COALESCE(l.ms, 0)
		FROM artists ar
		LEFT JOIN artist_follows f ON f.artist_id = ar.id
		LEFT JOIN listened l ON l.artist_id = ar.id
		WHERE (f.followed = 1 OR (f.followed IS NULL AND ar.id IN (SELECT artist_id FROM auto)))
		  AND EXISTS (SELECT 1 FROM tracks t WHERE t.missing_since IS NULL
		              AND (t.artist_id = ar.id OR t.album_id IN (SELECT id FROM albums WHERE album_artist_id = ar.id)))`,
		now.AddDate(0, 0, -autoFollowDays).UnixMilli(), autoFollowMinMs, autoFollowCount)
	if err != nil {
		return nil, err
	}
	out := []FollowedArtist{}
	byID := map[int64]int{}
	for rows.Next() {
		var a FollowedArtist
		var cover sql.NullInt64
		if err := rows.Scan(&a.ID, &a.Name, &cover, &a.Auto, &a.listenedMs); err != nil {
			rows.Close()
			return nil, err
		}
		if cover.Valid {
			a.CoverID = &cover.Int64
		}
		byID[a.ID] = len(out)
		out = append(out, a)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}
	// The latest fresh release of each (NewReleases is most recent first).
	releases, err := db.NewReleases(ctx, now, freshReleaseDays, 100)
	if err != nil {
		return nil, err
	}
	for i := range releases {
		if j, ok := byID[releases[i].ArtistID]; ok && out[j].NewRelease == nil && releases[i].AlbumID == nil {
			out[j].NewRelease = &releases[i]
		}
	}
	sort.SliceStable(out, func(a, b int) bool {
		if (out[a].NewRelease != nil) != (out[b].NewRelease != nil) {
			return out[a].NewRelease != nil
		}
		if out[a].listenedMs != out[b].listenedMs {
			return out[a].listenedMs > out[b].listenedMs
		}
		return out[a].Name < out[b].Name
	})
	return out, nil
}

// SetFollowed follows an artist by hand (on) or stops following it,
// automatic or not. ErrNotFound if the artist does not exist.
func (db *DB) SetFollowed(ctx context.Context, artistID int64, on bool) error {
	_, err := db.w.ExecContext(ctx, `INSERT INTO artist_follows (artist_id, followed, created_at) VALUES (?, ?, ?)
		ON CONFLICT (artist_id) DO UPDATE SET followed = excluded.followed, created_at = excluded.created_at`,
		artistID, on, now())
	if isFKError(err) {
		return ErrNotFound
	}
	return err
}
