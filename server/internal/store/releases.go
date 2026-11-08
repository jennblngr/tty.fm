package store

import (
	"context"
	"database/sql"
	"fmt"
	"regexp"
	"strings"
	"time"
	"unicode"
)

// New releases (phase 3). The recommender asks which album artists to look
// up (ReleaseQueue), finds them on MusicBrainz and sends their release
// groups (SaveArtistReleases); NewReleases compares them with the library.

// releaseRecheck is how long an artist's releases are trusted.
const releaseRecheck = 7 * 24 * time.Hour

// ReleaseJob is an album artist to look up on MusicBrainz.
type ReleaseJob struct {
	ArtistID int64    `json:"artist_id"`
	Name     string   `json:"name"`
	MBID     *string  `json:"mbid,omitempty"` // from the tags or an earlier lookup
	Albums   []string `json:"albums"`         // titles in the library, to tell namesakes apart
}

// ReleaseReport is what the recommender found for an artist. A nil MBID
// means MusicBrainz has no such artist.
type ReleaseReport struct {
	MBID     *string         `json:"mbid"`
	Releases []ReleaseRecord `json:"releases"`
}

// ReleaseRecord is a MusicBrainz release group.
type ReleaseRecord struct {
	MBID     string `json:"mbid"`
	Title    string `json:"title"`
	Kind     string `json:"kind"`     // album, ep, single
	Released string `json:"released"` // YYYY-MM-DD, YYYY-MM or YYYY
}

var releaseDate = regexp.MustCompile(`^\d{4}(-\d{2}(-\d{2})?)?$`)

// ReleaseQueue lists the album artists (and the liked artists)
// whose releases were never looked up or are more than a week old, the
// most listened first.
func (db *DB) ReleaseQueue(ctx context.Context, limit int, now time.Time) ([]ReleaseJob, error) {
	limit = min(clampLimit(limit), 50)
	rows, err := db.r.QueryContext(ctx, `
		SELECT ar.id, ar.name, COALESCE(NULLIF(ar.mbid, ''), l.mbid)
		FROM artists ar LEFT JOIN artist_lookups l ON l.artist_id = ar.id
		WHERE (EXISTS (SELECT 1 FROM albums al WHERE al.album_artist_id = ar.id AND al.track_count > 0)
		       OR ar.id IN (SELECT artist_id FROM favorite_artists))
		  AND (l.checked_at IS NULL OR l.checked_at < ?)
		ORDER BY l.checked_at IS NOT NULL, l.checked_at,
		         (SELECT -COALESCE(SUM(p.listened_ms), 0) FROM plays p JOIN tracks t ON t.id = p.track_id
		          WHERE t.artist_id = ar.id), ar.id
		LIMIT ?`, now.Add(-releaseRecheck).Unix(), limit)
	if err != nil {
		return nil, err
	}
	jobs := []ReleaseJob{}
	for rows.Next() {
		var j ReleaseJob
		var mbid sql.NullString
		if err := rows.Scan(&j.ArtistID, &j.Name, &mbid); err != nil {
			rows.Close()
			return nil, err
		}
		if mbid.Valid {
			j.MBID = &mbid.String
		}
		jobs = append(jobs, j)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}
	for i := range jobs {
		jobs[i].Albums = []string{}
		ar, err := db.r.QueryContext(ctx, `SELECT title FROM albums WHERE album_artist_id = ? AND track_count > 0
			ORDER BY sort_title`, jobs[i].ArtistID)
		if err != nil {
			return nil, err
		}
		for ar.Next() {
			var t string
			if err := ar.Scan(&t); err != nil {
				ar.Close()
				return nil, err
			}
			jobs[i].Albums = append(jobs[i].Albums, t)
		}
		ar.Close()
	}
	return jobs, nil
}

