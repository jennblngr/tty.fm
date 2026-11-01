package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestMigrateLegacyDB(t *testing.T) {
	dir := t.TempDir()
	c := &Config{DataDir: dir}
	for _, f := range []string{"selfstream.db", "selfstream.db-wal"} {
		if err := os.WriteFile(filepath.Join(dir, f), []byte(f), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	moved, err := c.MigrateLegacyDB()
	if err != nil || !moved {
		t.Fatalf("first migration: moved=%v err=%v", moved, err)
	}
	for _, f := range []string{"ttyfm.db", "ttyfm.db-wal"} {
		if _, err := os.Stat(filepath.Join(dir, f)); err != nil {
			t.Errorf("%s missing after migration", f)
		}
	}
	if _, err := os.Stat(filepath.Join(dir, "selfstream.db")); !os.IsNotExist(err) {
		t.Error("legacy database still present")
	}
	// Second start: nothing left to do, and an existing database is never overwritten.
	os.WriteFile(filepath.Join(dir, "selfstream.db"), []byte("stale"), 0o644)
	if moved, err := c.MigrateLegacyDB(); err != nil || moved {
		t.Fatalf("second migration: moved=%v err=%v", moved, err)
	}
	if b, _ := os.ReadFile(filepath.Join(dir, "ttyfm.db")); string(b) != "selfstream.db" {
		t.Errorf("ttyfm.db overwritten: %q", b)
	}
}
