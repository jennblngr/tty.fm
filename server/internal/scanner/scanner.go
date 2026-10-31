// Package scanner indexes the music directory into the store: full or
// incremental (size + mtime) scans, move detection, covers, fsnotify watch.
package scanner

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"log/slog"
	"math"
	"os"
	"path"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"go.senan.xyz/taglib"

	"selfstream/internal/covers"
	"selfstream/internal/store"
)

var audioExt = map[string]bool{
	".mp3": true, ".flac": true, ".m4a": true, ".mp4": true, ".aac": true, ".alac": true,
	".ogg": true, ".oga": true, ".opus": true, ".wav": true, ".aif": true, ".aiff": true,
	".wma": true, ".ape": true, ".wv": true, ".mpc": true,
}

// coverNames are folder images by priority (lower index wins).
var coverNames = []string{"cover", "folder", "front", "album", "albumart"}

var imageExt = map[string]bool{".jpg": true, ".jpeg": true, ".png": true, ".webp": true}

const batchSize = 250
const lastScanKey = "last_scan_at"

// Stats summarises one scan.
type Stats struct {
	Seen     int           `json:"seen"`
	Added    int           `json:"added"`
	Updated  int           `json:"updated"`
	Moved    int           `json:"moved"`
	Missing  int           `json:"missing"`
	Errors   int           `json:"errors"`
	Duration time.Duration `json:"duration_ms"`
}

// Status is what the admin endpoint reports.
type Status struct {
	Running  bool      `json:"running"`
	Progress int       `json:"progress"` // files processed in current scan
	Total    int       `json:"total"`    // files to process in current scan
	Last     *Stats    `json:"last,omitempty"`
	LastAt   time.Time `json:"last_at,omitempty"`
	LastErr  string    `json:"last_error,omitempty"`
}

type Scanner struct {
	db      *store.DB
	root    string
	covers  *covers.Cache
	workers int
	log     *slog.Logger
	// onChange is called after a scan that changed the library.
	onChange func()

	mu       sync.Mutex // one scan at a time
	running  atomic.Bool
	progress atomic.Int64
	total    atomic.Int64
	statusMu sync.Mutex
	last     *Stats
	lastAt   time.Time
	lastErr  string
}

// SetOnChange registers a callback run after a scan that changed the library.
func (s *Scanner) SetOnChange(f func()) { s.onChange = f }

func New(db *store.DB, root string, c *covers.Cache, workers int, log *slog.Logger) *Scanner {
	return &Scanner{db: db, root: root, covers: c, workers: max(1, workers), log: log}
}

func (s *Scanner) Status() Status {
	s.statusMu.Lock()
	defer s.statusMu.Unlock()
	return Status{
		Running:  s.running.Load(),
		Progress: int(s.progress.Load()),
		Total:    int(s.total.Load()),
		Last:     s.last,
		LastAt:   s.lastAt,
		LastErr:  s.lastErr,
	}
}

type walkedFile struct {
	rel   string
	size  int64
	mtime int64
}

type walkResult struct {
	files     []walkedFile
	coverFile map[string]string // dir (relative) → best cover image (relative)
	coverTime map[string]int64  // dir → mtime of that image (unix nanos)
}

func (s *Scanner) walk(ctx context.Context) (*walkResult, error) {
	res := &walkResult{coverFile: map[string]string{}, coverTime: map[string]int64{}}
	coverRank := map[string]int{}
	err := filepath.WalkDir(s.root, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			if p == s.root {
				return err
			}
			s.log.Warn("scan: cannot read", "path", p, "err", err)
			return nil
		}
		if ctx.Err() != nil {
			return ctx.Err()
		}
		name := d.Name()
		if d.IsDir() {
			if p != s.root && (strings.HasPrefix(name, ".") || name == "@eaDir" || name == "#recycle") {
				return filepath.SkipDir // hidden dirs, Synology/UGOS thumbnails, recycle bin
			}
			return nil
		}
		if strings.HasPrefix(name, ".") || !d.Type().IsRegular() {
			return nil
		}
		ext := strings.ToLower(filepath.Ext(name))
		rel, err := filepath.Rel(s.root, p)
		if err != nil {
			return err
		}
		rel = filepath.ToSlash(rel)
		if audioExt[ext] {
			info, err := d.Info()
			if err != nil {
				return nil
			}
			res.files = append(res.files, walkedFile{rel: rel, size: info.Size(), mtime: info.ModTime().UnixNano()})
			return nil
		}
		if imageExt[ext] {
			base := strings.ToLower(strings.TrimSuffix(name, filepath.Ext(name)))
			for rank, cn := range coverNames {
				if base != cn {
					continue
				}
				dir := path.Dir(rel)
				if old, ok := coverRank[dir]; ok && old <= rank {
					break
				}
				info, err := d.Info()
				if err != nil {
					break
				}
				coverRank[dir] = rank
				res.coverFile[dir] = rel
				res.coverTime[dir] = info.ModTime().UnixNano()
				break
			}
		}
		return nil
	})
	return res, err
}

