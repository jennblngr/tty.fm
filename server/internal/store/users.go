package store

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"time"
)

type User struct {
	ID           int64
	Username     string
	PasswordHash string
}

type Device struct {
	ID         int64  `json:"id"`
	UserID     int64  `json:"-"`
	Name       string `json:"name"`
	Platform   string `json:"platform"`
	CreatedAt  int64  `json:"created_at"`
	LastSeenAt int64  `json:"last_seen_at"`
}

func (db *DB) UserCount(ctx context.Context) (int, error) {
	var n int
	err := db.r.QueryRowContext(ctx, `SELECT COUNT(*) FROM users`).Scan(&n)
	return n, err
}

func (db *DB) CreateUser(ctx context.Context, username, passwordHash string) (int64, error) {
	var id int64
	err := db.w.QueryRowContext(ctx,
		`INSERT INTO users (username, password_hash, created_at) VALUES (?, ?, ?) RETURNING id`,
		username, passwordHash, now()).Scan(&id)
	return id, err
}

func (db *DB) UserByName(ctx context.Context, username string) (User, error) {
	var u User
	err := db.r.QueryRowContext(ctx,
		`SELECT id, username, password_hash FROM users WHERE username = ?`, username).
		Scan(&u.ID, &u.Username, &u.PasswordHash)
	return u, notFound(err)
}

func (db *DB) SetPassword(ctx context.Context, userID int64, passwordHash string) error {
	_, err := db.w.ExecContext(ctx, `UPDATE users SET password_hash = ? WHERE id = ?`, passwordHash, userID)
	return err
}

func (db *DB) CreateDevice(ctx context.Context, userID int64, name, platform, tokenHash string) (Device, error) {
	ts := now()
	d := Device{UserID: userID, Name: name, Platform: platform, CreatedAt: ts, LastSeenAt: ts}
	err := db.w.QueryRowContext(ctx, `
		INSERT INTO devices (user_id, name, platform, token_hash, created_at, last_seen_at)
		VALUES (?, ?, ?, ?, ?, ?) RETURNING id`, userID, name, platform, tokenHash, ts, ts).Scan(&d.ID)
	return d, err
}

// DeviceByToken resolves a token hash. Results are not cached here; the auth
// layer keeps an in-memory cache.
func (db *DB) DeviceByToken(ctx context.Context, tokenHash string) (Device, error) {
	var d Device
	err := db.r.QueryRowContext(ctx, `
		SELECT id, user_id, name, platform, created_at, last_seen_at FROM devices WHERE token_hash = ?`, tokenHash).
		Scan(&d.ID, &d.UserID, &d.Name, &d.Platform, &d.CreatedAt, &d.LastSeenAt)
	return d, notFound(err)
}

func (db *DB) TouchDevice(ctx context.Context, id int64, at time.Time) error {
	_, err := db.w.ExecContext(ctx, `UPDATE devices SET last_seen_at = ? WHERE id = ?`, at.Unix(), id)
	return err
}

