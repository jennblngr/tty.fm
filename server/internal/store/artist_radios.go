package store

import (
	"context"
	"database/sql"
	"time"
)

// Artist radios ("◉ radios d'artistes" on the home screen) start from the
// liked artists, then, to fill the row, from the most listened ones of
// the last radioDays days.
const radioDays = 28

// ArtistRadio is an artist whose radio the home screen offers.
type ArtistRadio struct {
	ID      int64  `json:"id"`
	Name    string `json:"name"`
	CoverID *int64 `json:"cover_id,omitempty"`
	Liked   bool   `json:"liked"`
}

// ArtistRadios lists up to limit artists still in the library: the liked
// ones first, then the others listened to lately, each group the most
// listened first.
func (db *DB) ArtistRadios(ctx context.Context, now time.Time, limit int) ([]ArtistRadio, error) {
	rows, err := db.r.QueryContext(ctx, `
		WITH listened AS (
		  SELECT t.artist_id AS id, SUM(p.listened_ms) AS ms
		  FROM plays p JOIN tracks t ON t.id = p.track_id
		  WHERE p.started_at >= ?
		  GROUP BY t.artist_id
		)
		SELECT ar.id, ar.name,
		       (SELECT al.cover_id FROM albums al WHERE al.album_artist_id = ar.id AND al.cover_id IS NOT NULL
		        ORDER BY al.year DESC LIMIT 1),
		       f.artist_id IS NOT NULL AS liked
		FROM artists ar
		LEFT JOIN favorite_artists f ON f.artist_id = ar.id
		LEFT JOIN listened l ON l.id = ar.id
		WHERE (f.artist_id IS NOT NULL OR l.ms > 0)
		  AND EXISTS (SELECT 1 FROM tracks t WHERE t.missing_since IS NULL
		              AND (t.artist_id = ar.id OR t.album_id IN (SELECT id FROM albums WHERE album_artist_id = ar.id)))
		ORDER BY liked DESC, COALESCE(l.ms, 0) DESC, ar.sort_name
		LIMIT ?`,
		now.AddDate(0, 0, -radioDays).UnixMilli(), max(limit, 0))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []ArtistRadio{}
	for rows.Next() {
		var a ArtistRadio
		var cover sql.NullInt64
		if err := rows.Scan(&a.ID, &a.Name, &cover, &a.Liked); err != nil {
			return nil, err
		}
		a.CoverID = ptrID(cover)
		out = append(out, a)
	}
	return out, rows.Err()
}
