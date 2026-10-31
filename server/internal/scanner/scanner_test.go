package scanner

import (
	"context"
	"image"
	"image/color"
	"image/png"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"selfstream/internal/covers"
	"selfstream/internal/store"
)

func needFFmpeg(t *testing.T) {
	t.Helper()
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		t.Skip("ffmpeg not installed")
	}
}

func writePNG(t *testing.T, p string, c color.Color, size int) {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, size, size))
	for x := 0; x < size; x++ {
		for y := 0; y < size; y++ {
			img.Set(x, y, c)
		}
	}
	f, err := os.Create(p)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	if err := png.Encode(f, img); err != nil {
		t.Fatal(err)
	}
}

// genTrack writes a 1-second sine file with the given tags. If coverPNG is
// set, the image is embedded as attached picture.
func genTrack(t *testing.T, root, rel string, tags map[string]string, coverPNG string) {
	t.Helper()
	out := filepath.Join(root, rel)
	if err := os.MkdirAll(filepath.Dir(out), 0o755); err != nil {
		t.Fatal(err)
	}
	args := []string{"-y", "-loglevel", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=1"}
	if coverPNG != "" {
		args = append(args, "-i", coverPNG, "-map", "0:a", "-map", "1:v", "-c:v", "png", "-disposition:v", "attached_pic")
	}
	for k, v := range tags {
		args = append(args, "-metadata", k+"="+v)
	}
	if strings.HasSuffix(rel, ".mp3") {
		args = append(args, "-c:a", "libmp3lame", "-id3v2_version", "3")
	}
	args = append(args, out)
	if b, err := exec.Command("ffmpeg", args...).CombinedOutput(); err != nil {
		t.Fatalf("ffmpeg: %v\n%s", err, b)
	}
}

type env struct {
	root string
	db   *store.DB
	sc   *Scanner
	cov  *covers.Cache
}

func newEnv(t *testing.T) *env {
	t.Helper()
	needFFmpeg(t)
	dir := t.TempDir()
	root := filepath.Join(dir, "music")
	os.MkdirAll(root, 0o755)
	db, err := store.Open(filepath.Join(dir, "db.sqlite"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close() })
	cov, err := covers.New(filepath.Join(dir, "covers"))
	if err != nil {
		t.Fatal(err)
	}
	log := slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelWarn}))
	return &env{root: root, db: db, cov: cov, sc: New(db, root, cov, 4, log)}
}

func (e *env) scan(t *testing.T, full bool) Stats {
	t.Helper()
	st, err := e.sc.Scan(context.Background(), full)
	if err != nil {
		t.Fatal(err)
	}
	return st
}

func TestScan(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()

	red := filepath.Join(t.TempDir(), "red.png")
	writePNG(t, red, color.RGBA{255, 0, 0, 255}, 1000)

	// Album 1: folder cover.jpg-style image, two tracks.
	genTrack(t, e.root, "Artist A/Album One/01.flac", map[string]string{
		"title": "First", "artist": "Artist A", "album": "Album One", "track": "1/2", "date": "1999-04-01",
		"REPLAYGAIN_TRACK_GAIN": "-6.50 dB"}, "")
	genTrack(t, e.root, "Artist A/Album One/02.flac", map[string]string{
		"title": "Second", "artist": "Artist A", "album": "Album One", "track": "2/2"}, "")
	writePNG(t, filepath.Join(e.root, "Artist A/Album One/Folder.png"), color.RGBA{0, 0, 255, 255}, 50)
	// Album 2: embedded cover, mp3, compilation with album artist.
	genTrack(t, e.root, "Various/Comp/01.mp3", map[string]string{
		"title": "Guest Song", "artist": "Guest", "album_artist": "Various Artists", "album": "Comp", "track": "1"}, red)
	// Hidden and non-audio files are ignored.
	os.WriteFile(filepath.Join(e.root, "notes.txt"), []byte("x"), 0o644)
	os.MkdirAll(filepath.Join(e.root, "@eaDir"), 0o755)
	os.WriteFile(filepath.Join(e.root, "@eaDir", "x.mp3"), []byte("x"), 0o644)

	st := e.scan(t, false)
	if st.Seen != 3 || st.Added != 3 || st.Errors != 0 {
		t.Fatalf("initial scan: %+v", st)
	}

	albums, _ := e.db.Albums(ctx, "name", "", 0)
	if len(albums.Items) != 2 {
		t.Fatalf("albums: %+v", albums.Items)
	}
	for _, a := range albums.Items {
		if a.CoverID == nil {
			t.Fatalf("album %q has no cover", a.Title)
		}
		hash, err := e.db.CoverHash(ctx, *a.CoverID)
		if err != nil {
			t.Fatal(err)
		}
		for _, size := range covers.Sizes {
			if _, err := os.Stat(e.cov.Path(hash, size)); err != nil {
				t.Fatalf("cover %q size %d missing: %v", a.Title, size, err)
			}
		}
	}
	one := albums.Items[0]
	if one.Title != "Album One" || one.Year == nil || *one.Year != 1999 || one.TrackCount != 2 {
		t.Fatalf("album one: %+v", one)
	}
	tracks, _ := e.db.AlbumTracks(ctx, one.ID)
	if tracks[0].Title != "First" || *tracks[0].TrackNo != 1 || tracks[0].RGTrackGain == nil || *tracks[0].RGTrackGain != -6.5 {
		t.Fatalf("track tags: %+v", tracks[0])
	}
	if tracks[0].DurationMs < 900 || tracks[0].DurationMs > 1100 {
		t.Fatalf("duration %d", tracks[0].DurationMs)
	}

	// Nothing changed: nothing re-read.
	if st := e.scan(t, false); st.Added+st.Updated+st.Moved+st.Missing != 0 {
		t.Fatalf("no-op scan: %+v", st)
	}
	// Full scan re-reads everything but keeps ids.
	if st := e.scan(t, true); st.Updated != 3 || st.Added != 0 {
		t.Fatalf("full scan: %+v", st)
	}
	again, _ := e.db.AlbumTracks(ctx, one.ID)
	if again[0].ID != tracks[0].ID {
		t.Fatal("full scan changed ids")
	}

	// Retag a file.
	genTrack(t, e.root, "Artist A/Album One/02.flac", map[string]string{
		"title": "Second (Remastered)", "artist": "Artist A", "album": "Album One", "track": "2/2"}, "")
	future := time.Now().Add(time.Minute)
	os.Chtimes(filepath.Join(e.root, "Artist A/Album One/02.flac"), future, future)
	if st := e.scan(t, false); st.Updated != 1 {
		t.Fatalf("retag scan: %+v", st)
	}
	if r, _ := e.db.Search(ctx, "remast", store.Filter{}, 10); len(r.Tracks) != 1 {
		t.Fatalf("search after retag: %+v", r.Tracks)
	}
}