// SaveArtistReleases stores what MusicBrainz knows of an artist, in place
// of the previous lookup. ErrNotFound if the artist is not in the library.
func (db *DB) SaveArtistReleases(ctx context.Context, artistID int64, r ReleaseReport, now time.Time) error {
	for _, rel := range r.Releases {
		switch {
		case rel.MBID == "" || strings.TrimSpace(rel.Title) == "":
			return fmt.Errorf("%w: a release needs an mbid and a title", ErrInvalid)
		case rel.Kind != "album" && rel.Kind != "ep" && rel.Kind != "single":
			return fmt.Errorf("%w: release kind must be album, ep or single", ErrInvalid)
		case !releaseDate.MatchString(rel.Released):
			return fmt.Errorf("%w: release date must be YYYY, YYYY-MM or YYYY-MM-DD", ErrInvalid)
		}
	}
	tx, err := db.w.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback() //nolint:errcheck // no-op after Commit
	_, err = tx.ExecContext(ctx, `INSERT INTO artist_lookups (artist_id, mbid, checked_at) VALUES (?, ?, ?)
		ON CONFLICT (artist_id) DO UPDATE SET mbid = excluded.mbid, checked_at = excluded.checked_at`,
		artistID, r.MBID, now.Unix())
	if isFKError(err) {
		return ErrNotFound
	} else if err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `DELETE FROM artist_releases WHERE artist_id = ?`, artistID); err != nil {
		return err
	}
	for _, rel := range r.Releases {
		if _, err := tx.ExecContext(ctx, `INSERT INTO artist_releases (artist_id, mbid, title, kind, released)
			VALUES (?, ?, ?, ?, ?) ON CONFLICT DO NOTHING`,
			artistID, rel.MBID, strings.TrimSpace(rel.Title), rel.Kind, rel.Released); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// NewRelease is a recent or upcoming release of an artist of the library.
type NewRelease struct {
	ArtistID int64  `json:"artist_id"`
	Artist   string `json:"artist"`
	MBID     string `json:"mbid"`
	Title    string `json:"title"`
	Kind     string `json:"kind"`
	Released string `json:"released"`
	Upcoming bool   `json:"upcoming"`           // not out yet
	AlbumID  *int64 `json:"album_id,omitempty"` // the matching album of the library, if any
}

// NewReleases lists the releases of the last days days and the upcoming
// ones, most recent first, with the library's matching album when there is
// one ("25 (Deluxe)" matches "25"). Dates without a day count as the first
// of the month; a bare year is too vague and left out.
func (db *DB) NewReleases(ctx context.Context, now time.Time, days, limit int) ([]NewRelease, error) {
	limit = min(clampLimit(limit), 100)
	from := now.AddDate(0, 0, -days).Format("2006-01-02")
	today := now.Format("2006-01-02")
	rows, err := db.r.QueryContext(ctx, `
		SELECT r.artist_id, ar.name, r.mbid, r.title, r.kind, r.released
		FROM artist_releases r JOIN artists ar ON ar.id = r.artist_id
		WHERE length(r.released) >= 7
		  AND (CASE length(r.released) WHEN 7 THEN r.released || '-01' ELSE r.released END) >= ?
		ORDER BY r.released DESC, r.title LIMIT ?`, from, limit)
	if err != nil {
		return nil, err
	}
	out := []NewRelease{}
	for rows.Next() {
		var n NewRelease
		if err := rows.Scan(&n.ArtistID, &n.Artist, &n.MBID, &n.Title, &n.Kind, &n.Released); err != nil {
			rows.Close()
			return nil, err
		}
		day := n.Released
		if len(day) == 7 {
			day += "-01"
		}
		n.Upcoming = day > today
		out = append(out, n)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}
	// The library's albums of these artists, by release key.
	albums := map[int64]map[string]int64{}
	for i := range out {
		a, ok := albums[out[i].ArtistID]
		if !ok {
			a = map[string]int64{}
			ar, err := db.r.QueryContext(ctx, `SELECT id, title FROM albums
				WHERE album_artist_id = ? AND track_count > 0`, out[i].ArtistID)
			if err != nil {
				return nil, err
			}
			for ar.Next() {
				var id int64
				var title string
				if err := ar.Scan(&id, &title); err != nil {
					ar.Close()
					return nil, err
				}
				a[releaseKey(title)] = id
			}
			ar.Close()
			albums[out[i].ArtistID] = a
		}
		if id, ok := a[releaseKey(out[i].Title)]; ok {
			out[i].AlbumID = &id
		}
	}
	return out, nil
}

var releaseExtra = regexp.MustCompile(`\s*[\(\[][^\)\]]*[\)\]]`)

// releaseKey compares album titles across editions: no parenthesised
// part ("(Deluxe Edition)", "[Remastered]"), no accents, no punctuation.
func releaseKey(title string) string {
	clean := func(t string) string {
		return MatchKey(strings.Map(func(r rune) rune {
			if unicode.IsLetter(r) || unicode.IsNumber(r) || unicode.IsSpace(r) {
				return r
			}
			return ' '
		}, t))
	}
	if k := clean(releaseExtra.ReplaceAllString(title, "")); k != "" {
		return k
	}
	return clean(title) // all in parentheses: "(What's the Story)"
}
