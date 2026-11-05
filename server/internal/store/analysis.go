package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"math"
	"strings"
)

// Analysis is the audio analysis of one track (phase 3). The recommender
// service computes it from the file and reports it through the API.
// Fields the analyser could not compute are nil.
type Analysis struct {
	TrackID       int64        `json:"track_id"`
	Analyzer      string       `json:"analyzer"`
	AnalyzedAt    int64        `json:"analyzed_at"`
	Error         *string      `json:"error,omitempty"`
	BPM           *float64     `json:"bpm,omitempty"`
	Key           *string      `json:"key,omitempty"`   // C, C#... B
	Scale         *string      `json:"scale,omitempty"` // major, minor
	Camelot       *string      `json:"camelot,omitempty"`
	KeyStrength   *float64     `json:"key_strength,omitempty"`
	LoudnessLUFS  *float64     `json:"loudness_lufs,omitempty"`
	LoudnessRange *float64     `json:"loudness_range,omitempty"`
	Energy        *float64     `json:"energy,omitempty"`
	Danceability  *float64     `json:"danceability,omitempty"`
	Acousticness  *float64     `json:"acousticness,omitempty"`
	Mood          *string      `json:"mood,omitempty"`
	Genres        []GenreShare `json:"genres,omitempty"`
	Stale         bool         `json:"stale"` // the file changed since; queued again
}

type GenreShare struct {
	Name  string  `json:"name"`
	Share float64 `json:"share"` // 0..1
}

// AnalysisReport is what the analyser sends for one track.
type AnalysisReport struct {
	FileMtime     int64        `json:"file_mtime"`
	Analyzer      string       `json:"analyzer"`
	Error         string       `json:"error,omitempty"`
	BPM           *float64     `json:"bpm,omitempty"`
	Key           string       `json:"key,omitempty"`
	Scale         string       `json:"scale,omitempty"`
	KeyStrength   *float64     `json:"key_strength,omitempty"`
	LoudnessLUFS  *float64     `json:"loudness_lufs,omitempty"`
	LoudnessRange *float64     `json:"loudness_range,omitempty"`
	Energy        *float64     `json:"energy,omitempty"`
	Danceability  *float64     `json:"danceability,omitempty"`
	Acousticness  *float64     `json:"acousticness,omitempty"`
	Mood          string       `json:"mood,omitempty"`
	Genres        []GenreShare `json:"genres,omitempty"`
}

// pitch classes, sharps first; flats are accepted on input.
var pitchClasses = map[string]int{
	"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6,
	"G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11,
}

