package store

import (
	"context"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
)

type Artist struct {
	ID         int64  `json:"id"`
	Name       string `json:"name"`
	AlbumCount int    `json:"album_count"`
	CoverID    *int64 `json:"cover_id,omitempty"` // cover of one of its albums
}

type Album struct {
	ID         int64   `json:"id"`
	Title      string  `json:"title"`
	ArtistID   int64   `json:"artist_id"`
	Artist     string  `json:"artist"`
	Year       *int    `json:"year,omitempty"`
	Genre      *string `json:"genre,omitempty"`
	CoverID    *int64  `json:"cover_id,omitempty"`
	TrackCount int     `json:"track_count"`
	DurationMs int64   `json:"duration_ms"`
	CreatedAt  int64   `json:"created_at"`
}

type Track struct {
	ID          int64    `json:"id"`
	Title       string   `json:"title"`
	ArtistID    int64    `json:"artist_id"`
	Artist      string   `json:"artist"`
	AlbumID     int64    `json:"album_id"`
	Album       string   `json:"album"`
	AlbumArtist string   `json:"album_artist"`
	TrackNo     *int     `json:"track_no,omitempty"`
	DiscNo      *int     `json:"disc_no,omitempty"`
	Year        *int     `json:"year,omitempty"`
	Genre       *string  `json:"genre,omitempty"`
	DurationMs  int64    `json:"duration_ms"`
	Format      string   `json:"format"`
	Codec       *string  `json:"codec,omitempty"`
	Bitrate     *int     `json:"bitrate,omitempty"`
	SampleRate  *int     `json:"sample_rate,omitempty"`
	BitDepth    *int     `json:"bit_depth,omitempty"`
	CoverID     *int64   `json:"cover_id,omitempty"`
	RGTrackGain *float64 `json:"rg_track_gain,omitempty"`
	RGTrackPeak *float64 `json:"rg_track_peak,omitempty"`
	RGAlbumGain *float64 `json:"rg_album_gain,omitempty"`
	RGAlbumPeak *float64 `json:"rg_album_peak,omitempty"`
	CreatedAt   int64    `json:"created_at"`
}

// Page is a keyset-paginated list. Next is empty on the last page.
type Page[T any] struct {
	Items []T    `json:"items"`
	Next  string `json:"next,omitempty"`
}

// cursor is the opaque pagination token: last sort value + last id.
type cursor struct {
	V  any   `json:"v"`
	ID int64 `json:"id"`
}

func encodeCursor(v any, id int64) string {
	b, _ := json.Marshal(cursor{V: v, ID: id})
	return base64.RawURLEncoding.EncodeToString(b)
}

func decodeCursor(s string) (*cursor, error) {
	if s == "" {
		return nil, nil
	}
	b, err := base64.RawURLEncoding.DecodeString(s)
	if err != nil {
		return nil, fmt.Errorf("%w: bad cursor", ErrInvalid)
	}
	var c cursor
	if err := json.Unmarshal(b, &c); err != nil {
		return nil, fmt.Errorf("%w: bad cursor", ErrInvalid)
	}
	return &c, nil
}

// sortSpec describes one keyset ordering: SQL expression, direction and
// how to read the sort value back from a scanned row.
type sortSpec struct {
	expr string
	desc bool
}

func (s sortSpec) where(c *cursor) (string, []any) {
	if c == nil {
		return "", nil
	}
	op := ">"
	if s.desc {
		op = "<"
	}
	return fmt.Sprintf(" AND (%[1]s %[2]s ? OR (%[1]s = ? AND id %[2]s ?))", s.expr, op), []any{c.V, c.V, c.ID}
}

func (s sortSpec) order() string {
	dir := "ASC"
	if s.desc {
		dir = "DESC"
	}
	return fmt.Sprintf(" ORDER BY %s %s, id %s", s.expr, dir, dir)
}

func clampLimit(limit int) int {
	if limit <= 0 {
		return 100
	}
	return min(limit, 500)
}

// --- Artists ---------------------------------------------------------------

const artistSelect = `
	SELECT id, name, album_count, cover_id, sort_name FROM (
	  SELECT ar.id, ar.name, ar.sort_name,
	    (SELECT COUNT(*) FROM albums al WHERE al.album_artist_id = ar.id AND al.track_count > 0) AS album_count,
	    (SELECT al.cover_id FROM albums al WHERE al.album_artist_id = ar.id AND al.cover_id IS NOT NULL
	     ORDER BY al.year DESC LIMIT 1) AS cover_id
	  FROM artists ar
	  WHERE EXISTS (SELECT 1 FROM tracks t WHERE t.missing_since IS NULL
	                AND (t.artist_id = ar.id OR t.album_id IN (SELECT id FROM albums WHERE album_artist_id = ar.id)))
	) WHERE 1=1`

