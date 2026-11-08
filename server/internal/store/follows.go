package store

import (
	"context"
	"database/sql"
	"sort"
	"time"
)

// Followed artists are the liked ones (favorite_artists): liking an artist
// follows its releases. A release this recent (or upcoming) puts the "•"
// by the artist.
const freshReleaseDays = 30

// FollowedArtist is an artist of "● artistes suivis".
type FollowedArtist struct {
	ID         int64       `json:"id"`
	Name       string      `json:"name"`
	CoverID    *int64      `json:"cover_id,omitempty"`
	NewRelease *NewRelease `json:"new_release,omitempty"`
	listenedMs int64
}

// FollowedArtists lists the liked artists still in the library, those with
// a new release first, then the most listened of the last 90 days.
func (db *DB) FollowedArtists(ctx context.Context, now time.Time) ([]FollowedArtist, error) {
	rows, err := db.r.QueryContext(ctx, `
		SELECT ar.id, ar.name,
		       (SELECT al.cover_id FROM albums al WHERE al.album_artist_id = ar.id AND al.cover_id IS NOT NULL
		        ORDER BY al.year DESC LIMIT 1),
		       (SELECT COALESCE(SUM(p.listened_ms), 0) FROM plays p JOIN tracks t ON t.id = p.track_id
		        WHERE t.artist_id = ar.id AND p.started_at >= ?)
		FROM favorite_artists f JOIN artists ar ON ar.id = f.artist_id
		WHERE EXISTS (SELECT 1 FROM tracks t WHERE t.missing_since IS NULL
		              AND (t.artist_id = ar.id OR t.album_id IN (SELECT id FROM albums WHERE album_artist_id = ar.id)))`,
		now.AddDate(0, 0, -90).UnixMilli())
	if err != nil {
		return nil, err
	}
	out := []FollowedArtist{}
	byID := map[int64]int{}
	for rows.Next() {
		var a FollowedArtist
		var cover sql.NullInt64
		if err := rows.Scan(&a.ID, &a.Name, &cover, &a.listenedMs); err != nil {
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
	// The latest fresh release of each that the library lacks
	// (NewReleases is most recent first).
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