// Scan indexes the library. A full scan re-reads every file's tags; an
// incremental one only reads new or changed files.
func (s *Scanner) Scan(ctx context.Context, full bool) (Stats, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.running.Store(true)
	s.progress.Store(0)
	s.total.Store(0)
	defer s.running.Store(false)

	start := time.Now()
	st, err := s.scan(ctx, full)
	st.Duration = time.Since(start)

	s.statusMu.Lock()
	s.lastAt = time.Now()
	s.last = &st
	s.lastErr = ""
	if err != nil {
		s.lastErr = err.Error()
	}
	s.statusMu.Unlock()
	if err != nil {
		s.log.Error("scan failed", "err", err, "duration", st.Duration)
	} else {
		s.log.Info("scan done", "full", full, "seen", st.Seen, "added", st.Added, "updated", st.Updated,
			"moved", st.Moved, "missing", st.Missing, "errors", st.Errors, "duration", st.Duration.Round(time.Millisecond))
		if s.onChange != nil && st.Added+st.Updated+st.Moved+st.Missing > 0 {
			s.onChange()
		}
	}
	return st, err
}

func (s *Scanner) scan(ctx context.Context, full bool) (Stats, error) {
	var st Stats
	lastScanStr, err := s.db.Meta(ctx, lastScanKey)
	if err != nil {
		return st, err
	}
	lastScan, _ := strconv.ParseInt(lastScanStr, 10, 64)
	scanStart := time.Now().UnixNano()

	walked, err := s.walk(ctx)
	if err != nil {
		return st, fmt.Errorf("walk %s: %w", s.root, err)
	}
	st.Seen = len(walked.files)
	known, err := s.db.KnownFiles(ctx)
	if err != nil {
		return st, err
	}

	present := 0
	for _, k := range known {
		if !k.Missing {
			present++
		}
	}
	// An empty walk over a non-empty library almost always means the volume
	// is not mounted: never mark the whole library missing because of that.
	if len(walked.files) == 0 && present > 0 {
		return st, errors.New("music directory is empty but the library is not; is the volume mounted? refusing to mark tracks missing")
	}

	onDisk := make(map[string]bool, len(walked.files))
	var toRead []walkedFile
	for _, f := range walked.files {
		onDisk[f.rel] = true
		k, ok := known[f.rel]
		if full || !ok || k.Missing || k.Size != f.size || k.Mtime != f.mtime {
			toRead = append(toRead, f)
		}
	}
	// Tracks whose file is gone: candidates for move detection, then missing.
	gone := map[int64]store.KnownFile{}
	for p, k := range known {
		if !onDisk[p] && !k.Missing {
			gone[k.ID] = k
		}
	}
	// Albums in directories whose cover image changed since the last scan.
	var coverDirs []string
	for dir, mt := range walked.coverTime {
		if full || mt > lastScan {
			coverDirs = append(coverDirs, dir)
		}
	}
	s.total.Store(int64(len(toRead)))

	results := s.readAll(ctx, toRead)
	batch := make([]*store.TrackFile, 0, batchSize)
	flush := func(final bool) error {
		err := s.db.WriteLibrary(ctx, func(w *store.LibWriter) error {
			for _, f := range batch {
				reuse := int64(0)
				k, isKnown := known[f.Path]
				if isKnown {
					reuse = k.ID
				} else if id := matchMoved(gone, f); id != 0 {
					reuse = id
					delete(gone, id)
					st.Moved++
				}
				if _, err := w.UpsertTrack(f, reuse); err != nil {
					return err
				}
				switch {
				case !isKnown && reuse == 0:
					st.Added++
				case isKnown:
					st.Updated++
				}
			}
			if final {
				ids := make([]int64, 0, len(gone))
				for id := range gone {
					ids = append(ids, id)
				}
				if err := w.MarkMissing(ids); err != nil {
					return err
				}
				st.Missing = len(ids)
				for _, dir := range coverDirs {
					albums, err := w.AlbumsInDir(dir)
					if err != nil {
						return err
					}
					for _, a := range albums {
						w.Touched[a] = true
					}
				}
			}
			if err := s.resolveCovers(w, walked); err != nil {
				return err
			}
			return w.Finalize()
		})
		batch = batch[:0]
		return err
	}

	for r := range results {
		s.progress.Add(1)
		if r.err != nil {
			st.Errors++
			s.log.Warn("scan: cannot read tags", "path", r.path, "err", r.err)
			continue
		}
		batch = append(batch, r.file)
		if len(batch) == batchSize {
			if err := flush(false); err != nil {
				return st, err
			}
		}
	}
	if err := ctx.Err(); err != nil {
		return st, err
	}
	if err := flush(true); err != nil {
		return st, err
	}
	return st, s.db.SetMeta(ctx, lastScanKey, strconv.FormatInt(scanStart, 10))
}