func scanArtist(row interface{ Scan(...any) error }) (a Artist, sortName string, err error) {
	var cover sql.NullInt64
	err = row.Scan(&a.ID, &a.Name, &a.AlbumCount, &cover, &sortName)
	a.CoverID = ptrID(cover)
	return a, sortName, err
}

// Artists lists artists that have at least one present track, by sort name.
// albumArtistsOnly hides artists that only appear on compilations.
func (db *DB) Artists(ctx context.Context, after string, limit int, albumArtistsOnly bool) (Page[Artist], error) {
	limit = clampLimit(limit)
	c, err := decodeCursor(after)
	if err != nil {
		return Page[Artist]{}, err
	}
	spec := sortSpec{expr: "sort_name COLLATE NOCASE"}
	q := artistSelect
	if albumArtistsOnly {
		q += " AND album_count > 0"
	}
	w, args := spec.where(c)
	q += w + spec.order() + " LIMIT ?"
	rows, err := db.r.QueryContext(ctx, q, append(args, limit+1)...)
	if err != nil {
		return Page[Artist]{}, err
	}
	defer rows.Close()
	page := Page[Artist]{Items: []Artist{}}
	var lastSort string
	for rows.Next() {
		a, sortName, err := scanArtist(rows)
		if err != nil {
			return page, err
		}
		if len(page.Items) == limit {
			page.Next = encodeCursor(lastSort, page.Items[limit-1].ID)
			break
		}
		page.Items = append(page.Items, a)
		lastSort = sortName
	}
	return page, rows.Err()
}

func (db *DB) Artist(ctx context.Context, id int64) (Artist, error) {
	a, _, err := scanArtist(db.r.QueryRowContext(ctx, artistSelect+" AND id = ?", id))
	return a, notFound(err)
}

// --- Albums ----------------------------------------------------------------

const albumSelect = `
	SELECT al.id, al.title, al.album_artist_id, ar.name, al.year, al.genre, al.cover_id,
	       al.track_count, al.duration_ms, al.created_at /*extra*/
	FROM albums al JOIN artists ar ON ar.id = al.album_artist_id
	WHERE al.track_count > 0`

func scanAlbum(row interface{ Scan(...any) error }, extra ...any) (Album, error) {
	var a Album
	var year sql.NullInt64
	var genre sql.NullString
	var cover sql.NullInt64
	dest := append([]any{&a.ID, &a.Title, &a.ArtistID, &a.Artist, &year, &genre, &cover,
		&a.TrackCount, &a.DurationMs, &a.CreatedAt}, extra...)
	if err := row.Scan(dest...); err != nil {
		return a, err
	}
	if year.Valid {
		y := int(year.Int64)
		a.Year = &y
	}
	if genre.Valid {
		a.Genre = &genre.String
	}
	a.CoverID = ptrID(cover)
	return a, nil
}

var albumSorts = map[string]sortSpec{
	"name":  {expr: "al.sort_title COLLATE NOCASE"},
	"added": {expr: "al.created_at", desc: true},
	"year":  {expr: "COALESCE(al.year, 0)", desc: true},
}

// Albums lists albums. sort is one of name, added, year.
func (db *DB) Albums(ctx context.Context, sort, after string, limit int) (Page[Album], error) {
	limit = clampLimit(limit)
	spec, ok := albumSorts[sort]
	if !ok {
		spec = albumSorts["name"]
	}
	c, err := decodeCursor(after)
	if err != nil {
		return Page[Album]{}, err
	}
	w, args := spec.where(c)
	w = strings.ReplaceAll(w, " id ", " al.id ")
	order := strings.ReplaceAll(spec.order(), " id ", " al.id ")
	q := strings.Replace(albumSelect, "/*extra*/", ", "+spec.expr, 1) + w + order + " LIMIT ?"
	rows, err := db.r.QueryContext(ctx, q, append(args, limit+1)...)
	if err != nil {
		return Page[Album]{}, err
	}
	defer rows.Close()
	page := Page[Album]{Items: []Album{}}
	var last any
	for rows.Next() {
		var sortVal any
		a, err := scanAlbum(rows, &sortVal)
		if err != nil {
			return page, err
		}
		if len(page.Items) == limit {
			page.Next = encodeCursor(last, page.Items[limit-1].ID)
			break
		}
		page.Items = append(page.Items, a)
		last = sortVal
	}
	return page, rows.Err()
}

