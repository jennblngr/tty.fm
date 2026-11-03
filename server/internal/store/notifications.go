package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"time"
)

// Notification is one entry of the bell's list. Data depends on Kind:
// AddedData for "added".
type Notification struct {
	ID        int64           `json:"id"`
	Kind      string          `json:"kind"`
	CreatedAt int64           `json:"created_at"`
	Read      bool            `json:"read"`
	Data      json.RawMessage `json:"data"`
}

// NotificationKinds lists the kinds the server generates, all on by
// default. The other kinds of the mockups (analysis, mixes, releases,
// stats) come with their features.
var NotificationKinds = []string{"added"}

// AddedData: "+ 3 titres ajoutés — faune, racines".
type AddedData struct {
	Tracks      int      `json:"tracks"`
	Albums      int      `json:"albums"`
	AlbumID     int64    `json:"album_id,omitempty"` // when they all belong to one album
	Artists     []string `json:"artists"`            // most tracks first, at most addedArtists
	ArtistCount int      `json:"artist_count"`
}

const (
	// addedLookback: batches older than this never become notifications,
	// so a library scanned long ago does not fill the bell on upgrade.
	addedLookback = 7 * 24 * time.Hour
	addedArtists  = 5
	// notificationsKept: older notifications are deleted.
	notificationsKept = 90 * 24 * time.Hour
)

// enabledKinds filters a notifications query on the kinds left on.
const enabledKinds = ` AND kind NOT IN (SELECT kind FROM notification_settings WHERE user_id = n.user_id AND enabled = 0)`

func (db *DB) NotificationSettings(ctx context.Context, userID int64) (map[string]bool, error) {
	out := map[string]bool{}
	for _, k := range NotificationKinds {
		out[k] = true
	}
	rows, err := db.r.QueryContext(ctx, `SELECT kind, enabled FROM notification_settings WHERE user_id = ?`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var k string
		var on bool
		if err := rows.Scan(&k, &on); err != nil {
			return nil, err
		}
		if _, ok := out[k]; ok {
			out[k] = on
		}
	}
	return out, rows.Err()
}

// SetNotificationSettings turns kinds on or off; the others keep their
// setting.
func (db *DB) SetNotificationSettings(ctx context.Context, userID int64, set map[string]bool) error {
	for k := range set {
		if !slices.Contains(NotificationKinds, k) {
			return fmt.Errorf("%w: unknown notification kind %q", ErrInvalid, k)
		}
	}
	return db.Tx(ctx, func(tx *sql.Tx) error {
		for k, on := range set {
			if _, err := tx.ExecContext(ctx, `
				INSERT INTO notification_settings (user_id, kind, enabled) VALUES (?, ?, ?)
				ON CONFLICT (user_id, kind) DO UPDATE SET enabled = excluded.enabled`, userID, k, on); err != nil {
				return err
			}
		}
		return nil
	})
}

// Notifications returns the notifications of the kinds left on, newest
// first.
func (db *DB) Notifications(ctx context.Context, userID int64, limit int) ([]Notification, error) {
	rows, err := db.r.QueryContext(ctx, `
		SELECT id, kind, created_at, read_at IS NOT NULL, data FROM notifications n
		WHERE user_id = ?`+enabledKinds+` ORDER BY created_at DESC, id DESC LIMIT ?`, userID, clampLimit(limit))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Notification{}
	for rows.Next() {
		var n Notification
		var data string
		if err := rows.Scan(&n.ID, &n.Kind, &n.CreatedAt, &n.Read, &data); err != nil {
			return nil, err
		}
		n.Data = json.RawMessage(data)
		out = append(out, n)
	}
	return out, rows.Err()
}

func (db *DB) UnreadNotifications(ctx context.Context, userID int64) (int, error) {
	var n int
	err := db.r.QueryRowContext(ctx, `
		SELECT COUNT(*) FROM notifications n WHERE user_id = ? AND read_at IS NULL`+enabledKinds, userID).Scan(&n)
	return n, err
}

func (db *DB) MarkNotificationRead(ctx context.Context, userID, id int64, read bool) error {
	res, err := db.w.ExecContext(ctx, `
		UPDATE notifications SET read_at = CASE WHEN ? THEN COALESCE(read_at, ?) END
		WHERE id = ? AND user_id = ?`, read, now(), id, userID)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrNotFound
	}
	return nil
}

