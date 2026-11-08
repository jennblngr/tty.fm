package store

import (
	"context"
	"database/sql"
	"fmt"
	"math"
	"strings"

	sqlitevec "github.com/asg017/sqlite-vec-go-bindings/cgo"
)

// EmbeddingDims is the size of the Discogs EffNet embeddings the
// recommender sends (track_embeddings, migration 0005).
const EmbeddingDims = 1280

// serializeEmbedding checks an embedding and encodes it for sqlite-vec.
func serializeEmbedding(v []float32) ([]byte, error) {
	if len(v) != EmbeddingDims {
		return nil, fmt.Errorf("%w: embedding must have %d values, not %d", ErrInvalid, EmbeddingDims, len(v))
	}
	var norm float64
	for _, x := range v {
		f := float64(x)
		if math.IsNaN(f) || math.IsInf(f, 0) {
			return nil, fmt.Errorf("%w: embedding values must be finite", ErrInvalid)
		}
		norm += f * f
	}
	if norm == 0 { // no direction: the cosine distance is undefined
		return nil, fmt.Errorf("%w: embedding is all zeros", ErrInvalid)
	}
	return sqlitevec.SerializeFloat32(v)
}

// saveEmbedding replaces the embedding of a track (nil removes it: an
// analysis without one, such as an error, must not keep the old vector).
func saveEmbedding(ctx context.Context, tx *sql.Tx, trackID int64, blob []byte) error {
	if _, err := tx.ExecContext(ctx, `DELETE FROM track_embeddings WHERE track_id = ?`, trackID); err != nil {
		return err
	}
	if blob == nil {
		return nil
	}
	_, err := tx.ExecContext(ctx, `INSERT INTO track_embeddings (track_id, embedding) VALUES (?, ?)`, trackID, blob)
	return err
}

// SimilarTrack is a track and how close it sounds to the reference one.
type SimilarTrack struct {
	Track
	Similarity float64 `json:"similarity"` // cosine similarity, 1 = same sound
}

// SimilarTracks returns the present tracks that sound closest to trackID
// (cosine distance between their embeddings), closest first, without the
// track itself nor the hidden ones. Empty if trackID has no embedding yet
// (not analysed, or analysed without the ML models); ErrNotFound if it is
// not in the library.
func (db *DB) SimilarTracks(ctx context.Context, trackID int64, limit int) ([]SimilarTrack, error) {
	limit = min(clampLimit(limit), 100)
	var present bool
	var blob []byte
	err := db.r.QueryRowContext(ctx, `
		SELECT EXISTS (SELECT 1 FROM tracks WHERE id = ?1 AND missing_since IS NULL),
		       (SELECT embedding FROM track_embeddings WHERE track_id = ?1)`, trackID).Scan(&present, &blob)
	if err != nil {
		return nil, err
	}
	if !present {
		return nil, ErrNotFound
	}
	out := []SimilarTrack{}
	if blob == nil {
		return out, nil
	}
	// The nearest neighbours come first, then the filters: ask for more than
	// limit so that the track itself, missing and hidden tracks leave enough.
	k := min(2*limit+32, 4096)
	q := `WITH knn AS MATERIALIZED (
		SELECT track_id, distance FROM track_embeddings WHERE embedding MATCH ? AND k = ?
	)` + strings.Replace(trackSelect, "/*extra*/", ", knn.distance", 1)
	q = strings.Replace(q, "FROM tracks t", "FROM knn JOIN tracks t ON t.id = knn.track_id", 1) + `
		AND t.id != ? AND t.id NOT IN (SELECT track_id FROM hidden_tracks)
		ORDER BY knn.distance, t.id LIMIT ?`
	rows, err := db.r.QueryContext(ctx, q, blob, k, trackID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var distance float64
		t, err := scanTrack(rows, &distance)
		if err != nil {
			return nil, err
		}
		out = append(out, SimilarTrack{Track: t, Similarity: math.Round((1-distance)*1000) / 1000})
	}
	return out, rows.Err()
}
