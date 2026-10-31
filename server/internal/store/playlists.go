package store

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
)

type Folder struct {
	ID        int64      `json:"id"`
	Name      string     `json:"name"`
	ParentID  *int64     `json:"parent_id"`
	Position  int        `json:"position"`
	Folders   []Folder   `json:"folders"`
	Playlists []Playlist `json:"playlists"`
}

type Playlist struct {
	ID         int64   `json:"id"`
	Name       string  `json:"name"`
	FolderID   *int64  `json:"folder_id"`
	Position   int     `json:"position"`
	TrackCount int     `json:"track_count"`
	DurationMs int64   `json:"duration_ms"`
	CoverIDs   []int64 `json:"cover_ids"` // up to 4 distinct album covers
	CreatedAt  int64   `json:"created_at"`
	UpdatedAt  int64   `json:"updated_at"`
}

// Tree is the root of the playlist hierarchy.
type Tree struct {
	Folders   []Folder   `json:"folders"`
	Playlists []Playlist `json:"playlists"`
}

type PlaylistEntry struct {
	EntryID  int64 `json:"entry_id"`
	Position int   `json:"position"`
	AddedAt  int64 `json:"added_at"`
	Track    Track `json:"track"`
}

const playlistSelect = `
	SELECT p.id, p.name, p.folder_id, p.position, p.created_at, p.updated_at,
	  (SELECT COUNT(*) FROM playlist_tracks pt JOIN tracks t ON t.id = pt.track_id
	   WHERE pt.playlist_id = p.id AND t.missing_since IS NULL),
	  (SELECT COALESCE(SUM(t.duration_ms), 0) FROM playlist_tracks pt JOIN tracks t ON t.id = pt.track_id
	   WHERE pt.playlist_id = p.id AND t.missing_since IS NULL),
	  (SELECT group_concat(cover_id) FROM (
	     SELECT DISTINCT al.cover_id FROM playlist_tracks pt
	     JOIN tracks t ON t.id = pt.track_id JOIN albums al ON al.id = t.album_id
	     WHERE pt.playlist_id = p.id AND al.cover_id IS NOT NULL AND t.missing_since IS NULL
	     ORDER BY pt.position LIMIT 4))
	FROM playlists p`

func scanPlaylist(row interface{ Scan(...any) error }) (Playlist, error) {
	var p Playlist
	var folder sql.NullInt64
	var covers sql.NullString
	err := row.Scan(&p.ID, &p.Name, &folder, &p.Position, &p.CreatedAt, &p.UpdatedAt,
		&p.TrackCount, &p.DurationMs, &covers)
	p.FolderID = ptrID(folder)
	p.CoverIDs = []int64{}
	if covers.Valid {
		for _, s := range strings.Split(covers.String, ",") {
			var id int64
			fmt.Sscan(s, &id)
			p.CoverIDs = append(p.CoverIDs, id)
		}
	}
	return p, err
}

// PlaylistTree returns the full folder/playlist hierarchy, ordered.
func (db *DB) PlaylistTree(ctx context.Context) (Tree, error) {
	var folders []Folder
	rows, err := db.r.QueryContext(ctx,
		`SELECT id, name, parent_id, position FROM playlist_folders ORDER BY position, id`)
	if err != nil {
		return Tree{}, err
	}
	for rows.Next() {
		var f Folder
		var parent sql.NullInt64
		if err := rows.Scan(&f.ID, &f.Name, &parent, &f.Position); err != nil {
			rows.Close()
			return Tree{}, err
		}
		f.ParentID = ptrID(parent)
		folders = append(folders, f)
	}
	rows.Close()

	var playlists []Playlist
	rows, err = db.r.QueryContext(ctx, playlistSelect+` ORDER BY p.position, p.id`)
	if err != nil {
		return Tree{}, err
	}
	for rows.Next() {
		p, err := scanPlaylist(rows)
		if err != nil {
			rows.Close()
			return Tree{}, err
		}
		playlists = append(playlists, p)
	}
	rows.Close()

	// Assemble bottom-up: children lists keyed by parent id (0 = root).
	childFolders := map[int64][]Folder{}
	childPlaylists := map[int64][]Playlist{}
	for _, p := range playlists {
		var k int64
		if p.FolderID != nil {
			k = *p.FolderID
		}
		childPlaylists[k] = append(childPlaylists[k], p)
	}
	for _, f := range folders {
		var k int64
		if f.ParentID != nil {
			k = *f.ParentID
		}
		childFolders[k] = append(childFolders[k], f)
	}
	var build func(parent int64) []Folder
	build = func(parent int64) []Folder {
		out := []Folder{}
		for _, f := range childFolders[parent] {
			f.Folders = build(f.ID)
			f.Playlists = childPlaylists[f.ID]
			if f.Playlists == nil {
				f.Playlists = []Playlist{}
			}
			out = append(out, f)
		}
		return out
	}
	t := Tree{Folders: build(0), Playlists: childPlaylists[0]}
	if t.Playlists == nil {
		t.Playlists = []Playlist{}
	}
	return t, nil
}

