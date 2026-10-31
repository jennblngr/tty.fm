package store

import (
	"context"
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

// Search runs a prefix full-text search over artists, albums and tracks.
// Results are ranked by bm25 with the title column weighted highest.
func (db *DB) Search(ctx context.Context, input string, limit int) (SearchResult, error) {
	res := SearchResult{Artists: []Artist{}, Albums: []Album{}, Tracks: []Track{}}
	q := ftsQuery(input)
	if q == "" {
		return res, nil
	}
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	// Weights: kind, ref_id, title, artist, album.
	const ranked = `SELECT ref_id, bm25(search_fts, 0, 0, 10, 5, 3) AS score
	                FROM search_fts WHERE search_fts MATCH ? AND kind = ? ORDER BY score LIMIT ?`

	rows, err := db.r.QueryContext(ctx, `SELECT a.* FROM (`+artistSelect+`) a
		JOIN (`+ranked+`) s ON s.ref_id = a.id ORDER BY s.score`, q, "artist", limit)
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

	if res.Albums, err = db.albumList(ctx, strings.Replace(albumSelect, "WHERE al.track_count > 0",
		"JOIN ("+ranked+") s ON s.ref_id = al.id WHERE al.track_count > 0", 1)+" ORDER BY s.score",
		q, "album", limit); err != nil {
		return res, err
	}
	if res.Tracks, err = db.trackList(ctx, strings.Replace(trackSelect, "WHERE t.missing_since IS NULL",
		"JOIN ("+ranked+") s ON s.ref_id = t.id WHERE t.missing_since IS NULL", 1)+" ORDER BY s.score",
		q, "track", limit); err != nil {
		return res, err
	}
	return res, nil
}