func (db *DB) Devices(ctx context.Context, userID int64) ([]Device, error) {
	rows, err := db.r.QueryContext(ctx, `
		SELECT id, user_id, name, platform, created_at, last_seen_at FROM devices
		WHERE user_id = ? ORDER BY last_seen_at DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Device{}
	for rows.Next() {
		var d Device
		if err := rows.Scan(&d.ID, &d.UserID, &d.Name, &d.Platform, &d.CreatedAt, &d.LastSeenAt); err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	return out, rows.Err()
}

func (db *DB) DeleteDevice(ctx context.Context, userID, id int64) error {
	res, err := db.w.ExecContext(ctx, `DELETE FROM devices WHERE id = ? AND user_id = ?`, id, userID)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrNotFound
	}
	return nil
}

// --- Plays -----------------------------------------------------------------

type Play struct {
	TrackID     int64  `json:"track_id"`
	StartedAt   int64  `json:"started_at"` // unix milliseconds
	ListenedMs  int64  `json:"listened_ms"`
	Skipped     bool   `json:"skipped"`
	ContextKind string `json:"context_kind,omitempty"`
	ContextID   int64  `json:"context_id,omitempty"`
}

// AddPlays records a batch of plays. Plays for unknown tracks are ignored
// (the client may send history for tracks deleted meanwhile).
func (db *DB) AddPlays(ctx context.Context, deviceID int64, plays []Play) (int, error) {
	n := 0
	err := db.Tx(ctx, func(tx *sql.Tx) error {
		for _, p := range plays {
			if p.StartedAt <= 0 || p.ListenedMs < 0 {
				return fmt.Errorf("%w: bad play", ErrInvalid)
			}
			res, err := tx.Exec(`
				INSERT INTO plays (track_id, device_id, started_at, listened_ms, skipped, context_kind, context_id)
				SELECT id, ?, ?, ?, ?, ?, ? FROM tracks WHERE id = ?`,
				nullInt(int(deviceID)), p.StartedAt, p.ListenedMs, p.Skipped, nullStr(p.ContextKind), nullInt(int(p.ContextID)), p.TrackID)
			if err != nil {
				return err
			}
			k, _ := res.RowsAffected()
			n += int(k)
		}
		return nil
	})
	return n, err
}

// --- Favorites -------------------------------------------------------------

var favTables = map[string][2]string{
	"tracks":  {"favorite_tracks", "track_id"},
	"albums":  {"favorite_albums", "album_id"},
	"artists": {"favorite_artists", "artist_id"},
}

func favTable(kind string) (string, string, error) {
	t, ok := favTables[kind]
	if !ok {
		return "", "", fmt.Errorf("%w: unknown favorite kind %q", ErrInvalid, kind)
	}
	return t[0], t[1], nil
}

func (db *DB) SetFavorite(ctx context.Context, kind string, id int64, on bool) error {
	table, col, err := favTable(kind)
	if err != nil {
		return err
	}
	if !on {
		_, err = db.w.ExecContext(ctx, fmt.Sprintf(`DELETE FROM %s WHERE %s = ?`, table, col), id)
		return err
	}
	_, err = db.w.ExecContext(ctx, fmt.Sprintf(
		`INSERT INTO %s (%s, created_at) VALUES (?, ?) ON CONFLICT DO NOTHING`, table, col), id, now())
	if isFKError(err) {
		return ErrNotFound
	}
	return err
}

// FavoriteIDs returns the ids of every favourite, by kind. The client keeps
// this small set in memory to draw hearts without extra requests.
func (db *DB) FavoriteIDs(ctx context.Context) (map[string][]int64, error) {
	out := map[string][]int64{}
	for kind, t := range favTables {
		rows, err := db.r.QueryContext(ctx, fmt.Sprintf(`SELECT %s FROM %s ORDER BY created_at DESC`, t[1], t[0]))
		if err != nil {
			return nil, err
		}
		ids := []int64{}
		for rows.Next() {
			var id int64
			if err := rows.Scan(&id); err != nil {
				rows.Close()
				return nil, err
			}
			ids = append(ids, id)
		}
		rows.Close()
		out[kind] = ids
	}
	return out, nil
}

func (db *DB) FavoriteTracks(ctx context.Context) ([]Track, error) {
	return db.trackList(ctx, strings.Replace(trackSelect, "FROM tracks t",
		"FROM favorite_tracks f JOIN tracks t ON t.id = f.track_id", 1)+" ORDER BY f.created_at DESC")
}

func (db *DB) FavoriteAlbums(ctx context.Context) ([]Album, error) {
	return db.albumList(ctx, strings.Replace(albumSelect, "FROM albums al",
		"FROM favorite_albums f JOIN albums al ON al.id = f.album_id", 1)+" ORDER BY f.created_at DESC")
}