// placeSibling moves row id of table to index among its siblings (rows
// sharing parentCol = parent) and renumbers positions 0..n-1.
func placeSibling(tx *sql.Tx, table, parentCol string, parent *int64, id int64, index int) error {
	rows, err := tx.Query(fmt.Sprintf(
		`SELECT id FROM %s WHERE %s IS ? AND id != ? ORDER BY position, id`, table, parentCol),
		nullID(parent), id)
	if err != nil {
		return err
	}
	var ids []int64
	for rows.Next() {
		var x int64
		if err := rows.Scan(&x); err != nil {
			rows.Close()
			return err
		}
		ids = append(ids, x)
	}
	rows.Close()
	if id != 0 {
		if index < 0 || index > len(ids) {
			index = len(ids)
		}
		ids = append(ids[:index], append([]int64{id}, ids[index:]...)...)
	}
	ts := now()
	for i, x := range ids {
		if _, err := tx.Exec(fmt.Sprintf(
			`UPDATE %s SET position = ?, updated_at = CASE WHEN id = ? THEN ? ELSE updated_at END WHERE id = ?`, table),
			i, id, ts, x); err != nil {
			return err
		}
	}
	return nil
}

func folderExists(tx *sql.Tx, id *int64) error {
	if id == nil {
		return nil
	}
	var x int64
	if err := tx.QueryRow(`SELECT id FROM playlist_folders WHERE id = ?`, *id).Scan(&x); err != nil {
		if err == sql.ErrNoRows {
			return fmt.Errorf("%w: folder %d does not exist", ErrInvalid, *id)
		}
		return err
	}
	return nil
}

// --- Folders ---------------------------------------------------------------

func (db *DB) CreateFolder(ctx context.Context, name string, parentID *int64) (int64, error) {
	if strings.TrimSpace(name) == "" {
		return 0, fmt.Errorf("%w: name is required", ErrInvalid)
	}
	var id int64
	err := db.Tx(ctx, func(tx *sql.Tx) error {
		if err := folderExists(tx, parentID); err != nil {
			return err
		}
		ts := now()
		if err := tx.QueryRow(`
			INSERT INTO playlist_folders (name, parent_id, position, created_at, updated_at)
			VALUES (?, ?, (SELECT COALESCE(MAX(position) + 1, 0) FROM playlist_folders WHERE parent_id IS ?), ?, ?)
			RETURNING id`, name, nullID(parentID), nullID(parentID), ts, ts).Scan(&id); err != nil {
			return err
		}
		return nil
	})
	return id, err
}

// FolderUpdate describes a partial update. MoveTo set means "change parent"
// (nil inner pointer = root); Position set means "place at this index".
type FolderUpdate struct {
	Name     *string
	MoveTo   **int64
	Position *int
}

func (db *DB) UpdateFolder(ctx context.Context, id int64, u FolderUpdate) error {
	return db.Tx(ctx, func(tx *sql.Tx) error {
		var parent sql.NullInt64
		if err := tx.QueryRow(`SELECT parent_id FROM playlist_folders WHERE id = ?`, id).Scan(&parent); err != nil {
			return notFound(err)
		}
		if u.Name != nil {
			if strings.TrimSpace(*u.Name) == "" {
				return fmt.Errorf("%w: name is required", ErrInvalid)
			}
			if _, err := tx.Exec(`UPDATE playlist_folders SET name = ?, updated_at = ? WHERE id = ?`, *u.Name, now(), id); err != nil {
				return err
			}
		}
		if u.MoveTo == nil && u.Position == nil {
			return nil
		}
		oldParent := ptrID(parent)
		newParent := oldParent
		if u.MoveTo != nil {
			newParent = *u.MoveTo
			if err := folderExists(tx, newParent); err != nil {
				return err
			}
			if newParent != nil {
				// Refuse to move a folder into itself or one of its descendants.
				var cyc int
				if err := tx.QueryRow(`
					WITH RECURSIVE sub(id) AS (
					  SELECT ? UNION ALL
					  SELECT f.id FROM playlist_folders f JOIN sub ON f.parent_id = sub.id)
					SELECT COUNT(*) FROM sub WHERE id = ?`, id, *newParent).Scan(&cyc); err != nil {
					return err
				}
				if cyc > 0 {
					return fmt.Errorf("%w: cannot move a folder into itself or its descendants", ErrInvalid)
				}
			}
			if _, err := tx.Exec(`UPDATE playlist_folders SET parent_id = ? WHERE id = ?`, nullID(newParent), id); err != nil {
				return err
			}
		}
		index := -1
		if u.Position != nil {
			index = *u.Position
		}
		if err := placeSibling(tx, "playlist_folders", "parent_id", newParent, id, index); err != nil {
			return err
		}
		if !sameID(oldParent, newParent) {
			return placeSibling(tx, "playlist_folders", "parent_id", oldParent, 0, 0)
		}
		return nil
	})
}

