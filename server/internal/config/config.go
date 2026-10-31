// Package config loads the server configuration from environment variables.
package config

import (
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"

	"selfstream/internal/app"
)

type Config struct {
	Listen        string        // HTTP listen address
	MusicDir      string        // library root (read-only mount)
	DataDir       string        // database, cover cache, transcode cache
	AdminUser     string        // created on first start if no user exists
	AdminPassword string        // idem; ignored once a user exists
	ScanOnStart   bool          // run an incremental scan at startup
	Watch         bool          // watch MusicDir with fsnotify
	WatchDebounce time.Duration // delay before rescanning after changes
	ScanWorkers   int           // parallel tag readers
	FFmpeg        string        // ffmpeg binary
	TranscodeMB   int64         // transcode cache size limit
	LogLevel      slog.Level
}

func env(key, def string) string {
	if v, ok := os.LookupEnv(app.EnvPrefix + key); ok && v != "" {
		return v
	}
	return def
}

// Load reads the configuration. It only fails on malformed values.
func Load() (*Config, error) {
	c := &Config{
		Listen:        env("LISTEN", ":4533"),
		MusicDir:      env("MUSIC_DIR", "/music"),
		DataDir:       env("DATA_DIR", "/data"),
		AdminUser:     env("ADMIN_USER", "admin"),
		AdminPassword: env("ADMIN_PASSWORD", ""),
		FFmpeg:        env("FFMPEG", "ffmpeg"),
	}
	var err error
	if c.ScanOnStart, err = strconv.ParseBool(env("SCAN_ON_START", "true")); err != nil {
		return nil, fmt.Errorf("%sSCAN_ON_START: %w", app.EnvPrefix, err)
	}
	if c.Watch, err = strconv.ParseBool(env("WATCH", "true")); err != nil {
		return nil, fmt.Errorf("%sWATCH: %w", app.EnvPrefix, err)
	}
	if c.WatchDebounce, err = time.ParseDuration(env("WATCH_DEBOUNCE", "10s")); err != nil {
		return nil, fmt.Errorf("%sWATCH_DEBOUNCE: %w", app.EnvPrefix, err)
	}
	if c.ScanWorkers, err = strconv.Atoi(env("SCAN_WORKERS", strconv.Itoa(runtime.NumCPU()))); err != nil || c.ScanWorkers < 1 {
		return nil, fmt.Errorf("%sSCAN_WORKERS: invalid value", app.EnvPrefix)
	}
	if c.TranscodeMB, err = strconv.ParseInt(env("TRANSCODE_CACHE_MB", "2048"), 10, 64); err != nil {
		return nil, fmt.Errorf("%sTRANSCODE_CACHE_MB: %w", app.EnvPrefix, err)
	}
	if err = c.LogLevel.UnmarshalText([]byte(strings.ToUpper(env("LOG_LEVEL", "info")))); err != nil {
		return nil, fmt.Errorf("%sLOG_LEVEL: %w", app.EnvPrefix, err)
	}
	if c.MusicDir, err = filepath.Abs(c.MusicDir); err != nil {
		return nil, err
	}
	if c.DataDir, err = filepath.Abs(c.DataDir); err != nil {
		return nil, err
	}
	return c, nil
}

func (c *Config) DBPath() string       { return filepath.Join(c.DataDir, app.Name+".db") }
func (c *Config) CoverDir() string     { return filepath.Join(c.DataDir, "covers") }
func (c *Config) TranscodeDir() string { return filepath.Join(c.DataDir, "transcode") }