// matchMoved finds a vanished track that is probably the same file under a
// new path: same size, same duration (±1 s) and same title.
func matchMoved(gone map[int64]store.KnownFile, f *store.TrackFile) int64 {
	for id, k := range gone {
		if k.Size == f.Size && math.Abs(float64(k.DurationMs-f.DurationMs)) < 1000 &&
			store.MatchKey(k.Title) == store.MatchKey(titleOrBase(f)) {
			return id
		}
	}
	return 0
}

func titleOrBase(f *store.TrackFile) string {
	if strings.TrimSpace(f.Title) != "" {
		return f.Title
	}
	b := path.Base(f.Path)
	return strings.TrimSuffix(b, path.Ext(b))
}

// resolveCovers picks a cover for every touched album: folder image first,
// otherwise the first track's embedded picture.
func (s *Scanner) resolveCovers(w *store.LibWriter, walked *walkResult) error {
	for albumID := range w.Touched {
		dirs, first, err := w.AlbumDirs(albumID)
		if err != nil {
			return err
		}
		if first == "" {
			continue // album has no present track left
		}
		var img []byte
		source := ""
		for _, d := range dirs {
			if cf, ok := walked.coverFile[d]; ok {
				if b, err := os.ReadFile(filepath.Join(s.root, filepath.FromSlash(cf))); err == nil {
					img, source = b, "file"
					break
				}
			}
		}
		if img == nil {
			if b, err := taglib.ReadImage(filepath.Join(s.root, filepath.FromSlash(first))); err == nil && len(b) > 0 {
				img, source = b, "embedded"
			}
		}
		var coverID int64
		if img != nil {
			hash, err := s.covers.Put(img)
			if err != nil {
				s.log.Warn("scan: bad cover image", "album", albumID, "err", err)
			} else if coverID, err = w.CoverID(hash, source); err != nil {
				return err
			}
		}
		cur, err := w.AlbumCover(albumID)
		if err != nil {
			return err
		}
		if cur != coverID {
			if err := w.SetAlbumCover(albumID, coverID); err != nil {
				return err
			}
		}
	}
	return nil
}

type readResult struct {
	path string
	file *store.TrackFile
	err  error
}

// readAll reads tags with a worker pool and streams results.
func (s *Scanner) readAll(ctx context.Context, files []walkedFile) <-chan readResult {
	jobs := make(chan walkedFile)
	out := make(chan readResult, s.workers*2)
	var wg sync.WaitGroup
	for range s.workers {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for f := range jobs {
				tf, err := readFile(filepath.Join(s.root, filepath.FromSlash(f.rel)), f)
				out <- readResult{path: f.rel, file: tf, err: err}
			}
		}()
	}
	go func() {
		defer close(jobs)
		for _, f := range files {
			select {
			case jobs <- f:
			case <-ctx.Done():
				return
			}
		}
	}()
	go func() {
		wg.Wait()
		close(out)
	}()
	return out
}