// DeleteFolder removes a folder with all its sub-folders and playlists.
func (db *DB) DeleteFolder(ctx context.Context, id int64) error {
	return db.Tx(ctx, func(tx *sql.Tx) error {
		var parent sql.NullInt64
		if err := tx.QueryRow(`DELETE FROM playlist_folders WHERE id = ? RETURNING parent_id`, id).Scan(&parent); err != nil {
			return notFound(err)
		}
		return placeSibling(tx, "playlist_folders", "parent_id", ptrID(parent), 0, 0)
	})
}

// --- Playlists -------------------------------------------------------------

func (db *DB) CreatePlaylist(ctx context.Context, name string, folderID *int64) (int64, error) {
	if strings.TrimSpace(name) == "" {
		return 0, fmt.Errorf("%w: name is required", ErrInvalid)
	}
	var id int64
	err := db.Tx(ctx, func(tx *sql.Tx) error {
		if err := folderExists(tx, folderID); err != nil {
			return err
		}
		ts := now()
		return tx.QueryRow(`
			INSERT INTO playlists (name, folder_id, position, created_at, updated_at)
			VALUES (?, ?, (SELECT COALESCE(MAX(position) + 1, 0) FROM playlists WHERE folder_id IS ?), ?, ?)
			RETURNING id`, name, nullID(folderID), nullID(folderID), ts, ts).Scan(&id)
	})
	return id, err
}

func (db *DB) Playlist(ctx context.Context, id int64) (Playlist, error) {
	p, err := scanPlaylist(db.r.QueryRowContext(ctx, playlistSelect+` WHERE p.id = ?`, id))
	return p, notFound(err)
}

func (db *DB) UpdatePlaylist(ctx context.Context, id int64, u FolderUpdate) error {
	return db.Tx(ctx, func(tx *sql.Tx) error {
		var folder sql.NullInt64
		if err := tx.QueryRow(`SELECT folder_id FROM playlists WHERE id = ?`, id).Scan(&folder); err != nil {
			return notFound(err)
		}
		if u.Name != nil {
			if strings.TrimSpace(*u.Name) == "" {
				return fmt.Errorf("%w: name is required", ErrInvalid)
			}
			if _, err := tx.Exec(`UPDATE playlists SET name = ?, updated_at = ? WHERE id = ?`, *u.Name, now(), id); err != nil {
				return err
			}
		}
		if u.MoveTo == nil && u.Position == nil {
			return nil
		}
		oldFolder := ptrID(folder)
		newFolder := oldFolder
		if u.MoveTo != nil {
			newFolder = *u.MoveTo
			if err := folderExists(tx, newFolder); err != nil {
				return err
			}
			if _, err := tx.Exec(`UPDATE playlists SET folder_id = ? WHERE id = ?`, nullID(newFolder), id); err != nil {
				return err
			}
		}
		index := -1
		if u.Position != nil {
			index = *u.Position
		}
		if err := placeSibling(tx, "playlists", "folder_id", newFolder, id, index); err != nil {
			return err
		}
		if !sameID(oldFolder, newFolder) {
			return placeSibling(tx, "playlists", "folder_id", oldFolder, 0, 0)
		}
		return nil
	})
}

func (db *DB) DeletePlaylist(ctx context.Context, id int64) error {
	return db.Tx(ctx, func(tx *sql.Tx) error {
		var folder sql.NullInt64
		if err := tx.QueryRow(`DELETE FROM playlists WHERE id = ? RETURNING folder_id`, id).Scan(&folder); err != nil {
			return notFound(err)
		}
		return placeSibling(tx, "playlists", "folder_id", ptrID(folder), 0, 0)
	})
}

// --- Playlist tracks -------------------------------------------------------

