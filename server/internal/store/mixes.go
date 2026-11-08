package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"hash/fnv"
	"math"
	"math/rand/v2"
	"sort"
	"strings"
	"time"
)

// Mixes of the day. Each night the tracks really listened lately (not
// skipped, at least 30 s) are grouped by sound (k-means on their
// embeddings); each group becomes a mix of some of its own tracks and of
// neighbours seldom or never played, which is where a mix gets
// interesting. The mixes stay the same for the whole day.
const (
	mixHistoryDays = 28
	mixMinListenMs = 30_000
	mixMinSeeds    = 8  // fewer listened tracks: no mixes yet
	mixSeedsPerMix = 12 // about one mix per this many listened tracks
	mixMaxCount    = 6
	mixSize        = 25
	mixFamiliar    = 8 // tracks of the group itself in a mix
	mixWornOut     = 3 // plays in the period above which a neighbour is not "fresh"
	mixKeepDays    = 7
	// A discovery must sound like its group: at most this far below the
	// closest neighbour found, in cosine similarity.
	mixSpread = 0.2
	// Bonus to the similarity of a track never played.
	mixNeverBonus = 0.05
)

// Mix is one mix of the day, with its tracks in play order.
type Mix struct {
	Day         string   `json:"day"`
	Position    int      `json:"position"` // 1, 2…
	Name        string   `json:"name"`     // mix_01
	Description string   `json:"description"`
	Artists     []string `json:"artists"`   // the most present, at most 3
	CoverIDs    []int64  `json:"cover_ids"` // up to 4 album covers
	TrackCount  int      `json:"track_count"`
	DurationMs  int64    `json:"duration_ms"`
	Tracks      []Track  `json:"tracks,omitempty"`
}

func mixName(position int) string { return fmt.Sprintf("mix_%02d", position) }

// mixDay is the day a mix belongs to, in the server's time zone.
func mixDay(t time.Time) string { return t.Format("2006-01-02") }

// DailyMixes returns the mixes of the latest day computed (today's once
// the night job ran), without their tracks unless withTracks. Tracks gone
// from the library or archived since are left out.
func (db *DB) DailyMixes(ctx context.Context, withTracks bool) ([]Mix, error) {
	rows, err := db.r.QueryContext(ctx, `SELECT day, position, description, track_ids FROM daily_mixes
		WHERE day = (SELECT MAX(day) FROM daily_mixes) ORDER BY position`)
	if err != nil {
		return nil, err
	}
	type row struct {
		m   Mix
		ids string
	}
	var raw []row
	for rows.Next() {
		var r row
		if err := rows.Scan(&r.m.Day, &r.m.Position, &r.m.Description, &r.ids); err != nil {
			rows.Close()
			return nil, err
		}
		raw = append(raw, r)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}
	out := []Mix{}
	for _, r := range raw {
		tracks, err := db.tracksInOrder(ctx, r.ids)
		if err != nil {
			return nil, err
		}
		if len(tracks) == 0 {
			continue
		}
		m := r.m
		m.Name = mixName(m.Position)
		m.TrackCount = len(tracks)
		artists := map[string]int{}
		seenCover := map[int64]bool{}
		m.CoverIDs = []int64{}
		for _, t := range tracks {
			m.DurationMs += t.DurationMs
			artists[t.Artist]++
			if t.CoverID != nil && !seenCover[*t.CoverID] && len(m.CoverIDs) < 4 {
				seenCover[*t.CoverID] = true
				m.CoverIDs = append(m.CoverIDs, *t.CoverID)
			}
		}
		m.Artists = topKeys(artists, 3)
		if withTracks {
			m.Tracks = tracks
		}
		out = append(out, m)
	}
	return out, nil
}

// DailyMix returns one mix of the latest day with its tracks.
func (db *DB) DailyMix(ctx context.Context, position int) (Mix, error) {
	mixes, err := db.DailyMixes(ctx, true)
	if err != nil {
		return Mix{}, err
	}
	for _, m := range mixes {
		if m.Position == position {
			return m, nil
		}
	}
	return Mix{}, ErrNotFound
}

