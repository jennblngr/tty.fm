package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"sync"
	"syscall"
	"time"
	_ "time/tzdata" // local time for stats even in a minimal image (TZ env)

	"ttyfm/internal/api"
	"ttyfm/internal/app"
	"ttyfm/internal/auth"
	"ttyfm/internal/config"
	"ttyfm/internal/covers"
	"ttyfm/internal/hub"
	"ttyfm/internal/lyrics"
	"ttyfm/internal/scanner"
	"ttyfm/internal/store"
	"ttyfm/internal/stream"
)

// Tracks missing for longer than this are deleted for good.
const purgeAfter = 30 * 24 * time.Hour

func main() {
	if len(os.Args) > 1 && os.Args[1] == "healthcheck" {
		os.Exit(healthcheck())
	}
	if err := run(); err != nil {
		slog.Error("fatal", "err", err)
		os.Exit(1)
	}
}

func run() error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	log := slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: cfg.LogLevel}))
	slog.SetDefault(log)
	log.Info("starting", "app", app.Title, "version", app.Version, "music", cfg.MusicDir, "data", cfg.DataDir)

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	if err := os.MkdirAll(cfg.DataDir, 0o755); err != nil {
		return err
	}
	db, err := store.Open(cfg.DBPath())
	if err != nil {
		return err
	}
	defer db.Close()

	authSvc := auth.NewService(db, log)
	if err := authSvc.EnsureUser(ctx, cfg.AdminUser, cfg.AdminPassword); err != nil {
		return err
	}
	coverCache, err := covers.New(cfg.CoverDir())
	if err != nil {
		return err
	}
	streamer, err := stream.New(cfg.MusicDir, cfg.FFmpeg, cfg.TranscodeDir(), cfg.TranscodeMB, log)
	if err != nil {
		return err
	}
	sc := scanner.New(db, cfg.MusicDir, coverCache, cfg.ScanWorkers, log)
	liveHub := hub.New(log)
	sc.SetOnChange(func() { liveHub.Changed("library", 0) })

	var bg sync.WaitGroup
	startScan := func(full bool) {
		bg.Add(1)
		go func() {
			defer bg.Done()
			sc.Scan(ctx, full)
		}()
	}

	srv := &api.Server{DB: db, Auth: authSvc, Scanner: sc, Covers: coverCache, Streamer: streamer, Log: log, Hub: liveHub,
		Lyrics: lyrics.New(cfg.MusicDir),
		ScanFn: startScan}
	httpSrv := &http.Server{Addr: cfg.Listen, Handler: srv.Handler(), ReadHeaderTimeout: 10 * time.Second}

	if cfg.ScanOnStart {
		startScan(false)
	}
	if cfg.Watch {
		bg.Add(1)
		go func() {
			defer bg.Done()
			if err := sc.Watch(ctx, cfg.WatchDebounce); err != nil {
				log.Error("watcher stopped", "err", err)
			}
		}()
	}
	// Periodic safety-net scan (fsnotify misses changes made over SMB on
	// some setups) and purge of long-missing tracks.
	bg.Add(1)
	go func() {
		defer bg.Done()
		t := time.NewTicker(cfg.ScanInterval)
		defer t.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
				sc.Scan(ctx, false)
				if n, err := db.PurgeMissing(ctx, purgeAfter); err != nil {
					log.Error("purge", "err", err)
				} else if n > 0 {
					log.Info("purged missing tracks", "count", n)
				}
			}
		}
	}()

	// Mixes of the day: computed at startup if today's are missing, then
	// each night at 04:00.
	bg.Add(1)
	go func() {
		defer bg.Done()
		mixes := func() {
			n, err := db.ComputeDailyMixes(ctx, time.Now())
			if err != nil {
				log.Error("daily mixes", "err", err)
				return
			}
			log.Info("daily mixes", "count", n)
			liveHub.Changed("library", 0) // the home screen reloads
		}
		if done, err := db.HasMixesFor(ctx, time.Now()); err == nil && !done {
			mixes()
		}
		for {
			t := time.NewTimer(time.Until(nextMixTime(time.Now())))
			select {
			case <-ctx.Done():
				t.Stop()
				return
			case <-t.C:
				mixes()
			}
		}
	}()

	errc := make(chan error, 1)
	go func() { errc <- httpSrv.ListenAndServe() }()
	log.Info("listening", "addr", cfg.Listen)

	select {
	case err := <-errc:
		return err
	case <-ctx.Done():
	}
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := httpSrv.Shutdown(shutdownCtx); err != nil && !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	bg.Wait()
	log.Info("stopped")
	return nil
}

// healthcheck is used by the Docker HEALTHCHECK (the image has no curl).
func healthcheck() int {
	cfg, err := config.Load()
	if err != nil {
		return 1
	}
	addr := cfg.Listen
	if strings.HasPrefix(addr, ":") {
		addr = "127.0.0.1" + addr
	}
	c := http.Client{Timeout: 3 * time.Second}
	resp, err := c.Get("http://" + addr + "/api/" + app.APIVersion + "/health")
	if err != nil {
		return 1
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return 1
	}
	return 0
}

// nextMixTime is the next 04:00 (local time) after now.
func nextMixTime(now time.Time) time.Time {
	y, m, d := now.Date()
	next := time.Date(y, m, d, 4, 0, 0, 0, now.Location())
	if !next.After(now) {
		next = next.AddDate(0, 0, 1)
	}
	return next
}
