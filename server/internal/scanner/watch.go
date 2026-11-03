package scanner

import (
	"context"
	"io/fs"
	"path/filepath"
	"strings"
	"time"

	"github.com/fsnotify/fsnotify"
)

// Watch rescans incrementally after filesystem changes settle for debounce.
// It blocks until ctx is cancelled. Note: inotify does not see changes made
// over SMB/NFS from another machine on some NAS setups; the periodic scan
// and the manual trigger cover that case.
func (s *Scanner) Watch(ctx context.Context, debounce time.Duration) error {
	w, err := fsnotify.NewWatcher()
	if err != nil {
		return err
	}
	defer w.Close()

	addTree := func(root string) {
		// The callback skips unreadable entries and never fails the walk.
		_ = filepath.WalkDir(root, func(p string, d fs.DirEntry, err error) error {
			if err != nil || !d.IsDir() {
				return nil
			}
			if p != s.root && (strings.HasPrefix(d.Name(), ".") || d.Name() == "@eaDir" || d.Name() == "#recycle") {
				return filepath.SkipDir
			}
			if err := w.Add(p); err != nil {
				s.log.Warn("watch: cannot add", "path", p, "err", err)
			}
			return nil
		})
	}
	addTree(s.root)
	s.log.Info("watching library", "root", s.root)

	timer := time.NewTimer(debounce)
	timer.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case ev, ok := <-w.Events:
			if !ok {
				return nil
			}
			if ev.Has(fsnotify.Create) {
				addTree(ev.Name) // no-op for files; picks up new sub-directories
			}
			timer.Reset(debounce)
		case err, ok := <-w.Errors:
			if !ok {
				return nil
			}
			s.log.Warn("watch error", "err", err)
		case <-timer.C:
			s.Scan(ctx, false)
		}
	}
}
