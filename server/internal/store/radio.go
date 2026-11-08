package store

import (
	"context"
	"database/sql"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"math"
	"sort"
	"strings"

	sqlitevec "github.com/asg017/sqlite-vec-go-bindings/cgo"
)

// Radio tuning. A batch keeps the neighbours of the seed from all coming
// out of one album: at most radioPerAlbum tracks per album and
// radioPerArtist per artist, never the same artist twice in a row. These
// limits are relaxed step by step only when the library is too small to
// fill the batch otherwise.
const (
	radioPerAlbum  = 1
	radioPerArtist = 2
	// radioDrift is how many of the last played tracks steer the next batch,
	// along with the seed, so that an endless radio drifts.
	radioDrift = 3
	// radioMixBonus is added to the similarity of a track that mixes well
	// with the last one (neighbouring key, bpm within ±6 %).
	radioMixBonus = 0.05
	radioMaxLimit = 50
)

// RadioRequest asks for a batch of radio tracks. Exactly one of TrackID and
// ArtistID is the seed. The client asks for the next batch with the same
// seed, the tracks played since in Recent and those already queued in
// Exclude.
type RadioRequest struct {
	TrackID  int64
	ArtistID int64
	Recent   []int64 // last played tracks, oldest first: steer and excluded
	Exclude  []int64 // tracks already queued or played: left out
	Limit    int
}

// RadioSeed names what a radio started from, for the queue header.
type RadioSeed struct {
	Kind string `json:"kind"` // "track" or "artist"
	ID   int64  `json:"id"`
	Name string `json:"name"` // track title or artist name
}

// RadioTrack is a track of a radio batch. Similarity is set when it was
// found from the embeddings, absent when it comes from the fallback.
type RadioTrack struct {
	Track
	Similarity *float64 `json:"similarity,omitempty"`
}

// Radio is a batch of tracks to play after a seed.
type Radio struct {
	Seed RadioSeed `json:"seed"`
	// Mode is "similar" when the batch comes from the embeddings, "fallback"
	// when nothing could steer it (no embedding yet): same genre, same
	// artist, then the rest of the library.
	Mode  string       `json:"mode"`
	Items []RadioTrack `json:"items"`
}

// Radio builds a batch of tracks that sound like the seed and the last
// played tracks: the nearest neighbours of their mean embedding, a small
// bonus for those that mix well with the last track, spread across albums
// and artists. Without embeddings (tracks not yet analysed with the ML
// models), or when they leave the batch short, it falls back on the genre
// and the artist of the seed. Missing and hidden tracks are left out.
// ErrNotFound if the seed is not in the library.
func (db *DB) Radio(ctx context.Context, req RadioRequest) (Radio, error) {
	limit := req.Limit
	if limit <= 0 {
		limit = 20
	}
	limit = min(limit, radioMaxLimit)

	out := Radio{Mode: "similar", Items: []RadioTrack{}}
	var seedVecs [][]float32
	var seedArtist int64
	ref := req.TrackID // the track the next one should mix with
	switch {
	case req.TrackID > 0:
		var blob []byte
		err := db.r.QueryRowContext(ctx, `
			SELECT t.title, t.artist_id, (SELECT embedding FROM track_embeddings WHERE track_id = t.id)
			FROM tracks t WHERE t.id = ? AND t.missing_since IS NULL`, req.TrackID).
			Scan(&out.Seed.Name, &seedArtist, &blob)
		if err != nil {
			return out, notFound(err)
		}
		out.Seed.Kind, out.Seed.ID = "track", req.TrackID
		if blob != nil {
			seedVecs = append(seedVecs, decodeEmbedding(blob))
		}
	case req.ArtistID > 0:
		err := db.r.QueryRowContext(ctx, `SELECT name FROM artists WHERE id = ?`, req.ArtistID).Scan(&out.Seed.Name)
		if err != nil {
			return out, notFound(err)
		}
		out.Seed.Kind, out.Seed.ID, seedArtist = "artist", req.ArtistID, req.ArtistID
		vecs, err := db.artistEmbeddings(ctx, req.ArtistID)
		if err != nil {
			return out, err
		}
		if m := meanDirection(vecs); m != nil {
			seedVecs = append(seedVecs, m)
		}
	default:
		return out, fmt.Errorf("%w: radio needs a track or an artist", ErrInvalid)
	}

	// The last played tracks steer the batch as much as the seed each.
	var prevArtist int64
	recent := req.Recent[max(0, len(req.Recent)-radioDrift):]
	for i, id := range recent {
		var artist int64
		var blob []byte
		err := db.r.QueryRowContext(ctx, `
			SELECT t.artist_id, (SELECT embedding FROM track_embeddings WHERE track_id = t.id)
			FROM tracks t WHERE t.id = ?`, id).Scan(&artist, &blob)
		if err == sql.ErrNoRows {
			continue
		} else if err != nil {
			return out, err
		}
		if blob != nil {
			seedVecs = append(seedVecs, decodeEmbedding(blob))
		}
		if i == len(recent)-1 {
			prevArtist, ref = artist, id
		}
	}

	excluded := append(append([]int64{req.TrackID}, req.Recent...), req.Exclude...)
	exclJSON, _ := json.Marshal(excluded)
	mix, err := db.mixFilter(ctx, ref)
	if err != nil {
		return out, err
	}

	var cands []RadioTrack
	if q := meanDirection(seedVecs); q != nil {
		cands, err = db.radioNeighbours(ctx, q, limit, len(excluded), string(exclJSON), mix)
		if err != nil {
			return out, err
		}
	}
	if len(cands) == 0 {
		out.Mode = "fallback"
	}
	if pickDiverse(cands, limit, prevArtist, false) < limit {
		more, err := db.radioFallback(ctx, req, seedArtist, string(exclJSON), mix)
		if err != nil {
			return out, err
		}
		cands = append(cands, more...)
	}
	n := pickDiverse(cands, limit, prevArtist, true)
	out.Items = append(out.Items, cands[:n]...)
	return out, nil
}

