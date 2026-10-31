package api

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"testing"

	"selfstream/internal/auth"
	"selfstream/internal/covers"
	"selfstream/internal/scanner"
	"selfstream/internal/store"
	"selfstream/internal/stream"
)

type client struct {
	t     *testing.T
	base  string
	token string
}

func (c *client) do(method, path string, body any) (*http.Response, []byte) {
	c.t.Helper()
	var rd io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rd = bytes.NewReader(b)
	}
	req, _ := http.NewRequest(method, c.base+path, rd)
	if c.token != "" {
		req.Header.Set("Authorization", "Bearer "+c.token)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		c.t.Fatal(err)
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(resp.Body)
	return resp, b
}

func (c *client) json(method, path string, body any, wantStatus int, out any) {
	c.t.Helper()
	resp, b := c.do(method, path, body)
	if resp.StatusCode != wantStatus {
		c.t.Fatalf("%s %s: status %d, want %d: %s", method, path, resp.StatusCode, wantStatus, b)
	}
	if out != nil {
		if err := json.Unmarshal(b, out); err != nil {
			c.t.Fatalf("%s %s: decode: %v: %s", method, path, err, b)
		}
	}
}

func setup(t *testing.T) *client {
	t.Helper()
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		t.Skip("ffmpeg not installed")
	}
	dir := t.TempDir()
	root := filepath.Join(dir, "music")
	for i, title := range []string{"Alpha", "Beta"} {
		p := filepath.Join(root, "Band", "Record", title+".flac")
		os.MkdirAll(filepath.Dir(p), 0o755)
		out, err := exec.Command("ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi", "-i", "sine=duration=3",
			"-metadata", "title="+title, "-metadata", "artist=Band", "-metadata", "album=Record",
			"-metadata", "track="+string(rune('1'+i)), p).CombinedOutput()
		if err != nil {
			t.Fatalf("ffmpeg: %v %s", err, out)
		}
	}
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	db, err := store.Open(filepath.Join(dir, "db.sqlite"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close() })
	cov, _ := covers.New(filepath.Join(dir, "covers"))
	st, _ := stream.New(root, "ffmpeg", filepath.Join(dir, "transcode"), 100, log)
	sc := scanner.New(db, root, cov, 2, log)
	if _, err := sc.Scan(context.Background(), false); err != nil {
		t.Fatal(err)
	}
	a := auth.NewService(db, log)
	if err := a.EnsureUser(context.Background(), "me", "secret"); err != nil {
		t.Fatal(err)
	}
	s := &Server{DB: db, Auth: a, Scanner: sc, Covers: cov, Streamer: st, Log: log, ScanFn: func(bool) {}}
	ts := httptest.NewServer(s.Handler())
	t.Cleanup(ts.Close)
	return &client{t: t, base: ts.URL + "/api/v1"}
}

func login(c *client) {
	var res struct {
		Token  string `json:"token"`
		Device struct {
			ID int64 `json:"id"`
		} `json:"device"`
	}
	c.json("POST", "/auth/login", map[string]string{"username": "me", "password": "secret",
		"device_name": "test", "platform": "macos"}, 200, &res)
	if res.Token == "" || res.Device.ID == 0 {
		c.t.Fatalf("login: %+v", res)
	}
	c.token = res.Token
}

func TestAuth(t *testing.T) {
	c := setup(t)
	c.json("GET", "/health", nil, 200, nil)
	c.json("GET", "/albums", nil, 401, nil)
	c.json("POST", "/auth/login", map[string]string{"username": "me", "password": "nope"}, 401, nil)
	c.json("POST", "/auth/login", map[string]string{"username": "who", "password": "secret"}, 401, nil)
	login(c)
	c.json("GET", "/me", nil, 200, nil)

	// Token in query string works too (for players without headers).
	tok := c.token
	c.token = ""
	c.json("GET", "/me?token="+tok, nil, 200, nil)

	// Logout revokes the token immediately.
	c.token = tok
	c.json("POST", "/auth/logout", nil, 204, nil)
	c.json("GET", "/me", nil, 401, nil)
}

