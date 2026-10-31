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

	"selfstream/internal/api"
	"selfstream/internal/app"
	"selfstream/internal/auth"
	"selfstream/internal/config"
	"selfstream/internal/covers"
	"selfstream/internal/hub"
	"selfstream/internal/lyrics"
	"selfstream/internal/scanner"
	"selfstream/internal/store"
	"selfstream/internal/stream"
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
	log.Info("starting", "app", app.Name, "version", app.Version, "music", cfg.MusicDir, "data", cfg.DataDir)

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