// radioNeighbours returns the nearest present, not hidden, not excluded
// tracks to vec, best score first.
func (db *DB) radioNeighbours(ctx context.Context, vec []float32, limit, nExcluded int, exclJSON string, mix func(Track) bool) ([]RadioTrack, error) {
	blob, err := sqlitevec.SerializeFloat32(vec)
	if err != nil {
		return nil, err
	}
	// Ask for many more than limit: the diversity rules throw most away.
	k := min(10*limit+nExcluded+64, 4096)
	q := `WITH knn AS MATERIALIZED (
		SELECT track_id, distance FROM track_embeddings WHERE embedding MATCH ? AND k = ?
	)` + strings.Replace(trackSelect, "/*extra*/", ", knn.distance", 1)
	q = strings.Replace(q, "FROM tracks t", "FROM knn JOIN tracks t ON t.id = knn.track_id", 1) + `
		AND t.id NOT IN (SELECT track_id FROM hidden_tracks)
		AND t.id NOT IN (SELECT value FROM json_each(?))
		ORDER BY knn.distance, t.id`
	rows, err := db.r.QueryContext(ctx, q, blob, k, exclJSON)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []RadioTrack
	var scores []float64
	for rows.Next() {
		var distance float64
		t, err := scanTrack(rows, &distance)
		if err != nil {
			return nil, err
		}
		sim := math.Round((1-distance)*1000) / 1000
		score := sim
		if mix(t) {
			score += radioMixBonus
		}
		out = append(out, RadioTrack{Track: t, Similarity: &sim})
		scores = append(scores, score)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	idx := make([]int, len(out))
	for i := range idx {
		idx[i] = i
	}
	sort.SliceStable(idx, func(a, b int) bool { return scores[idx[a]] > scores[idx[b]] })
	sorted := make([]RadioTrack, len(out))
	for i, j := range idx {
		sorted[i] = out[j]
	}
	return sorted, nil
}

// radioFallback returns tracks of the genre or the artist of the seed in
// random order, then the rest of the library, those that mix well with
// the last track first within each group. It keeps the radio working
// while the library is being analysed.
func (db *DB) radioFallback(ctx context.Context, req RadioRequest, artistID int64, exclJSON string, mix func(Track) bool) ([]RadioTrack, error) {
	base := trackSelect + `
		AND t.id NOT IN (SELECT track_id FROM hidden_tracks)
		AND t.id NOT IN (SELECT value FROM json_each(?))`
	// Genres of the seed: of the track, or of every track of the artist.
	nearQ := base + ` AND (t.artist_id = ? OR t.genre IN (
			SELECT genre FROM tracks WHERE genre IS NOT NULL AND (id = ? OR artist_id = ?)))
		ORDER BY random() LIMIT 200`
	// Only an artist seed takes the genres of all its tracks (ArtistID is 0
	// for a track seed, TrackID 0 for an artist one).
	near, err := db.trackList(ctx, nearQ, exclJSON, artistID, req.TrackID, req.ArtistID)
	if err != nil {
		return nil, err
	}
	rest, err := db.trackList(ctx, base+` ORDER BY random() LIMIT 200`, exclJSON)
	if err != nil {
		return nil, err
	}
	var out []RadioTrack
	for _, group := range [][]Track{near, rest} {
		sort.SliceStable(group, func(a, b int) bool { return mix(group[a]) && !mix(group[b]) })
		for _, t := range group {
			out = append(out, RadioTrack{Track: t})
		}
	}
	return out, nil
}

// mixFilter returns a test for the tracks that mix well with trackID:
// neighbouring key on the Camelot wheel and bpm within ±6 %, as
// CompatibleTracks. Always false if trackID is not analysed.
func (db *DB) mixFilter(ctx context.Context, trackID int64) (func(Track) bool, error) {
	never := func(Track) bool { return false }
	var bpm sql.NullFloat64
	var camelot sql.NullString
	err := db.r.QueryRowContext(ctx,
		`SELECT bpm, camelot FROM track_analysis WHERE track_id = ? AND error IS NULL`, trackID).Scan(&bpm, &camelot)
	if err == sql.ErrNoRows {
		return never, nil
	} else if err != nil {
		return nil, err
	}
	codes := camelotNeighbours(camelot.String)
	if !bpm.Valid || len(codes) == 0 {
		return never, nil
	}
	return func(t Track) bool {
		if t.BPM == nil || t.Camelot == nil || *t.BPM < bpm.Float64*0.94 || *t.BPM > bpm.Float64*1.06 {
			return false
		}
		for _, c := range codes {
			if *t.Camelot == c {
				return true
			}
		}
		return false
	}, nil
}

// artistEmbeddings returns the embeddings of the present tracks of an artist.
func (db *DB) artistEmbeddings(ctx context.Context, artistID int64) ([][]float32, error) {
	rows, err := db.r.QueryContext(ctx,
		`SELECT id FROM tracks WHERE artist_id = ? AND missing_since IS NULL`, artistID)
	if err != nil {
		return nil, err
	}
	var ids []int64
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			rows.Close()
			return nil, err
		}
		ids = append(ids, id)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}
	var out [][]float32
	for _, id := range ids { // vec0 is searched by primary key one at a time
		var blob []byte
		err := db.r.QueryRowContext(ctx, `SELECT embedding FROM track_embeddings WHERE track_id = ?`, id).Scan(&blob)
		if err == sql.ErrNoRows {
			continue
		} else if err != nil {
			return nil, err
		}
		out = append(out, decodeEmbedding(blob))
	}
	return out, nil
}