func TestLibraryAndStream(t *testing.T) {
	c := setup(t)
	login(c)

	var albums store.Page[store.Album]
	c.json("GET", "/albums?sort=added", nil, 200, &albums)
	if len(albums.Items) != 1 {
		t.Fatalf("albums: %+v", albums)
	}
	var detail struct {
		Album  store.Album   `json:"album"`
		Tracks []store.Track `json:"tracks"`
	}
	c.json("GET", "/albums/"+itoa(albums.Items[0].ID), nil, 200, &detail)
	if len(detail.Tracks) != 2 || detail.Tracks[0].Title != "Alpha" {
		t.Fatalf("album detail: %+v", detail)
	}
	c.json("GET", "/albums/999", nil, 404, nil)
	c.json("GET", "/albums/abc", nil, 400, nil)

	var sr store.SearchResult
	c.json("GET", "/search?q=bet", nil, 200, &sr)
	if len(sr.Tracks) != 1 || sr.Tracks[0].Title != "Beta" {
		t.Fatalf("search: %+v", sr)
	}

	id := itoa(detail.Tracks[0].ID)
	// Original with Range.
	req, _ := http.NewRequest("GET", c.base+"/stream/"+id, nil)
	req.Header.Set("Authorization", "Bearer "+c.token)
	req.Header.Set("Range", "bytes=0-99")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	b, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != 206 || len(b) != 100 || string(b[:4]) != "fLaC" || resp.Header.Get("Content-Type") != "audio/flac" {
		t.Fatalf("range: status %d len %d ct %s", resp.StatusCode, len(b), resp.Header.Get("Content-Type"))
	}

	// Transcoded: first request streams, second is served from cache with Range.
	resp1, b1 := c.do("GET", "/stream/"+id+"?format=opus&bitrate=64", nil)
	if resp1.StatusCode != 200 || !bytes.HasPrefix(b1, []byte("OggS")) {
		t.Fatalf("opus: status %d len %d", resp1.StatusCode, len(b1))
	}
	resp2, b2 := c.do("GET", "/stream/"+id+"?format=opus&bitrate=64", nil)
	if resp2.StatusCode != 200 || resp2.Header.Get("Accept-Ranges") != "bytes" || !bytes.Equal(b1, b2) {
		t.Fatalf("cached opus: status %d ranges %q same=%v", resp2.StatusCode, resp2.Header.Get("Accept-Ranges"), bytes.Equal(b1, b2))
	}
	c.json("GET", "/stream/"+id+"?format=wav", nil, 400, nil)

	// Plays feed "recently played" on the home screen.
	var rec map[string]int
	c.json("POST", "/plays", map[string]any{"plays": []map[string]any{
		{"track_id": detail.Tracks[0].ID, "started_at": 1700000000000, "listened_ms": 2500, "skipped": false},
	}}, 200, &rec)
	if rec["recorded"] != 1 {
		t.Fatalf("plays: %+v", rec)
	}
	var home struct {
		Added  []store.Album `json:"recently_added"`
		Played []store.Track `json:"recently_played_tracks"`
	}
	c.json("GET", "/home", nil, 200, &home)
	if len(home.Added) != 1 || len(home.Played) != 1 {
		t.Fatalf("home: %+v", home)
	}

	// Favourites.
	c.json("PUT", "/favorites/tracks/"+id, nil, 204, nil)
	c.json("PUT", "/favorites/bogus/"+id, nil, 400, nil)
	var favs map[string][]int64
	c.json("GET", "/favorites", nil, 200, &favs)
	if len(favs["tracks"]) != 1 {
		t.Fatalf("favorites: %+v", favs)
	}
	c.json("DELETE", "/favorites/tracks/"+id, nil, 204, nil)
}

func TestPlaylistsAPI(t *testing.T) {
	c := setup(t)
	login(c)
	var tracks store.Page[store.Track]
	c.json("GET", "/tracks", nil, 200, &tracks)

	var f1, f2 map[string]int64
	c.json("POST", "/folders", map[string]any{"name": "Moods"}, 201, &f1)
	c.json("POST", "/folders", map[string]any{"name": "Calm", "parent_id": f1["id"]}, 201, &f2)
	var pl store.Playlist
	c.json("POST", "/playlists", map[string]any{"name": "Evening", "folder_id": f2["id"],
		"track_ids": []int64{tracks.Items[1].ID, tracks.Items[0].ID}}, 201, &pl)
	if pl.TrackCount != 2 {
		t.Fatalf("created playlist: %+v", pl)
	}

	// Cycle refused, move to root via explicit null.
	c.json("PATCH", "/folders/"+itoa(f1["id"]), map[string]any{"parent_id": f2["id"]}, 400, nil)
	c.json("PATCH", "/folders/"+itoa(f2["id"]), map[string]any{"parent_id": nil, "position": 0}, 204, nil)
	// Rename only: playlist stays in its folder.
	c.json("PATCH", "/playlists/"+itoa(pl.ID), map[string]any{"name": "Night"}, 204, nil)

	var tree store.Tree
	c.json("GET", "/playlists/tree", nil, 200, &tree)
	if len(tree.Folders) != 2 || tree.Folders[0].Name != "Calm" || len(tree.Folders[0].Playlists) != 1 ||
		tree.Folders[0].Playlists[0].Name != "Night" {
		t.Fatalf("tree: %+v", tree)
	}

	var entries struct {
		Items []store.PlaylistEntry `json:"items"`
	}
	c.json("GET", "/playlists/"+itoa(pl.ID)+"/tracks", nil, 200, &entries)
	c.json("PATCH", "/playlists/"+itoa(pl.ID)+"/tracks",
		map[string]any{"entry_id": entries.Items[1].EntryID, "to_position": 0}, 204, nil)
	c.json("GET", "/playlists/"+itoa(pl.ID)+"/tracks", nil, 200, &entries)
	if entries.Items[0].Track.ID != tracks.Items[0].ID {
		t.Fatalf("reorder: %+v", entries.Items)
	}
	c.json("DELETE", "/playlists/"+itoa(pl.ID)+"/tracks/"+itoa(entries.Items[0].EntryID), nil, 204, nil)
	c.json("DELETE", "/folders/"+itoa(f2["id"]), nil, 204, nil)
	c.json("GET", "/playlists/"+itoa(pl.ID), nil, 404, nil)
}

func itoa(n int64) string { return strconv.FormatInt(n, 10) }