// PlaylistTracks returns the entries in order. Missing tracks are skipped.
func (db *DB) PlaylistTracks(ctx context.Context, playlistID int64) ([]PlaylistEntry, error) {
	if _, err := db.Playlist(ctx, playlistID); err != nil {
		return nil, err
	}
	q := strings.Replace(trackSelect, "/*extra*/", ", pt.id, pt.position, pt.added_at", 1)
	q = strings.Replace(q, "FROM tracks t", "FROM playlist_tracks pt JOIN tracks t ON t.id = pt.track_id", 1)
	rows, err := db.r.QueryContext(ctx, q+` AND pt.playlist_id = ? ORDER BY pt.position`, playlistID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []PlaylistEntry{}
	for rows.Next() {
		var e PlaylistEntry
		t, err := scanTrack(rows, &e.EntryID, &e.Position, &e.AddedAt)
		if err != nil {
			return nil, err
		}
		e.Track = t
		out = append(out, e)
	}
	return out, rows.Err()
}

func entryIDs(tx *sql.Tx, playlistID int64) ([]int64, error) {
	rows, err := tx.Query(`SELECT id FROM playlist_tracks WHERE playlist_id = ? ORDER BY position, id`, playlistID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var ids []int64
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

func renumberEntries(tx *sql.Tx, playlistID int64, ids []int64) error {
	for i, id := range ids {
		if _, err := tx.Exec(`UPDATE playlist_tracks SET position = ? WHERE id = ?`, i, id); err != nil {
			return err
		}
	}
	_, err := tx.Exec(`UPDATE playlists SET updated_at = ? WHERE id = ?`, now(), playlistID)
	return err
}

func playlistExists(tx *sql.Tx, id int64) error {
	var x int64
	return notFound(tx.QueryRow(`SELECT id FROM playlists WHERE id = ?`, id).Scan(&x))
}

// AddTracks inserts tracks at index (nil or out of range = append).
func (db *DB) AddTracks(ctx context.Context, playlistID int64, trackIDs []int64, at *int) error {
	if len(trackIDs) == 0 {
		return nil
	}
	return db.Tx(ctx, func(tx *sql.Tx) error {
		if err := playlistExists(tx, playlistID); err != nil {
			return err
		}
		ids, err := entryIDs(tx, playlistID)
		if err != nil {
			return err
		}
		index := len(ids)
		if at != nil && *at >= 0 && *at < len(ids) {
			index = *at
		}
		ts := now()
		var added []int64
		for _, tid := range trackIDs {
			var id int64
			err := tx.QueryRow(`
				INSERT INTO playlist_tracks (playlist_id, track_id, position, added_at)
				SELECT ?, id, 0, ? FROM tracks WHERE id = ? RETURNING id`, playlistID, ts, tid).Scan(&id)
			if err == sql.ErrNoRows {
				return fmt.Errorf("%w: track %d does not exist", ErrInvalid, tid)
			}
			if err != nil {
				return err
			}
			added = append(added, id)
		}
		ids = append(ids[:index], append(added, ids[index:]...)...)
		return renumberEntries(tx, playlistID, ids)
	})
}

// MoveEntry moves one entry to index.
func (db *DB) MoveEntry(ctx context.Context, playlistID, entryID int64, index int) error {
	return db.Tx(ctx, func(tx *sql.Tx) error {
		ids, err := entryIDs(tx, playlistID)
		if err != nil {
			return err
		}
		from := -1
		for i, id := range ids {
			if id == entryID {
				from = i
				break
			}
		}
		if from < 0 {
			return ErrNotFound
		}
		ids = append(ids[:from], ids[from+1:]...)
		if index < 0 || index > len(ids) {
			index = len(ids)
		}
		ids = append(ids[:index], append([]int64{entryID}, ids[index:]...)...)
		return renumberEntries(tx, playlistID, ids)
	})
}

func (db *DB) RemoveEntry(ctx context.Context, playlistID, entryID int64) error {
	return db.Tx(ctx, func(tx *sql.Tx) error {
		res, err := tx.Exec(`DELETE FROM playlist_tracks WHERE id = ? AND playlist_id = ?`, entryID, playlistID)
		if err != nil {
			return err
		}
		if n, _ := res.RowsAffected(); n == 0 {
			return ErrNotFound
		}
		ids, err := entryIDs(tx, playlistID)
		if err != nil {
			return err
		}
		return renumberEntries(tx, playlistID, ids)
	})
}

func sameID(a, b *int64) bool {
	if a == nil || b == nil {
		return a == nil && b == nil
	}
	return *a == *b
}