func (db *DB) Album(ctx context.Context, id int64) (Album, error) {
	a, err := scanAlbum(db.r.QueryRowContext(ctx, albumSelect+" AND al.id = ?", id))
	return a, notFound(err)
}

// ArtistAlbums returns the albums where the artist is album artist, newest first.
func (db *DB) ArtistAlbums(ctx context.Context, artistID int64) ([]Album, error) {
	return db.albumList(ctx, albumSelect+" AND al.album_artist_id = ? ORDER BY al.year DESC, al.sort_title", artistID)
}

// RecentAlbums returns the most recently added albums.
func (db *DB) RecentAlbums(ctx context.Context, limit int) ([]Album, error) {
	return db.albumList(ctx, albumSelect+" ORDER BY al.created_at DESC, al.id DESC LIMIT ?", clampLimit(limit))
}

func (db *DB) albumList(ctx context.Context, q string, args ...any) ([]Album, error) {
	rows, err := db.r.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Album{}
	for rows.Next() {
		a, err := scanAlbum(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

// --- Tracks ----------------------------------------------------------------

const trackSelect = `
	SELECT t.id, t.title, t.artist_id, ar.name, t.album_id, al.title, aar.name,
	       t.track_no, t.disc_no, t.year, t.genre, t.duration_ms, t.format, t.codec,
	       t.bitrate, t.sample_rate, t.bit_depth, COALESCE(t.cover_id, al.cover_id),
	       t.rg_track_gain, t.rg_track_peak, t.rg_album_gain, t.rg_album_peak, t.created_at /*extra*/
	FROM tracks t
	JOIN artists ar  ON ar.id = t.artist_id
	JOIN albums  al  ON al.id = t.album_id
	JOIN artists aar ON aar.id = al.album_artist_id
	WHERE t.missing_since IS NULL`

func scanTrack(row interface{ Scan(...any) error }, extra ...any) (Track, error) {
	var t Track
	var trackNo, discNo, year, bitrate, sampleRate, bitDepth, cover sql.NullInt64
	var genre, codec sql.NullString
	dest := append([]any{&t.ID, &t.Title, &t.ArtistID, &t.Artist, &t.AlbumID, &t.Album, &t.AlbumArtist,
		&trackNo, &discNo, &year, &genre, &t.DurationMs, &t.Format, &codec,
		&bitrate, &sampleRate, &bitDepth, &cover,
		&t.RGTrackGain, &t.RGTrackPeak, &t.RGAlbumGain, &t.RGAlbumPeak, &t.CreatedAt}, extra...)
	if err := row.Scan(dest...); err != nil {
		return t, err
	}
	t.TrackNo, t.DiscNo, t.Year = intPtr(trackNo), intPtr(discNo), intPtr(year)
	t.Bitrate, t.SampleRate, t.BitDepth = intPtr(bitrate), intPtr(sampleRate), intPtr(bitDepth)
	if genre.Valid {
		t.Genre = &genre.String
	}
	if codec.Valid {
		t.Codec = &codec.String
	}
	t.CoverID = ptrID(cover)
	return t, nil
}

func intPtr(n sql.NullInt64) *int {
	if !n.Valid {
		return nil
	}
	v := int(n.Int64)
	return &v
}

func (db *DB) trackList(ctx context.Context, q string, args ...any) ([]Track, error) {
	rows, err := db.r.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Track{}
	for rows.Next() {
		t, err := scanTrack(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

var trackSorts = map[string]sortSpec{
	"name":  {expr: "t.title COLLATE NOCASE"},
	"added": {expr: "t.created_at", desc: true},
}

// Tracks lists all present tracks. sort is name or added.
func (db *DB) Tracks(ctx context.Context, sort, after string, limit int) (Page[Track], error) {
	limit = clampLimit(limit)
	spec, ok := trackSorts[sort]
	if !ok {
		spec = trackSorts["name"]
	}
	c, err := decodeCursor(after)
	if err != nil {
		return Page[Track]{}, err
	}
	w, args := spec.where(c)
	w = strings.ReplaceAll(w, " id ", " t.id ")
	order := strings.ReplaceAll(spec.order(), " id ", " t.id ")
	q := strings.Replace(trackSelect, "/*extra*/", ", "+spec.expr, 1) + w + order + " LIMIT ?"
	rows, err := db.r.QueryContext(ctx, q, append(args, limit+1)...)
	if err != nil {
		return Page[Track]{}, err
	}
	defer rows.Close()
	page := Page[Track]{Items: []Track{}}
	var last any
	for rows.Next() {
		var sortVal any
		t, err := scanTrack(rows, &sortVal)
		if err != nil {
			return page, err
		}
		if len(page.Items) == limit {
			page.Next = encodeCursor(last, page.Items[limit-1].ID)
			break
		}
		page.Items = append(page.Items, t)
		last = sortVal
	}
	return page, rows.Err()
}

func (db *DB) Track(ctx context.Context, id int64) (Track, error) {
	t, err := scanTrack(db.r.QueryRowContext(ctx, trackSelect+" AND t.id = ?", id))
	return t, notFound(err)
}

func (db *DB) AlbumTracks(ctx context.Context, albumID int64) ([]Track, error) {
	return db.trackList(ctx, trackSelect+" AND t.album_id = ? ORDER BY t.disc_no, t.track_no, t.path", albumID)
}

// TrackFileInfo is what streaming needs to know about a track's file.
type TrackFileInfo struct {
	Path       string
	Format     string
	DurationMs int64
	Mtime      int64
}

// TrackFileInfo returns file information for a present track.
func (db *DB) TrackFileInfo(ctx context.Context, id int64) (TrackFileInfo, error) {
	var f TrackFileInfo
	err := db.r.QueryRowContext(ctx,
		`SELECT path, format, duration_ms, file_mtime FROM tracks WHERE id = ? AND missing_since IS NULL`, id).
		Scan(&f.Path, &f.Format, &f.DurationMs, &f.Mtime)
	return f, notFound(err)
}

// RecentItem is one "recently played" shortcut: the album, artist or
// playlist plays were started from. Exactly one of the pointers is set.
type RecentItem struct {
	Kind     string    `json:"kind"` // album, artist, playlist
	Album    *Album    `json:"album,omitempty"`
	Artist   *Artist   `json:"artist,omitempty"`
	Playlist *Playlist `json:"playlist,omitempty"`
}

// RecentlyPlayed returns what recent plays were started from, most recent
// first. A play started from a playlist or an artist counts for it; any
// other play counts for the track's album.
func (db *DB) RecentlyPlayed(ctx context.Context, limit int) ([]RecentItem, error) {
	type key struct {
		kind string
		id   int64
	}
	rows, err := db.r.QueryContext(ctx, `
		SELECT kind, id FROM (
		  SELECT CASE WHEN p.context_kind IN ('playlist', 'artist') AND p.context_id IS NOT NULL
		              THEN p.context_kind ELSE 'album' END AS kind,
		         CASE WHEN p.context_kind IN ('playlist', 'artist') AND p.context_id IS NOT NULL
		              THEN p.context_id ELSE t.album_id END AS id,
		         MAX(p.started_at) AS last
		  FROM plays p JOIN tracks t ON t.id = p.track_id
		  GROUP BY 1, 2)
		WHERE (kind = 'album'    AND id IN (SELECT id FROM albums WHERE track_count > 0))
		   OR (kind = 'artist'   AND id IN (SELECT id FROM artists))
		   OR (kind = 'playlist' AND id IN (SELECT id FROM playlists))
		ORDER BY last DESC LIMIT ?`, clampLimit(limit))
	if err != nil {
		return nil, err
	}
	var keys []key
	for rows.Next() {
		var k key
		if err := rows.Scan(&k.kind, &k.id); err != nil {
			rows.Close()
			return nil, err
		}
		keys = append(keys, k)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}

	out := []RecentItem{}
	for _, k := range keys {
		it := RecentItem{Kind: k.kind}
		switch k.kind {
		case "album":
			a, e := db.Album(ctx, k.id)
			it.Album, err = &a, e
		case "artist":
			a, e := db.Artist(ctx, k.id)
			it.Artist, err = &a, e
		case "playlist":
			p, e := db.Playlist(ctx, k.id)
			it.Playlist, err = &p, e
		}
		if errors.Is(err, ErrNotFound) { // e.g. an artist left with no present track
			continue
		}
		if err != nil {
			return nil, err
		}
		out = append(out, it)
	}
	return out, nil
}