// tracksInOrder resolves a JSON array of track ids, keeping its order and
// leaving out missing and archived tracks.
func (db *DB) tracksInOrder(ctx context.Context, idsJSON string) ([]Track, error) {
	q := strings.Replace(trackSelect, "/*extra*/", ", j.key", 1)
	q = strings.Replace(q, "FROM tracks t", "FROM json_each(?) j JOIN tracks t ON t.id = j.value", 1) +
		` AND t.id NOT IN (SELECT track_id FROM hidden_tracks) ORDER BY j.key`
	rows, err := db.r.QueryContext(ctx, q, idsJSON)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Track{}
	for rows.Next() {
		var key int
		t, err := scanTrack(rows, &key)
		if err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

// HasMixesFor tells whether the mixes of day t were computed.
func (db *DB) HasMixesFor(ctx context.Context, t time.Time) (bool, error) {
	var n int
	err := db.r.QueryRowContext(ctx, `SELECT COUNT(*) FROM daily_mixes WHERE day = ?`, mixDay(t)).Scan(&n)
	return n > 0, err
}

type mixSeed struct {
	id     int64
	weight float64 // listening time
	vec    []float32
}

// ComputeDailyMixes builds the mixes of the day of now from the listening
// history and stores them in place of that day's (none when the history is
// too short: the previous day's stay until there are). It returns how many
// it made. The result only depends on the data and the day, so computing
// twice the same day gives the same mixes.
func (db *DB) ComputeDailyMixes(ctx context.Context, now time.Time) (int, error) {
	from := now.AddDate(0, 0, -mixHistoryDays).UnixMilli()
	rows, err := db.r.QueryContext(ctx, `
		SELECT p.track_id, SUM(p.listened_ms), (SELECT embedding FROM track_embeddings WHERE track_id = p.track_id)
		FROM plays p JOIN tracks t ON t.id = p.track_id
		WHERE p.started_at >= ? AND p.skipped = 0 AND p.listened_ms >= ? AND t.missing_since IS NULL
		  AND p.track_id NOT IN (SELECT track_id FROM hidden_tracks)
		GROUP BY p.track_id ORDER BY p.track_id`, from, mixMinListenMs)
	if err != nil {
		return 0, err
	}
	var seeds []mixSeed
	for rows.Next() {
		var s mixSeed
		var ms int64
		var blob []byte
		if err := rows.Scan(&s.id, &ms, &blob); err != nil {
			rows.Close()
			return 0, err
		}
		if blob == nil {
			continue // not analysed with the ML models yet
		}
		s.weight, s.vec = float64(ms), unitVec(decodeEmbedding(blob))
		if s.vec != nil {
			seeds = append(seeds, s)
		}
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return 0, err
	}
	if len(seeds) < mixMinSeeds {
		return 0, nil
	}

	// How often each track was played lately: the worn-out ones are not
	// offered as discoveries.
	plays := map[int64]int{}
	prow, err := db.r.QueryContext(ctx, `SELECT track_id, COUNT(*) FROM plays WHERE started_at >= ? GROUP BY track_id`, from)
	if err != nil {
		return 0, err
	}
	for prow.Next() {
		var id int64
		var n int
		if err := prow.Scan(&id, &n); err != nil {
			prow.Close()
			return 0, err
		}
		plays[id] = n
	}
	prow.Close()

	day := mixDay(now)
	h := fnv.New64a()
	h.Write([]byte(day))
	rng := rand.New(rand.NewPCG(h.Sum64(), 0x7f4a7c15))
	k := min(mixMaxCount, max(1, int(math.Round(float64(len(seeds))/mixSeedsPerMix))))
	groups := kmeans(seeds, k, rng)

	type built struct {
		description string
		ids         []int64
	}
	var mixes []built
	used := map[int64]bool{} // a discovery goes in one mix only
	for _, g := range groups {
		// Familiar: the most listened tracks of the group.
		sort.SliceStable(g.members, func(a, b int) bool { return g.members[a].weight > g.members[b].weight })
		var familiar []int64
		inMix := map[int64]bool{}
		for _, s := range g.members[:min(mixFamiliar, len(g.members))] {
			familiar = append(familiar, s.id)
			inMix[s.id] = true
		}
		// Fresh: the neighbours of the group's centre, seldom or never
		// played; the tracks listened lately (every group's) are not new.
		var excl []int64
		for id, n := range plays {
			if n >= mixWornOut {
				excl = append(excl, id)
			}
		}
		for id := range used {
			excl = append(excl, id)
		}
		for _, s := range seeds {
			excl = append(excl, s.id)
		}
		exclJSON, _ := json.Marshal(excl)
		cands, err := db.radioNeighbours(ctx, g.centre, mixSize, len(excl), string(exclJSON), func(Track) bool { return false })
		if err != nil {
			return 0, err
		}
		// Close to the group only; never played a little ahead.
		if len(cands) > 0 {
			floor := *cands[0].Similarity - mixSpread
			kept := cands[:0]
			for _, c := range cands {
				if *c.Similarity >= floor {
					kept = append(kept, c)
				}
			}
			cands = kept
		}
		score := func(c RadioTrack) float64 {
			if plays[c.ID] == 0 {
				return *c.Similarity + mixNeverBonus
			}
			return *c.Similarity
		}
		sort.SliceStable(cands, func(a, b int) bool { return score(cands[a]) > score(cands[b]) })
		n := pickDiverse(cands, mixSize-len(familiar), 0, true)
		var fresh []int64
		for _, c := range cands[:n] {
			if !inMix[c.ID] {
				fresh = append(fresh, c.ID)
				used[c.ID] = true
			}
		}
		// Start on something familiar, then two discoveries for one known.
		var ids []int64
		for i, j := 0, 0; i < len(familiar) || j < len(fresh); {
			if i < len(familiar) {
				ids = append(ids, familiar[i])
				i++
			}
			for range 2 {
				if j < len(fresh) {
					ids = append(ids, fresh[j])
					j++
				}
			}
		}
		if ids, err = db.dropSameSong(ctx, ids); err != nil {
			return 0, err
		}
		desc, err := db.mixDescription(ctx, ids)
		if err != nil {
			return 0, err
		}
		mixes = append(mixes, built{desc, ids})
	}

	tx, err := db.w.BeginTx(ctx, nil)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback() //nolint:errcheck // no-op after Commit
	if _, err := tx.ExecContext(ctx, `DELETE FROM daily_mixes WHERE day = ? OR day < ?`,
		day, mixDay(now.AddDate(0, 0, -mixKeepDays))); err != nil {
		return 0, err
	}
	for i, m := range mixes {
		ids, _ := json.Marshal(m.ids)
		if _, err := tx.ExecContext(ctx, `INSERT INTO daily_mixes (day, position, description, track_ids, created_at)
			VALUES (?, ?, ?, ?, ?)`, day, i+1, m.description, string(ids), now.Unix()); err != nil {
			return 0, err
		}
	}
	return len(mixes), tx.Commit()
}

// dropSameSong keeps the first of the tracks that are the same song by
// the same artist (a library often holds an album and its deluxe edition).
func (db *DB) dropSameSong(ctx context.Context, ids []int64) ([]int64, error) {
	idsJSON, _ := json.Marshal(ids)
	rows, err := db.r.QueryContext(ctx, `SELECT id, artist_id, title FROM tracks
		WHERE id IN (SELECT value FROM json_each(?))`, string(idsJSON))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	key := map[int64]string{}
	for rows.Next() {
		var id, artist int64
		var title string
		if err := rows.Scan(&id, &artist, &title); err != nil {
			return nil, err
		}
		key[id] = fmt.Sprintf("%d|%s", artist, strings.ToLower(strings.Join(strings.Fields(title), " ")))
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	seen := map[string]bool{}
	out := ids[:0]
	for _, id := range ids {
		if k, ok := key[id]; ok && !seen[k] {
			seen[k] = true
			out = append(out, id)
		}
	}
	return out, nil
}

// mixDescription names a mix after its dominant style and mood:
// "dance-pop · festif" (the style the analysis heard, else the genre).
func (db *DB) mixDescription(ctx context.Context, ids []int64) (string, error) {
	idsJSON, _ := json.Marshal(ids)
	rows, err := db.r.QueryContext(ctx, `SELECT genres, mood FROM track_analysis
		WHERE track_id IN (SELECT value FROM json_each(?)) AND error IS NULL`, string(idsJSON))
	if err != nil {
		return "", err
	}
	defer rows.Close()
	styles, moods := map[string]int{}, map[string]int{}
	for rows.Next() {
		var genres, mood sql.NullString
		if err := rows.Scan(&genres, &mood); err != nil {
			return "", err
		}
		var gs []GenreShare
		if genres.Valid && json.Unmarshal([]byte(genres.String), &gs) == nil && len(gs) > 0 {
			styles[strings.ToLower(gs[len(gs)-1].Name)]++
		}
		if mood.Valid && mood.String != "" {
			moods[strings.TrimSpace(strings.SplitN(mood.String, "·", 2)[0])]++
		}
	}
	if err := rows.Err(); err != nil {
		return "", err
	}
	parts := append(topKeys(styles, 1), topKeys(moods, 1)...)
	return strings.Join(parts, " · "), nil
}

type mixGroup struct {
	centre  []float32
	members []mixSeed
	weight  float64
}

// kmeans groups the seeds by cosine similarity (k-means++ start, weighted
// by listening time), largest group first; empty groups are dropped.
func kmeans(seeds []mixSeed, k int, rng *rand.Rand) []mixGroup {
	k = min(k, len(seeds))
	centres := [][]float32{seeds[rng.IntN(len(seeds))].vec}
	for len(centres) < k {
		// Next centre: far from the chosen ones, with probability ∝ d².
		d := make([]float64, len(seeds))
		var total float64
		for i, s := range seeds {
			best := math.Inf(1)
			for _, c := range centres {
				best = math.Min(best, 1-dot(s.vec, c))
			}
			d[i] = best * best * s.weight
			total += d[i]
		}
		if total == 0 {
			break
		}
		r := rng.Float64() * total
		i := 0
		for ; i < len(d)-1 && r > d[i]; i++ {
			r -= d[i]
		}
		centres = append(centres, seeds[i].vec)
	}
	assign := make([]int, len(seeds))
	for iter := 0; iter < 25; iter++ {
		changed := iter == 0
		for i, s := range seeds {
			best, bestSim := 0, math.Inf(-1)
			for j, c := range centres {
				if sim := dot(s.vec, c); sim > bestSim {
					best, bestSim = j, sim
				}
			}
			if assign[i] != best {
				assign[i], changed = best, true
			}
		}
		if !changed {
			break
		}
		for j := range centres {
			sum := make([]float32, len(seeds[0].vec))
			for i, s := range seeds {
				if assign[i] != j {
					continue
				}
				for x, v := range s.vec {
					sum[x] += v * float32(s.weight)
				}
			}
			if u := unitVec(sum); u != nil {
				centres[j] = u
			}
		}
	}
	groups := make([]mixGroup, len(centres))
	for j := range groups {
		groups[j].centre = centres[j]
	}
	for i, s := range seeds {
		g := &groups[assign[i]]
		g.members = append(g.members, s)
		g.weight += s.weight
	}
	out := groups[:0]
	for _, g := range groups {
		if len(g.members) > 0 {
			out = append(out, g)
		}
	}
	sort.SliceStable(out, func(a, b int) bool { return out[a].weight > out[b].weight })
	return out
}

func dot(a, b []float32) float64 {
	var s float64
	for i := range a {
		s += float64(a[i]) * float64(b[i])
	}
	return s
}

// unitVec returns v scaled to length 1, nil for a zero vector.
func unitVec(v []float32) []float32 {
	var n float64
	for _, x := range v {
		n += float64(x) * float64(x)
	}
	if n == 0 {
		return nil
	}
	inv := float32(1 / math.Sqrt(n))
	out := make([]float32, len(v))
	for i, x := range v {
		out[i] = x * inv
	}
	return out
}

// topKeys returns the n most counted keys, ties by name.
func topKeys(m map[string]int, n int) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		if k != "" {
			keys = append(keys, k)
		}
	}
	sort.Slice(keys, func(a, b int) bool {
		return m[keys[a]] > m[keys[b]] || m[keys[a]] == m[keys[b]] && keys[a] < keys[b]
	})
	return keys[:min(n, len(keys))]
}
