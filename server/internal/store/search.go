package store

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"unicode"
)

type SearchResult struct {
	Artists []Artist `json:"artists"`
	Albums  []Album  `json:"albums"`
	Tracks  []Track  `json:"tracks"`
}

// ftsQuery turns user input into an FTS5 prefix query: every word must
// match the start of a token. "beat abb" → "beat"* "abb"*.
func ftsQuery(input string) string {
	words := strings.FieldsFunc(input, func(r rune) bool {
		return !unicode.IsLetter(r) && !unicode.IsNumber(r)
	})
	parts := make([]string, 0, len(words))
	for _, w := range words {
		parts = append(parts, `"`+w+`"*`)
	}
	return strings.Join(parts, " ")
}

// Filter narrows a search. Zero values mean "any". The bpm and key
// filters only keep analysed tracks.
type Filter struct {
	Genre   string
	YearMin int
	YearMax int
	Format  string
	BPMMin  float64
	BPMMax  float64
	Camelot string // 1A..12B
}

func (f Filter) active() bool {
	return f.Genre != "" || f.YearMin != 0 || f.YearMax != 0 || f.Format != "" ||
		f.BPMMin != 0 || f.BPMMax != 0 || f.Camelot != ""
}

// Validate normalises the key ("8a" → "8A") and refuses impossible values.
func (f *Filter) Validate() error {
	if f.Camelot != "" {
		f.Camelot = strings.ToUpper(strings.TrimSpace(f.Camelot))
		if camelotNeighbours(f.Camelot) == nil {
			return fmt.Errorf("%w: key must be a Camelot code, 1A to 12B", ErrInvalid)
		}
	}
	if f.BPMMin < 0 || f.BPMMax < 0 || f.BPMMax != 0 && f.BPMMin > f.BPMMax {
		return fmt.Errorf("%w: bpm range", ErrInvalid)
	}
	return nil
}

// trackConds returns SQL conditions on the tracks alias a (e.g. "t").
func (f Filter) trackConds(a string) (string, []any) {
	var sb strings.Builder
	var args []any
	if f.Genre != "" {
		sb.WriteString(" AND " + a + ".genre = ? COLLATE NOCASE")
		args = append(args, f.Genre)
	}
	if f.YearMin != 0 {
		sb.WriteString(" AND " + a + ".year >= ?")
		args = append(args, f.YearMin)
	}
	if f.YearMax != 0 {
		sb.WriteString(" AND " + a + ".year <= ?")
		args = append(args, f.YearMax)
	}
	if f.Format != "" {
		sb.WriteString(" AND " + a + ".format = ?")
		args = append(args, strings.ToLower(f.Format))
	}
	if f.BPMMin != 0 || f.BPMMax != 0 || f.Camelot != "" {
		sb.WriteString(" AND " + a + ".id IN (SELECT track_id FROM track_analysis WHERE error IS NULL")
		if f.BPMMin != 0 {
			sb.WriteString(" AND bpm >= ?")
			args = append(args, f.BPMMin)
		}
		if f.BPMMax != 0 {
			sb.WriteString(" AND bpm <= ?")
			args = append(args, f.BPMMax)
		}
		if f.Camelot != "" {
			sb.WriteString(" AND camelot = ?")
			args = append(args, f.Camelot)
		}
		sb.WriteString(")")
	}
	return sb.String(), args
}

// exists returns a condition "some present track joined on link matches".
func (f Filter) exists(link string) (string, []any) {
	conds, args := f.trackConds("ft")
	return " AND EXISTS (SELECT 1 FROM tracks ft WHERE ft.missing_since IS NULL AND " + link + conds + ")", args
}

