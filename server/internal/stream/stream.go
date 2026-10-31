// Package stream serves audio: original files with HTTP Range support, or
// transcoded on the fly by ffmpeg with a size-bounded disk cache.
package stream

import (
	"context"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Format is a transcoding target.
type Format struct {
	Name        string
	ContentType string
	Ext         string
	args        func(bitrate int) []string
}

var Formats = map[string]Format{
	"opus": {
		Name: "opus", ContentType: "audio/ogg", Ext: "opus",
		args: func(br int) []string {
			return []string{"-c:a", "libopus", "-b:a", fmt.Sprintf("%dk", br), "-vbr", "on", "-f", "ogg"}
		},
	},
	"aac": {
		Name: "aac", ContentType: "audio/aac", Ext: "aac",
		args: func(br int) []string {
			return []string{"-c:a", "aac", "-b:a", fmt.Sprintf("%dk", br), "-f", "adts"}
		},
	},
	"mp3": {
		Name: "mp3", ContentType: "audio/mpeg", Ext: "mp3",
		args: func(br int) []string {
			return []string{"-c:a", "libmp3lame", "-b:a", fmt.Sprintf("%dk", br), "-f", "mp3"}
		},
	},
}

var contentTypes = map[string]string{
	"mp3": "audio/mpeg", "flac": "audio/flac", "m4a": "audio/mp4", "mp4": "audio/mp4",
	"aac": "audio/aac", "alac": "audio/mp4", "ogg": "audio/ogg", "oga": "audio/ogg",
	"opus": "audio/ogg", "wav": "audio/wav", "aif": "audio/aiff", "aiff": "audio/aiff",
	"wma": "audio/x-ms-wma", "ape": "audio/x-ape", "wv": "audio/x-wavpack", "mpc": "audio/x-musepack",
}

// ClampBitrate keeps bitrates (kbit/s) within sane bounds per format.
func ClampBitrate(br int) int {
	if br <= 0 {
		return 128
	}
	return min(max(br, 32), 320)
}

type Streamer struct {
	root     string
	ffmpeg   string
	cacheDir string
	maxBytes int64
	log      *slog.Logger

	mu       sync.Mutex
	inflight map[string]bool // cache keys being written
}

func New(root, ffmpeg, cacheDir string, maxMB int64, log *slog.Logger) (*Streamer, error) {
	if err := os.MkdirAll(cacheDir, 0o755); err != nil {
		return nil, err
	}
	// Leftovers from an interrupted run.
	tmps, _ := filepath.Glob(filepath.Join(cacheDir, "*.tmp"))
	for _, t := range tmps {
		os.Remove(t)
	}
	return &Streamer{root: root, ffmpeg: ffmpeg, cacheDir: cacheDir, maxBytes: maxMB << 20,
		log: log, inflight: map[string]bool{}}, nil
}

// ServeOriginal serves the file as-is; http.ServeContent handles Range,
// If-Range and HEAD.
func (s *Streamer) ServeOriginal(w http.ResponseWriter, r *http.Request, relPath, format string) {
	f, err := os.Open(filepath.Join(s.root, filepath.FromSlash(relPath)))
	if err != nil {
		http.Error(w, "file unavailable", http.StatusNotFound)
		return
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil {
		http.Error(w, "file unavailable", http.StatusNotFound)
		return
	}
	if ct, ok := contentTypes[format]; ok {
		w.Header().Set("Content-Type", ct)
	}
	w.Header().Set("Cache-Control", "private, max-age=86400")
	http.ServeContent(w, r, "", info.ModTime(), f)
}

// ServeTranscoded serves a transcoded version. Complete cached versions are
// served with Range support; otherwise ffmpeg output is streamed while being
// written to the cache. offset (seconds) starts mid-track and bypasses the
// cache, for seeking within a stream that is not cached yet.
func (s *Streamer) ServeTranscoded(w http.ResponseWriter, r *http.Request, trackID int64, relPath string,
	mtime int64, f Format, bitrate int, offset float64) {
	key := fmt.Sprintf("%d_%d_%s_%d", trackID, mtime, f.Name, bitrate)
	cached := filepath.Join(s.cacheDir, key+"."+f.Ext)
	w.Header().Set("Content-Type", f.ContentType)

	if offset <= 0 {
		if file, err := os.Open(cached); err == nil {
			defer file.Close()
			info, _ := file.Stat()
			now := time.Now()
			os.Chtimes(cached, now, now) // LRU recency
			w.Header().Set("Cache-Control", "private, max-age=86400")
			http.ServeContent(w, r, "", info.ModTime(), file)
			return
		}
	}

	ctx, cancel := context.WithCancel(r.Context())
	defer cancel()
	args := []string{"-hide_banner", "-loglevel", "error", "-nostdin"}
	if offset > 0 {
		args = append(args, "-ss", strconv.FormatFloat(offset, 'f', 3, 64))
	}
	args = append(args, "-i", filepath.Join(s.root, filepath.FromSlash(relPath)),
		"-map", "0:a:0", "-vn", "-map_metadata", "-1")
	args = append(args, f.args(bitrate)...)
	args = append(args, "pipe:1")
	cmd := exec.CommandContext(ctx, s.ffmpeg, args...)
	var stderr strings.Builder
	cmd.Stderr = &stderr
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		http.Error(w, "transcode failed", http.StatusInternalServerError)
		return
	}
	if err := cmd.Start(); err != nil {
		s.log.Error("ffmpeg start", "err", err)
		http.Error(w, "transcode failed", http.StatusInternalServerError)
		return
	}

	// Tee into the cache unless seeking or another request is already writing it.
	var tmp *os.File
	if offset <= 0 && s.claim(key) {
		defer s.release(key)
		if tmp, err = os.CreateTemp(s.cacheDir, key+"-*.tmp"); err != nil {
			tmp = nil
		}
	}
	var dst io.Writer = w
	if tmp != nil {
		dst = io.MultiWriter(w, tmp)
	}
	w.Header().Set("Accept-Ranges", "none")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(http.StatusOK)

	_, copyErr := io.Copy(dst, stdout)
	waitErr := cmd.Wait()

	if tmp != nil {
		name := tmp.Name()
		closeErr := tmp.Close()
		if copyErr == nil && waitErr == nil && closeErr == nil {
			if err := os.Rename(name, cached); err == nil {
				go s.evict()
			}
		} else {
			os.Remove(name)
		}
	}
	if waitErr != nil && ctx.Err() == nil {
		s.log.Warn("ffmpeg failed", "track", trackID, "err", waitErr, "stderr", strings.TrimSpace(stderr.String()))
	}
}

func (s *Streamer) claim(key string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.inflight[key] {
		return false
	}
	s.inflight[key] = true
	return true
}

func (s *Streamer) release(key string) {
	s.mu.Lock()
	delete(s.inflight, key)
	s.mu.Unlock()
}

// evict deletes least recently used cache files above the size limit.
func (s *Streamer) evict() {
	entries, err := os.ReadDir(s.cacheDir)
	if err != nil {
		return
	}
	type item struct {
		path  string
		size  int64
		mtime time.Time
	}
	var items []item
	var total int64
	for _, e := range entries {
		if e.IsDir() || strings.HasSuffix(e.Name(), ".tmp") {
			continue
		}
		info, err := e.Info()
		if err != nil {
			continue
		}
		items = append(items, item{filepath.Join(s.cacheDir, e.Name()), info.Size(), info.ModTime()})
		total += info.Size()
	}
	if total <= s.maxBytes {
		return
	}
	sort.Slice(items, func(i, j int) bool { return items[i].mtime.Before(items[j].mtime) })
	for _, it := range items {
		if total <= s.maxBytes {
			break
		}
		if os.Remove(it.path) == nil {
			total -= it.size
		}
	}
}