var sharpNames = [12]string{"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}

// Camelot returns the Camelot wheel notation of a key (8A = A minor,
// 8B = C major) and the key normalised to sharps.
func Camelot(key, scale string) (code, tonic string, ok bool) {
	pc, found := pitchClasses[key]
	if !found {
		return "", "", false
	}
	var letter string
	switch scale {
	case "major":
		letter = "B"
	case "minor":
		letter = "A"
		pc = (pc + 3) % 12 // relative major
	default:
		return "", "", false
	}
	// C major is 8B; each fifth up (+7 semitones) adds one.
	n := (7+7*pc)%12 + 1
	return fmt.Sprintf("%d%s", n, letter), sharpNames[pitchClasses[key]], true
}

// camelotNeighbours lists the codes that mix well with code: itself, one
// step around the wheel either way, and the relative major / minor.
func camelotNeighbours(code string) []string {
	var n int
	var letter string
	if _, err := fmt.Sscanf(code, "%d%s", &n, &letter); err != nil || n < 1 || n > 12 {
		return nil
	}
	other := "A"
	if letter == "A" {
		other = "B"
	}
	return []string{
		code,
		fmt.Sprintf("%d%s", n%12+1, letter),
		fmt.Sprintf("%d%s", (n+10)%12+1, letter),
		fmt.Sprintf("%d%s", n, other),
	}
}

func unit(name string, v *float64) error {
	if v != nil && (math.IsNaN(*v) || *v < 0 || *v > 1) {
		return fmt.Errorf("%w: %s must be between 0 and 1", ErrInvalid, name)
	}
	return nil
}

func finite(name string, v *float64, lo, hi float64) error {
	if v != nil && (math.IsNaN(*v) || *v < lo || *v > hi) {
		return fmt.Errorf("%w: %s out of range", ErrInvalid, name)
	}
	return nil
}

// SaveAnalysis stores (replacing) the analysis of a present track.
func (db *DB) SaveAnalysis(ctx context.Context, trackID int64, r AnalysisReport) error {
	if strings.TrimSpace(r.Analyzer) == "" {
		return fmt.Errorf("%w: analyzer is required", ErrInvalid)
	}
	var camelot, key sql.NullString
	if r.Key != "" || r.Scale != "" {
		code, tonic, ok := Camelot(r.Key, r.Scale)
		if !ok {
			return fmt.Errorf("%w: unknown key %q %q", ErrInvalid, r.Key, r.Scale)
		}
		camelot, key = nullStr(code), nullStr(tonic)
	}
	for _, err := range []error{
		finite("bpm", r.BPM, 20, 300),
		finite("loudness_lufs", r.LoudnessLUFS, -70, 10),
		finite("loudness_range", r.LoudnessRange, 0, 100),
		unit("key_strength", r.KeyStrength), unit("energy", r.Energy),
		unit("danceability", r.Danceability), unit("acousticness", r.Acousticness),
	} {
		if err != nil {
			return err
		}
	}
	var genres sql.NullString
	if len(r.Genres) > 0 {
		for _, g := range r.Genres {
			if g.Name == "" {
				return fmt.Errorf("%w: genre without a name", ErrInvalid)
			}
			if err := unit("genre share", &g.Share); err != nil {
				return err
			}
		}
		b, _ := json.Marshal(r.Genres)
		genres = nullStr(string(b))
	}
	return db.Tx(ctx, func(tx *sql.Tx) error {
		var present bool
		if err := tx.QueryRowContext(ctx,
			`SELECT EXISTS (SELECT 1 FROM tracks WHERE id = ? AND missing_since IS NULL)`, trackID).
			Scan(&present); err != nil {
			return err
		}
		if !present {
			return ErrNotFound
		}
		_, err := tx.ExecContext(ctx, `
			INSERT OR REPLACE INTO track_analysis (track_id, file_mtime, analyzer, analyzed_at, error,
			  bpm, key, scale, camelot, key_strength, loudness_lufs, loudness_range,
			  energy, danceability, acousticness, mood, genres)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			trackID, r.FileMtime, r.Analyzer, now(), nullStr(r.Error),
			r.BPM, key, nullStr(r.Scale), camelot, r.KeyStrength, r.LoudnessLUFS, r.LoudnessRange,
			r.Energy, r.Danceability, r.Acousticness, nullStr(r.Mood), genres)
		return err
	})
}

// TrackAnalysis returns the analysis of a track, or ErrNotFound if it has
// not been analysed yet.
func (db *DB) TrackAnalysis(ctx context.Context, trackID int64) (Analysis, error) {
	a := Analysis{TrackID: trackID}
	var genres sql.NullString
	err := db.r.QueryRowContext(ctx, `
		SELECT a.analyzer, a.analyzed_at, a.error, a.bpm, a.key, a.scale, a.camelot, a.key_strength,
		       a.loudness_lufs, a.loudness_range, a.energy, a.danceability, a.acousticness, a.mood,
		       a.genres, a.file_mtime != t.file_mtime
		FROM track_analysis a JOIN tracks t ON t.id = a.track_id
		WHERE a.track_id = ? AND t.missing_since IS NULL`, trackID).
		Scan(&a.Analyzer, &a.AnalyzedAt, &a.Error, &a.BPM, &a.Key, &a.Scale, &a.Camelot, &a.KeyStrength,
			&a.LoudnessLUFS, &a.LoudnessRange, &a.Energy, &a.Danceability, &a.Acousticness, &a.Mood,
			&genres, &a.Stale)
	if err != nil {
		return a, notFound(err)
	}
	if genres.Valid {
		if err := json.Unmarshal([]byte(genres.String), &a.Genres); err != nil {
			return a, err
		}
	}
	return a, nil
}

// ResetAnalysis forgets the analysis of one track (trackID > 0) or of the
// whole library (trackID == 0): the analyser picks them up again.
func (db *DB) ResetAnalysis(ctx context.Context, trackID int64) error {
	return db.Tx(ctx, func(tx *sql.Tx) error {
		if trackID == 0 {
			_, err := tx.ExecContext(ctx, `DELETE FROM track_analysis`)
			return err
		}
		var present bool
		if err := tx.QueryRowContext(ctx,
			`SELECT EXISTS (SELECT 1 FROM tracks WHERE id = ? AND missing_since IS NULL)`, trackID).
			Scan(&present); err != nil {
			return err
		}
		if !present {
			return ErrNotFound
		}
		_, err := tx.ExecContext(ctx, `DELETE FROM track_analysis WHERE track_id = ?`, trackID)
		return err
	})
}

// AnalysisJob is a track waiting for analysis.
type AnalysisJob struct {
	ID         int64  `json:"id"`
	Path       string `json:"path"` // relative to the music root
	FileMtime  int64  `json:"file_mtime"`
	DurationMs int64  `json:"duration_ms"`
}

// AnalysisQueue returns tracks never analysed, or whose file changed since,
// most recently added first. Failed analyses are only retried once the file
// changes (or after a reset).
func (db *DB) AnalysisQueue(ctx context.Context, limit int) ([]AnalysisJob, error) {
	rows, err := db.r.QueryContext(ctx, `
		SELECT t.id, t.path, t.file_mtime, t.duration_ms
		FROM tracks t LEFT JOIN track_analysis a ON a.track_id = t.id
		WHERE t.missing_since IS NULL AND (a.track_id IS NULL OR a.file_mtime != t.file_mtime)
		ORDER BY t.created_at DESC, t.id DESC LIMIT ?`, clampLimit(limit))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []AnalysisJob{}
	for rows.Next() {
		var j AnalysisJob
		if err := rows.Scan(&j.ID, &j.Path, &j.FileMtime, &j.DurationMs); err != nil {
			return nil, err
		}
		out = append(out, j)
	}
	return out, rows.Err()
}

// AnalysisStatus counts present tracks by analysis state.
type AnalysisStatus struct {
	Total    int `json:"total"`
	Analyzed int `json:"analyzed"`
	Failed   int `json:"failed"`
	Pending  int `json:"pending"` // never analysed, or the file changed
}

func (db *DB) AnalysisStatus(ctx context.Context) (AnalysisStatus, error) {
	var s AnalysisStatus
	err := db.r.QueryRowContext(ctx, `
		SELECT COUNT(*),
		       COALESCE(SUM(a.track_id IS NOT NULL AND a.file_mtime = t.file_mtime AND a.error IS NULL), 0),
		       COALESCE(SUM(a.track_id IS NOT NULL AND a.file_mtime = t.file_mtime AND a.error IS NOT NULL), 0)
		FROM tracks t LEFT JOIN track_analysis a ON a.track_id = t.id
		WHERE t.missing_since IS NULL`).Scan(&s.Total, &s.Analyzed, &s.Failed)
	s.Pending = s.Total - s.Analyzed - s.Failed
	return s, err
}

// CompatibleTracks returns tracks that chain well after trackID: a
// harmonically compatible key (Camelot neighbours) and a tempo within 6 %,
// closest tempo first. Empty if the track has no bpm or key.
func (db *DB) CompatibleTracks(ctx context.Context, trackID int64, limit int) ([]Track, error) {
	var bpm sql.NullFloat64
	var camelot sql.NullString
	err := db.r.QueryRowContext(ctx,
		`SELECT bpm, camelot FROM track_analysis WHERE track_id = ? AND error IS NULL`, trackID).
		Scan(&bpm, &camelot)
	if err != nil {
		return nil, notFound(err)
	}
	codes := camelotNeighbours(camelot.String)
	if !bpm.Valid || len(codes) == 0 {
		return []Track{}, nil
	}
	q := trackSelect + ` AND t.id != ? AND ta.camelot IN (?, ?, ?, ?) AND ta.bpm BETWEEN ? AND ?
		ORDER BY ABS(ta.bpm - ?), t.id LIMIT ?`
	return db.trackList(ctx, q, trackID, codes[0], codes[1], codes[2], codes[3],
		bpm.Float64*0.94, bpm.Float64*1.06, bpm.Float64, min(clampLimit(limit), 50))
}
