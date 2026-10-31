package store

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"time"
)

// TrackFile is what the scanner extracts from one audio file.
type TrackFile struct {
	Path            string // relative to the music root, '/' separated
	Size            int64
	Mtime           int64 // unix nanoseconds
	Title           string
	Artist          string
	ArtistSort      string
	AlbumArtist     string
	AlbumArtistSort string
	Album           string
	TrackNo         int
	DiscNo          int
	Year            int
	Genre           string
	DurationMs      int64
	Format          string
	Codec           string
	Bitrate         int
	SampleRate      int
	BitDepth        int
	Channels        int
	RGTrackGain     *float64
	RGTrackPeak     *float64
	RGAlbumGain     *float64
	RGAlbumPeak     *float64
	MBID            string
	ArtistMBID      string
	AlbumMBID       string
	AlbumArtistMBID string
}

// KnownFile is the scan-relevant state of a track already in the database.
type KnownFile struct {
	ID         int64
	Size       int64
	Mtime      int64
	DurationMs int64
	Title      string
	Missing    bool
}

// KnownFiles returns every track indexed by path, including missing ones.
func (db *DB) KnownFiles(ctx context.Context) (map[string]KnownFile, error) {
	rows, err := db.r.QueryContext(ctx,
		`SELECT id, path, file_size, file_mtime, duration_ms, title, missing_since IS NOT NULL FROM tracks`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make(map[string]KnownFile)
	for rows.Next() {
		var k KnownFile
		var path string
		if err := rows.Scan(&k.ID, &path, &k.Size, &k.Mtime, &k.DurationMs, &k.Title, &k.Missing); err != nil {
			return nil, err
		}
		out[path] = k
	}
	return out, rows.Err()
}

// LibWriter applies scan results inside one transaction, caching artist and
// album ids. It also records which albums were touched.
type LibWriter struct {
	tx      *sql.Tx
	ts      int64
	artists map[string]int64
	albums  map[string]int64
	Touched map[int64]bool // album ids whose tracks changed
}

// WriteLibrary runs fn with a LibWriter in a single write transaction.
func (db *DB) WriteLibrary(ctx context.Context, fn func(w *LibWriter) error) error {
	return db.Tx(ctx, func(tx *sql.Tx) error {
		w := &LibWriter{
			tx:      tx,
			ts:      now(),
			artists: map[string]int64{},
			albums:  map[string]int64{},
			Touched: map[int64]bool{},
		}
		return fn(w)
	})
}

func (w *LibWriter) artistID(name, sortTag, mbid string) (int64, error) {
	if strings.TrimSpace(name) == "" {
		name = "Unknown artist"
	}
	key := MatchKey(name)
	if id, ok := w.artists[key]; ok {
		return id, nil
	}
	var id int64
	err := w.tx.QueryRow(`
		INSERT INTO artists (name, sort_name, match_key, mbid, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?)
		ON CONFLICT (match_key) DO UPDATE SET
		  mbid = COALESCE(artists.mbid, excluded.mbid)
		RETURNING id`,
		name, SortName(name, sortTag), key, nullStr(mbid), w.ts, w.ts).Scan(&id)
	if err != nil {
		return 0, fmt.Errorf("artist %q: %w", name, err)
	}
	w.artists[key] = id
	return id, nil
}

func (w *LibWriter) albumID(f *TrackFile, albumArtistID int64) (int64, error) {
	title := strings.TrimSpace(f.Album)
	if title == "" {
		title = "Unknown album"
	}
	key := fmt.Sprintf("%d\x00%s", albumArtistID, MatchKey(title))
	if id, ok := w.albums[key]; ok {
		// Tracks are read in parallel, so the first one seen may lack the
		// year or genre a sibling has: fill the gaps.
		if f.Year != 0 || f.Genre != "" || f.AlbumMBID != "" {
			if _, err := w.tx.Exec(`
				UPDATE albums SET
				  year  = COALESCE(year, ?),
				  genre = COALESCE(genre, ?),
				  mbid  = COALESCE(mbid, ?)
				WHERE id = ?`,
				nullInt(f.Year), nullStr(f.Genre), nullStr(f.AlbumMBID), id); err != nil {
				return 0, fmt.Errorf("album %q: %w", title, err)
			}
		}
		return id, nil
	}
	var id int64
	err := w.tx.QueryRow(`
		INSERT INTO albums (title, sort_title, match_key, album_artist_id, year, genre, mbid, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT (album_artist_id, match_key) DO UPDATE SET
		  year  = COALESCE(excluded.year, albums.year),
		  genre = COALESCE(excluded.genre, albums.genre),
		  mbid  = COALESCE(excluded.mbid, albums.mbid),
		  updated_at = excluded.updated_at
		RETURNING id`,
		title, SortName(title, ""), MatchKey(title), albumArtistID,
		nullInt(f.Year), nullStr(f.Genre), nullStr(f.AlbumMBID), w.ts, w.ts).Scan(&id)
	if err != nil {
		return 0, fmt.Errorf("album %q: %w", title, err)
	}
	w.albums[key] = id
	return id, nil
}

// UpsertTrack inserts or updates the track. If reuseID is non-zero, the
// existing row with that id is updated in place (moved/renamed file), keeping
// playlists, favourites and history attached.
func (w *LibWriter) UpsertTrack(f *TrackFile, reuseID int64) (int64, error) {
	artistID, err := w.artistID(f.Artist, f.ArtistSort, f.ArtistMBID)
	if err != nil {
		return 0, err
	}
	albumArtistID := artistID
	if strings.TrimSpace(f.AlbumArtist) != "" {
		if albumArtistID, err = w.artistID(f.AlbumArtist, f.AlbumArtistSort, f.AlbumArtistMBID); err != nil {
			return 0, err
		}
	}
	albumID, err := w.albumID(f, albumArtistID)
	if err != nil {
		return 0, err
	}
	title := strings.TrimSpace(f.Title)
	if title == "" {
		title = baseName(f.Path)
	}

	args := []any{
		f.Path, f.Size, f.Mtime, albumID, artistID, title,
		nullInt(f.TrackNo), nullInt(f.DiscNo), nullInt(f.Year), nullStr(f.Genre),
		f.DurationMs, f.Format, nullStr(f.Codec), nullInt(f.Bitrate), nullInt(f.SampleRate),
		nullInt(f.BitDepth), nullInt(f.Channels),
		f.RGTrackGain, f.RGTrackPeak, f.RGAlbumGain, f.RGAlbumPeak, nullStr(f.MBID),
	}
	var id int64
	if reuseID != 0 {
		// Remember the previous album so it gets its aggregates refreshed.
		var oldAlbum int64
		if err := w.tx.QueryRow(`SELECT album_id FROM tracks WHERE id = ?`, reuseID).Scan(&oldAlbum); err == nil {
			w.Touched[oldAlbum] = true
		}
		_, err = w.tx.Exec(`
			UPDATE tracks SET
			  path=?, file_size=?, file_mtime=?, album_id=?, artist_id=?, title=?,
			  track_no=?, disc_no=?, year=?, genre=?, duration_ms=?, format=?, codec=?,
			  bitrate=?, sample_rate=?, bit_depth=?, channels=?,
			  rg_track_gain=?, rg_track_peak=?, rg_album_gain=?, rg_album_peak=?, mbid=?,
			  missing_since=NULL, updated_at=?
			WHERE id=?`, append(args, w.ts, reuseID)...)
		id = reuseID
	} else {
		err = w.tx.QueryRow(`
			INSERT INTO tracks (
			  path, file_size, file_mtime, album_id, artist_id, title,
			  track_no, disc_no, year, genre, duration_ms, format, codec,
			  bitrate, sample_rate, bit_depth, channels,
			  rg_track_gain, rg_track_peak, rg_album_gain, rg_album_peak, mbid,
			  created_at, updated_at)
			VALUES (?,?,?,?,?,?, ?,?,?,?,?,?,?, ?,?,?,?, ?,?,?,?,?, ?,?)
			RETURNING id`, append(args, w.ts, w.ts)...).Scan(&id)
	}
	if err != nil {
		return 0, fmt.Errorf("track %q: %w", f.Path, err)
	}
	w.Touched[albumID] = true
	return id, nil
}

// MarkMissing soft-deletes tracks whose file disappeared.
func (w *LibWriter) MarkMissing(ids []int64) error {
	for _, id := range ids {
		var albumID int64
		err := w.tx.QueryRow(`
			UPDATE tracks SET missing_since = ?, updated_at = ?
			WHERE id = ? AND missing_since IS NULL RETURNING album_id`, w.ts, w.ts, id).Scan(&albumID)
		if err == sql.ErrNoRows {
			continue
		}
		if err != nil {
			return err
		}
		w.Touched[albumID] = true
	}
	return nil
}

// AlbumDirs returns, for each touched album, the directories of its present
// tracks and the path of its first track (for embedded cover lookup).
func (w *LibWriter) AlbumDirs(albumID int64) (dirs []string, firstTrack string, err error) {
	rows, err := w.tx.Query(`
		SELECT path FROM tracks WHERE album_id = ? AND missing_since IS NULL
		ORDER BY disc_no, track_no, path`, albumID)
	if err != nil {
		return nil, "", err
	}
	defer rows.Close()
	seen := map[string]bool{}
	for rows.Next() {
		var p string
		if err := rows.Scan(&p); err != nil {
			return nil, "", err
		}
		if firstTrack == "" {
			firstTrack = p
		}
		if d := dirName(p); !seen[d] {
			seen[d] = true
			dirs = append(dirs, d)
		}
	}
	return dirs, firstTrack, rows.Err()
}

// AlbumCover returns the current cover id of an album (0 if none).
func (w *LibWriter) AlbumCover(albumID int64) (int64, error) {
	var c sql.NullInt64
	err := w.tx.QueryRow(`SELECT cover_id FROM albums WHERE id = ?`, albumID).Scan(&c)
	return c.Int64, err
}

// CoverID returns the id of the cover with this hash, creating the row.
func (w *LibWriter) CoverID(hash, source string) (int64, error) {
	var id int64
	err := w.tx.QueryRow(`
		INSERT INTO covers (hash, source) VALUES (?, ?)
		ON CONFLICT (hash) DO UPDATE SET source = covers.source
		RETURNING id`, hash, source).Scan(&id)
	return id, err
}

func (w *LibWriter) SetAlbumCover(albumID, coverID int64) error {
	_, err := w.tx.Exec(`UPDATE albums SET cover_id = ?, updated_at = ? WHERE id = ?`,
		nullID(&coverID), w.ts, albumID)
	return err
}

// Finalize refreshes album aggregates, removes empty albums/artists that
// nothing references, and rebuilds the search index.
func (w *LibWriter) Finalize() error {
	for id := range w.Touched {
		if _, err := w.tx.Exec(`
			UPDATE albums SET
			  track_count = (SELECT COUNT(*) FROM tracks WHERE album_id = ?1 AND missing_since IS NULL),
			  duration_ms = (SELECT COALESCE(SUM(duration_ms), 0) FROM tracks WHERE album_id = ?1 AND missing_since IS NULL),
			  updated_at = ?2
			WHERE id = ?1`, id, w.ts); err != nil {
			return err
		}
	}
	return w.cleanupAndReindex()
}

func (w *LibWriter) cleanupAndReindex() error {
	stmts := []string{
		`DELETE FROM albums WHERE NOT EXISTS (SELECT 1 FROM tracks WHERE tracks.album_id = albums.id)`,
		`DELETE FROM artists WHERE
		   NOT EXISTS (SELECT 1 FROM tracks WHERE tracks.artist_id = artists.id) AND
		   NOT EXISTS (SELECT 1 FROM albums WHERE albums.album_artist_id = artists.id)`,
		`DELETE FROM covers WHERE
		   NOT EXISTS (SELECT 1 FROM albums WHERE albums.cover_id = covers.id) AND
		   NOT EXISTS (SELECT 1 FROM tracks WHERE tracks.cover_id = covers.id)`,
		`DELETE FROM search_fts`,
		`INSERT INTO search_fts (kind, ref_id, title, artist, album)
		   SELECT 'artist', ar.id, '', ar.name, '' FROM artists ar
		   WHERE EXISTS (SELECT 1 FROM tracks t WHERE t.missing_since IS NULL
		                 AND (t.artist_id = ar.id OR t.album_id IN (SELECT id FROM albums WHERE album_artist_id = ar.id)))`,
		`INSERT INTO search_fts (kind, ref_id, title, artist, album)
		   SELECT 'album', al.id, '', ar.name, al.title FROM albums al
		   JOIN artists ar ON ar.id = al.album_artist_id WHERE al.track_count > 0`,
		`INSERT INTO search_fts (kind, ref_id, title, artist, album)
		   SELECT 'track', t.id, t.title, ar.name, al.title FROM tracks t
		   JOIN artists ar ON ar.id = t.artist_id JOIN albums al ON al.id = t.album_id
		   WHERE t.missing_since IS NULL`,
	}
	for _, s := range stmts {
		if _, err := w.tx.Exec(s); err != nil {
			return fmt.Errorf("finalize: %w", err)
		}
	}
	return nil
}

// PurgeMissing hard-deletes tracks missing for longer than maxAge. Their
// playlist entries, favourites and plays are removed by cascade.
func (db *DB) PurgeMissing(ctx context.Context, maxAge time.Duration) (int64, error) {
	var n int64
	err := db.WriteLibrary(ctx, func(w *LibWriter) error {
		res, err := w.tx.Exec(`DELETE FROM tracks WHERE missing_since IS NOT NULL AND missing_since < ?`,
			time.Now().Add(-maxAge).Unix())
		if err != nil {
			return err
		}
		if n, _ = res.RowsAffected(); n == 0 {
			return nil
		}
		return w.cleanupAndReindex()
	})
	return n, err
}

// Meta reads a key from the meta table ("" if absent).
func (db *DB) Meta(ctx context.Context, key string) (string, error) {
	var v string
	err := db.r.QueryRowContext(ctx, `SELECT value FROM meta WHERE key = ?`, key).Scan(&v)
	if err == sql.ErrNoRows {
		return "", nil
	}
	return v, err
}

func (db *DB) SetMeta(ctx context.Context, key, value string) error {
	_, err := db.w.ExecContext(ctx,
		`INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value`,
		key, value)
	return err
}

func dirName(p string) string {
	if i := strings.LastIndexByte(p, '/'); i >= 0 {
		return p[:i]
	}
	return ""
}

func baseName(p string) string {
	if i := strings.LastIndexByte(p, '/'); i >= 0 {
		p = p[i+1:]
	}
	if i := strings.LastIndexByte(p, '.'); i > 0 {
		p = p[:i]
	}
	return p
}

// AlbumsInDir returns the albums having a present track directly in dir.
func (w *LibWriter) AlbumsInDir(dir string) ([]int64, error) {
	prefix := dir + "/"
	if dir == "" {
		prefix = ""
	}
	rows, err := w.tx.Query(`
		SELECT DISTINCT album_id FROM tracks
		WHERE missing_since IS NULL AND substr(path, 1, ?) = ? AND instr(substr(path, ?), '/') = 0`,
		len(prefix), prefix, len(prefix)+1)
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

// CoverHash returns the content hash of a cover.
func (db *DB) CoverHash(ctx context.Context, id int64) (string, error) {
	var h string
	err := db.r.QueryRowContext(ctx, `SELECT hash FROM covers WHERE id = ?`, id).Scan(&h)
	return h, notFound(err)
}

// LibraryStats returns counts for status displays.
func (db *DB) LibraryStats(ctx context.Context) (tracks, albums, artists int, err error) {
	err = db.r.QueryRowContext(ctx, `SELECT
		(SELECT COUNT(*) FROM tracks WHERE missing_since IS NULL),
		(SELECT COUNT(*) FROM albums WHERE track_count > 0),
		(SELECT COUNT(*) FROM artists)`).Scan(&tracks, &albums, &artists)
	return
}