func (db *DB) MarkAllNotificationsRead(ctx context.Context, userID int64) error {
	_, err := db.w.ExecContext(ctx, `
		UPDATE notifications SET read_at = ? WHERE user_id = ? AND read_at IS NULL`, now(), userID)
	return err
}

// SyncNotifications generates the user's notifications from the library
// up to now, and deletes the old ones. Running it again changes nothing
// until the library does.
func (db *DB) SyncNotifications(ctx context.Context, userID int64, now time.Time) error {
	settings, err := db.NotificationSettings(ctx, userID)
	if err != nil {
		return err
	}
	if settings["added"] {
		if err := db.syncAdded(ctx, userID, now); err != nil {
			return err
		}
	}
	_, err = db.w.ExecContext(ctx, `DELETE FROM notifications WHERE user_id = ? AND created_at < ?`,
		userID, now.Add(-notificationsKept).Unix())
	return err
}

// addedGroup is a run of recent additions (batches of the home's "ajouts
// récents") less than additionWindow apart: one scan or one copy, maybe
// spanning several albums.
type addedGroup struct {
	since, at int64
	batches   []RecentAddition
}

func groupAdditions(adds []RecentAddition) []addedGroup {
	var out []addedGroup // newest first, as adds
	for _, a := range adds {
		if n := len(out); n > 0 && out[n-1].since-a.AddedAt <= additionWindow {
			out[n-1].since = a.AddedAt
			out[n-1].batches = append(out[n-1].batches, a)
			continue
		}
		out = append(out, addedGroup{since: a.AddedAt, at: a.AddedAt, batches: []RecentAddition{a}})
	}
	return out
}

func (g addedGroup) data() AddedData {
	d := AddedData{Albums: len(g.batches), Artists: []string{}}
	tracks := map[string]int{}
	var order []string
	for _, b := range g.batches {
		d.Tracks += b.Tracks
		if _, ok := tracks[b.Album.Artist]; !ok {
			order = append(order, b.Album.Artist)
		}
		tracks[b.Album.Artist] += b.Tracks
	}
	if len(g.batches) == 1 {
		d.AlbumID = g.batches[0].Album.ID
	}
	slices.SortStableFunc(order, func(a, b string) int { return tracks[b] - tracks[a] })
	d.ArtistCount = len(order)
	d.Artists = append(d.Artists, order[:min(len(order), addedArtists)]...)
	return d
}

// syncAdded turns the groups of recent additions newer than the last
// "added" notification into notifications. A group that follows the last
// one closely (a copy still in progress) updates it, and marks it unread
// again if it brought more tracks.
func (db *DB) syncAdded(ctx context.Context, userID int64, now time.Time) error {
	adds, err := db.RecentAdditions(ctx, 500)
	if err != nil {
		return err
	}
	from := now.Add(-addedLookback).Unix()
	adds = slices.DeleteFunc(adds, func(a RecentAddition) bool { return a.AddedAt < from })
	groups := groupAdditions(adds)
	if len(groups) == 0 {
		return nil
	}
	return db.Tx(ctx, func(tx *sql.Tx) error {
		var lastID, lastAt int64
		err := tx.QueryRowContext(ctx, `
			SELECT id, created_at FROM notifications WHERE user_id = ? AND kind = 'added'
			ORDER BY created_at DESC LIMIT 1`, userID).Scan(&lastID, &lastAt)
		if err != nil && !errors.Is(err, sql.ErrNoRows) {
			return err
		}
		for i := len(groups) - 1; i >= 0; i-- {
			g := groups[i]
			if lastID != 0 && g.at < lastAt {
				continue
			}
			b, err := json.Marshal(g.data())
			if err != nil {
				return err
			}
			data := string(b) // TEXT, for json_extract
			if lastID != 0 && g.since-lastAt <= additionWindow {
				_, err = tx.ExecContext(ctx, `
					UPDATE notifications SET since = MIN(since, ?1), created_at = ?2, data = ?3,
					  read_at = CASE WHEN json_extract(?3, '$.tracks') > json_extract(data, '$.tracks') THEN NULL ELSE read_at END
					WHERE id = ?4 AND data != ?3`, g.since, g.at, data, lastID)
			} else {
				err = tx.QueryRowContext(ctx, `
					INSERT INTO notifications (user_id, kind, since, created_at, data) VALUES (?, 'added', ?, ?, ?)
					RETURNING id`, userID, g.since, g.at, data).Scan(&lastID)
			}
			if err != nil {
				return err
			}
			lastAt = g.at
		}
		return nil
	})
}