func TestScanMoveAndMissing(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	genTrack(t, e.root, "A/song.flac", map[string]string{"title": "Song", "artist": "X", "album": "Y"}, "")
	genTrack(t, e.root, "A/other.flac", map[string]string{"title": "Other", "artist": "X", "album": "Y"}, "")
	e.scan(t, false)

	page, _ := e.db.Tracks(ctx, "name", "", 0)
	var songID int64
	for _, tr := range page.Items {
		if tr.Title == "Song" {
			songID = tr.ID
		}
	}
	pl, _ := e.db.CreatePlaylist(ctx, "P", nil)
	e.db.AddTracks(ctx, pl, []int64{songID}, nil)
	e.db.SetFavorite(ctx, "tracks", songID, true)

	// Rename/move: same id, playlist and favourite kept.
	os.MkdirAll(filepath.Join(e.root, "B"), 0o755)
	os.Rename(filepath.Join(e.root, "A/song.flac"), filepath.Join(e.root, "B/renamed.flac"))
	if st := e.scan(t, false); st.Moved != 1 || st.Added != 0 || st.Missing != 0 {
		t.Fatalf("move scan: %+v", st)
	}
	entries, _ := e.db.PlaylistTracks(ctx, pl)
	if len(entries) != 1 || entries[0].Track.ID != songID {
		t.Fatalf("playlist after move: %+v", entries)
	}

	// Delete: soft-deleted, hidden from listings, playlist entry kept in DB.
	os.Remove(filepath.Join(e.root, "B/renamed.flac"))
	if st := e.scan(t, false); st.Missing != 1 {
		t.Fatalf("delete scan: %+v", st)
	}
	if _, err := e.db.Track(ctx, songID); err != store.ErrNotFound {
		t.Fatalf("missing track still visible: %v", err)
	}
	if entries, _ := e.db.PlaylistTracks(ctx, pl); len(entries) != 0 {
		t.Fatalf("missing track listed in playlist")
	}

	// Comes back at the same path: restored with the same id.
	genTrack(t, e.root, "B/renamed.flac", map[string]string{"title": "Song", "artist": "X", "album": "Y"}, "")
	e.scan(t, false)
	if entries, _ := e.db.PlaylistTracks(ctx, pl); len(entries) != 1 || entries[0].Track.ID != songID {
		t.Fatalf("restored track: %+v", entries)
	}

	// Unmounted volume: refuse to mark everything missing.
	os.RemoveAll(e.root)
	os.MkdirAll(e.root, 0o755)
	if _, err := e.sc.Scan(ctx, false); err == nil {
		t.Fatal("empty root: expected an error")
	}
	if _, err := e.db.Track(ctx, songID); err != nil {
		t.Fatalf("track lost after empty scan: %v", err)
	}
}

func TestTagParsing(t *testing.T) {
	for in, want := range map[string]int{"3": 3, "03/12": 3, "": 0, "a": 0, "12a": 12} {
		if got := leadingInt(in); got != want {
			t.Errorf("leadingInt(%q) = %d", in, got)
		}
	}
	if y := year("", "2004-05-01"); y != 2004 {
		t.Errorf("year = %d", y)
	}
	if g := gain("-6.54 dB"); g == nil || *g != -6.54 {
		t.Errorf("gain = %v", g)
	}
	if g := gain("junk"); g != nil {
		t.Errorf("gain junk = %v", *g)
	}
}