// Search runs a prefix full-text search over artists, albums and tracks,
// narrowed by f. Results are ranked by bm25 with the title column weighted
// highest. With an empty input and an active filter, it lists what matches
// the filter (albums by year, tracks by title).
func (db *DB) Search(ctx context.Context, input string, f Filter, limit int) (SearchResult, error) {
	res := SearchResult{Artists: []Artist{}, Albums: []Album{}, Tracks: []Track{}}
	q := ftsQuery(input)
	if q == "" && !f.active() {
		return res, nil
	}
	maxLimit := 100
	if f.active() {
		maxLimit = 500 // browsing a genre or a decade
	}
	if limit <= 0 || limit > maxLimit {
		limit = min(20, maxLimit)
	}
	artistCond, artistArgs := f.exists("(ft.artist_id = a.id OR ft.album_id IN (SELECT id FROM albums WHERE album_artist_id = a.id))")
	albumCond, albumArgs := f.exists("ft.album_id = al.id")
	trackCond, trackArgs := f.trackConds("t")
	if !f.active() {
		artistCond, artistArgs, albumCond, albumArgs = "", nil, "", nil
	}

	if q == "" {
		var err error
		if res.Albums, err = db.albumList(ctx, albumSelect+albumCond+" ORDER BY COALESCE(al.year, 0) DESC, al.sort_title LIMIT ?",
			append(albumArgs, limit)...); err != nil {
			return res, err
		}
		res.Tracks, err = db.trackList(ctx, trackSelect+trackCond+" ORDER BY t.title COLLATE NOCASE LIMIT ?",
			append(trackArgs, limit)...)
		return res, err
	}

	// Weights: kind, ref_id, title, artist, album.
	const ranked = `SELECT ref_id, bm25(search_fts, 0, 0, 10, 5, 3) AS score
	                FROM search_fts WHERE search_fts MATCH ? AND kind = ? ORDER BY score LIMIT ?`
	// The FTS subquery is limited before filtering: over-fetch when filtering.
	ftsLimit := limit
	if f.active() {
		ftsLimit = 1000
	}

	args := append([]any{q, "artist", ftsLimit}, artistArgs...)
	rows, err := db.r.QueryContext(ctx, `SELECT a.* FROM (`+artistSelect+`) a
		JOIN (`+ranked+`) s ON s.ref_id = a.id WHERE 1=1`+artistCond+` ORDER BY s.score LIMIT ?`, append(args, limit)...)
	if err != nil {
		return res, err
	}
	for rows.Next() {
		a, _, err := scanArtist(rows)
		if err != nil {
			rows.Close()
			return res, err
		}
		res.Artists = append(res.Artists, a)
	}
	rows.Close()

	args = append([]any{q, "album", ftsLimit}, albumArgs...)
	if res.Albums, err = db.albumList(ctx, strings.Replace(albumSelect, "WHERE al.track_count > 0",
		"JOIN ("+ranked+") s ON s.ref_id = al.id WHERE al.track_count > 0", 1)+albumCond+" ORDER BY s.score LIMIT ?",
		append(args, limit)...); err != nil {
		return res, err
	}
	args = append([]any{q, "track", ftsLimit}, trackArgs...)
	if res.Tracks, err = db.trackList(ctx, strings.Replace(trackSelect, "WHERE t.missing_since IS NULL",
		"JOIN ("+ranked+") s ON s.ref_id = t.id WHERE t.missing_since IS NULL", 1)+trackCond+" ORDER BY s.score LIMIT ?",
		append(args, limit)...); err != nil {
		return res, err
	}
	return res, nil
}

// Facet is one filter value with the number of tracks having it.
type Facet struct {
	Name  string `json:"name"`
	Count int    `json:"count"`
}

// Facets lists the values available for search filters.
type Facets struct {
	Genres  []Facet `json:"genres"`
	Formats []Facet `json:"formats"`
	YearMin *int    `json:"year_min,omitempty"`
	YearMax *int    `json:"year_max,omitempty"`
}

func (db *DB) SearchFacets(ctx context.Context) (Facets, error) {
	out := Facets{Genres: []Facet{}, Formats: []Facet{}}
	list := func(q string) ([]Facet, error) {
		rows, err := db.r.QueryContext(ctx, q)
		if err != nil {
			return nil, err
		}
		defer rows.Close()
		res := []Facet{}
		for rows.Next() {
			var f Facet
			if err := rows.Scan(&f.Name, &f.Count); err != nil {
				return nil, err
			}
			res = append(res, f)
		}
		return res, rows.Err()
	}
	var err error
	if out.Genres, err = list(`SELECT MIN(genre), COUNT(*) FROM tracks
		WHERE missing_since IS NULL AND genre IS NOT NULL AND genre <> ''
		GROUP BY genre COLLATE NOCASE ORDER BY COUNT(*) DESC, MIN(genre)`); err != nil {
		return out, err
	}
	if out.Formats, err = list(`SELECT format, COUNT(*) FROM tracks WHERE missing_since IS NULL
		GROUP BY format ORDER BY COUNT(*) DESC`); err != nil {
		return out, err
	}
	var lo, hi sql.NullInt64
	if err := db.r.QueryRowContext(ctx, `SELECT MIN(year), MAX(year) FROM tracks
		WHERE missing_since IS NULL AND year > 0`).Scan(&lo, &hi); err != nil {
		return out, err
	}
	out.YearMin, out.YearMax = intPtr(lo), intPtr(hi)
	return out, nil
}
