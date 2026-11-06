package store

import "context"

// SetHidden hides a track (on) or shows it again. Hidden tracks stay in the
// library; the client greys them out and never queues them.
func (db *DB) SetHidden(ctx context.Context, trackID int64, on bool) error {
	if !on {
		_, err := db.w.ExecContext(ctx, `DELETE FROM hidden_tracks WHERE track_id = ?`, trackID)
		return err
	}
	_, err := db.w.ExecContext(ctx,
		`INSERT INTO hidden_tracks (track_id, created_at) VALUES (?, ?) ON CONFLICT DO NOTHING`, trackID, now())
	if isFKError(err) {
		return ErrNotFound
	}
	return err
}

// HiddenTrackIDs returns the ids of every hidden track, most recent first.
// Like the favourites, the client keeps this small set in memory.
func (db *DB) HiddenTrackIDs(ctx context.Context) ([]int64, error) {
	rows, err := db.r.QueryContext(ctx, `SELECT track_id FROM hidden_tracks ORDER BY created_at DESC, track_id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	ids := []int64{}
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}