// pickDiverse reorders cands in place so that its first n tracks (the
// returned count, at most limit) follow the diversity rules: at most
// radioPerAlbum per album and radioPerArtist per artist, never the same
// artist twice in a row (prevArtist is the one played last). With relax,
// the rules loosen step by step when cands cannot fill the batch.
func pickDiverse(cands []RadioTrack, limit int, prevArtist int64, relax bool) int {
	type rule struct {
		album, artist int
		consecutive   bool
	}
	rules := []rule{{radioPerAlbum, radioPerArtist, false}}
	if relax {
		rules = append(rules, rule{2 * radioPerAlbum, radioPerArtist + 1, false},
			rule{math.MaxInt, math.MaxInt, false}, rule{math.MaxInt, math.MaxInt, true})
	}
	seen := map[int64]bool{}
	n := 0
	// Duplicates (a track found twice) go to the end, never picked.
	for i := range cands {
		if seen[cands[i].ID] {
			continue
		}
		seen[cands[i].ID] = true
		cands[i], cands[n] = cands[n], cands[i]
		n++
	}
	unique := n
	albums, artists := map[int64]int{}, map[int64]int{}
	picked, last := 0, prevArtist
	for _, r := range rules {
		for progress := true; progress && picked < limit; {
			progress = false
			for i := picked; i < unique && picked < limit; i++ {
				t := cands[i]
				if albums[t.AlbumID] >= r.album || artists[t.ArtistID] >= r.artist ||
					(!r.consecutive && t.ArtistID == last) {
					continue
				}
				// Keep the score order of the remaining candidates.
				copy(cands[picked+1:i+1], cands[picked:i])
				cands[picked] = t
				albums[t.AlbumID]++
				artists[t.ArtistID]++
				last = t.ArtistID
				picked++
				progress = true
				break // start again from the best remaining candidate
			}
		}
	}
	return picked
}

func decodeEmbedding(b []byte) []float32 {
	v := make([]float32, len(b)/4)
	for i := range v {
		v[i] = math.Float32frombits(binary.LittleEndian.Uint32(b[4*i:]))
	}
	return v
}

// meanDirection returns the mean of the unit vectors of vecs: each one
// weighs the same whatever its norm (the search uses cosine distance).
// nil when there is no direction to search (no vectors, or they cancel).
func meanDirection(vecs [][]float32) []float32 {
	if len(vecs) == 0 {
		return nil
	}
	out := make([]float32, len(vecs[0]))
	for _, v := range vecs {
		var norm float64
		for _, x := range v {
			norm += float64(x) * float64(x)
		}
		if norm == 0 {
			continue
		}
		inv := 1 / math.Sqrt(norm)
		for i, x := range v {
			out[i] += float32(float64(x) * inv)
		}
	}
	for _, x := range out {
		if x != 0 {
			return out
		}
	}
	return nil
}
