package api

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"

	"ttyfm/internal/auth"
	"ttyfm/internal/covers"
	"ttyfm/internal/hub"
	"ttyfm/internal/lyrics"
	"ttyfm/internal/scanner"
	"ttyfm/internal/store"
	"ttyfm/internal/stream"
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
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			t.Fatal(err)
		}
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
	if err := os.WriteFile(filepath.Join(root, "Band", "Record", "Alpha.lrc"), []byte("[00:01.00]first\n[00:02.50]second"), 0o644); err != nil {
		t.Fatal(err)
	}
	s := &Server{DB: db, Auth: a, Scanner: sc, Covers: cov, Streamer: st, Log: log, ScanFn: func(bool) {},
		Hub: hub.New(log), Lyrics: lyrics.New(root)}
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
	c.json("GET", "/search?bpm_min=100&bpm_max=130&camelot=8a", nil, 200, &sr)
	if len(sr.Tracks) != 0 { // nothing analysed yet
		t.Fatalf("search by bpm: %+v", sr)
	}
	c.json("GET", "/search?bpm_min=x", nil, 400, nil)
	c.json("GET", "/search?camelot=13Z", nil, 400, nil)
	c.json("GET", "/search?bpm_min=140&bpm_max=120", nil, 400, nil)

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
		Added  []store.RecentAddition `json:"recent_additions"`
		Played []store.RecentItem     `json:"recently_played"`
	}
	c.json("GET", "/home", nil, 200, &home)
	if len(home.Added) != 1 || home.Added[0].Tracks != home.Added[0].Album.TrackCount || len(home.Played) != 1 || home.Played[0].Album == nil {
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

	// Hidden tracks.
	c.json("PUT", "/hidden/"+id, nil, 204, nil)
	c.json("PUT", "/hidden/999999", nil, 404, nil)
	var hidden map[string][]int64
	c.json("GET", "/hidden", nil, 200, &hidden)
	if len(hidden["tracks"]) != 1 {
		t.Fatalf("hidden: %+v", hidden)
	}
	c.json("DELETE", "/hidden/"+id, nil, 204, nil)
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

func TestLyrics(t *testing.T) {
	c := setup(t)
	login(c)
	var tracks struct {
		Items []struct {
			ID    int64  `json:"id"`
			Title string `json:"title"`
		} `json:"items"`
	}
	c.json("GET", "/tracks?sort=name", nil, 200, &tracks)
	var l struct {
		Synced bool `json:"synced"`
		Lines  []struct {
			Ms   int64  `json:"ms"`
			Text string `json:"text"`
		} `json:"lines"`
	}
	c.json("GET", fmt.Sprintf("/tracks/%d/lyrics", tracks.Items[0].ID), nil, 200, &l) // Alpha
	if !l.Synced || len(l.Lines) != 2 || l.Lines[1].Ms != 2500 {
		t.Fatalf("lyrics: %+v", l)
	}
	c.json("GET", fmt.Sprintf("/tracks/%d/lyrics", tracks.Items[1].ID), nil, 404, nil) // Beta
	var f struct {
		Formats []struct{ Name string } `json:"formats"`
	}
	c.json("GET", "/search/facets", nil, 200, &f)
	if len(f.Formats) != 1 || f.Formats[0].Name != "flac" {
		t.Fatalf("facets: %+v", f)
	}
}

// wsDial connects a device to the live hub and returns a reader of messages.
func wsDial(t *testing.T, c *client) (*websocket.Conn, func() map[string]any) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	t.Cleanup(cancel)
	conn, _, err := websocket.Dial(ctx, strings.Replace(c.base, "http", "ws", 1)+"/ws",
		&websocket.DialOptions{HTTPHeader: http.Header{"Authorization": {"Bearer " + c.token}}})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.CloseNow() })
	return conn, func() map[string]any {
		t.Helper()
		_, b, err := conn.Read(ctx)
		if err != nil {
			t.Fatal(err)
		}
		var m map[string]any
		if err := json.Unmarshal(b, &m); err != nil {
			t.Fatalf("ws message %s: %v", b, err)
		}
		return m
	}
}

func TestHub(t *testing.T) {
	a := setup(t)
	login(a)
	b := &client{t: t, base: a.base}
	login(b) // second device, same user

	connA, readA := wsDial(t, a)
	if m := readA(); m["type"] != "hello" || len(m["devices"].([]any)) != 0 {
		t.Fatalf("hello A: %v", m)
	}
	connB, readB := wsDial(t, b)
	if m := readB(); m["type"] != "hello" || len(m["devices"].([]any)) != 1 {
		t.Fatalf("hello B: %v", m)
	}
	m := readA()
	if m["type"] != "presence" || m["online"] != true {
		t.Fatalf("presence: %v", m)
	}
	idB := m["device"].(map[string]any)["id"].(float64)
	ctx := context.Background()

	// B publishes its state; A receives it.
	if err := connB.Write(ctx, websocket.MessageText, []byte(`{"type":"state","state":{"playing":true,"track_id":1}}`)); err != nil {
		t.Fatal(err)
	}
	if m := readA(); m["type"] != "state" || m["state"].(map[string]any)["playing"] != true {
		t.Fatalf("state: %v", m)
	}
	// A sends a command to B.
	if err := connA.Write(ctx, websocket.MessageText, []byte(fmt.Sprintf(`{"type":"command","target":%d,"action":"pause"}`, int64(idB)))); err != nil {
		t.Fatal(err)
	}
	if m := readB(); m["type"] != "command" || m["action"] != "pause" {
		t.Fatalf("command: %v", m)
	}
	// Command to an unknown device: error back to the sender.
	if err := connA.Write(ctx, websocket.MessageText, []byte(`{"type":"command","target":999,"action":"pause"}`)); err != nil {
		t.Fatal(err)
	}
	if m := readA(); m["type"] != "error" {
		t.Fatalf("offline target: %v", m)
	}
	// A creates a playlist over REST: B is told, A (the origin) is not.
	a.json("POST", "/playlists", map[string]any{"name": "Live"}, 201, nil)
	if m := readB(); m["type"] != "changed" || m["what"] != "playlists" {
		t.Fatalf("changed: %v", m)
	}
	// B leaves: A sees it go offline.
	connB.Close(websocket.StatusNormalClosure, "")
	if m := readA(); m["type"] != "presence" || m["online"] != false {
		t.Fatalf("offline: %v", m)
	}
}

func TestNotificationsAPI(t *testing.T) {
	c := setup(t)
	login(c)

	// The scan of setup just added Band — Record: one notification.
	var unread map[string]int
	c.json("GET", "/notifications/unread", nil, 200, &unread)
	if unread["unread"] != 1 {
		t.Fatalf("unread: %+v", unread)
	}
	var list struct {
		Items []struct {
			ID   int64           `json:"id"`
			Kind string          `json:"kind"`
			Read bool            `json:"read"`
			Data store.AddedData `json:"data"`
		} `json:"items"`
		Unread int `json:"unread"`
	}
	c.json("GET", "/notifications", nil, 200, &list)
	if len(list.Items) != 1 || list.Unread != 1 || list.Items[0].Kind != "added" ||
		list.Items[0].Data.Tracks != 2 || list.Items[0].Data.AlbumID == 0 || list.Items[0].Data.Artists[0] != "Band" {
		t.Fatalf("list: %+v", list)
	}
	id := strconv.FormatInt(list.Items[0].ID, 10)
	c.json("PATCH", "/notifications/"+id, map[string]bool{"read": true}, 204, nil)
	c.json("PATCH", "/notifications/"+id, map[string]any{}, 400, nil)
	c.json("PATCH", "/notifications/999", map[string]bool{"read": true}, 404, nil)
	c.json("GET", "/notifications/unread", nil, 200, &unread)
	if unread["unread"] != 0 {
		t.Fatalf("unread after read: %+v", unread)
	}
	c.json("PATCH", "/notifications/"+id, map[string]bool{"read": false}, 204, nil)
	c.json("POST", "/notifications/read", nil, 204, nil)
	c.json("GET", "/notifications/unread", nil, 200, &unread)
	if unread["unread"] != 0 {
		t.Fatalf("unread after read all: %+v", unread)
	}

	var set map[string]bool
	c.json("GET", "/notifications/settings", nil, 200, &set)
	if !set["added"] {
		t.Fatalf("settings: %+v", set)
	}
	c.json("PATCH", "/notifications/settings", map[string]bool{"added": false}, 200, &set)
	if set["added"] {
		t.Fatalf("settings after update: %+v", set)
	}
	c.json("PATCH", "/notifications/settings", map[string]bool{"bogus": true}, 400, nil)
	c.json("GET", "/notifications", nil, 200, &list)
	if len(list.Items) != 0 {
		t.Fatalf("turned off: %+v", list)
	}
}

func TestAnalysisAPI(t *testing.T) {
	c := setup(t)
	login(c)
	var queue struct {
		Items []store.AnalysisJob `json:"items"`
	}
	c.json("GET", "/analysis/queue?limit=10", nil, 200, &queue)
	if len(queue.Items) != 2 || !strings.HasPrefix(queue.Items[0].Path, "Band/Record/") {
		t.Fatalf("queue: %+v", queue)
	}
	a, b := queue.Items[0], queue.Items[1]
	c.json("GET", fmt.Sprintf("/tracks/%d/analysis", a.ID), nil, 404, nil)
	c.json("PUT", fmt.Sprintf("/tracks/%d/analysis", a.ID), map[string]any{"analyzer": "x", "key": "Q", "scale": "major"}, 400, nil)
	for _, j := range []store.AnalysisJob{a, b} {
		c.json("PUT", fmt.Sprintf("/tracks/%d/analysis", j.ID), map[string]any{
			"file_mtime": j.FileMtime, "analyzer": "test/1", "bpm": 120, "key": "A", "scale": "minor",
			"loudness_lufs": -9.5, "energy": 0.8, "danceability": 0.6}, 204, nil)
	}
	var res struct {
		Analysis   store.Analysis `json:"analysis"`
		Compatible []store.Track  `json:"compatible"`
	}
	c.json("GET", fmt.Sprintf("/tracks/%d/analysis", a.ID), nil, 200, &res)
	if *res.Analysis.Camelot != "8A" || len(res.Compatible) != 1 || res.Compatible[0].ID != b.ID {
		t.Fatalf("analysis: %+v", res)
	}
	var tr store.Track
	c.json("GET", fmt.Sprintf("/tracks/%d", a.ID), nil, 200, &tr)
	if tr.BPM == nil || *tr.BPM != 120 {
		t.Fatalf("track bpm: %+v", tr)
	}
	var st store.AnalysisStatus
	c.json("GET", "/analysis", nil, 200, &st)
	if st != (store.AnalysisStatus{Enabled: true, Total: 2, Analyzed: 2}) {
		t.Fatalf("status: %+v", st)
	}
	c.json("GET", "/analysis/queue?analyzer=test%2F1", nil, 200, &queue)
	if len(queue.Items) != 0 {
		t.Fatalf("queue for the same analyzer: %+v", queue)
	}
	c.json("GET", "/analysis/queue?analyzer=test%2F2", nil, 200, &queue)
	if len(queue.Items) != 2 {
		t.Fatalf("queue for a new analyzer: %+v", queue)
	}
	var similar struct {
		Items []store.SimilarTrack `json:"items"`
	}
	c.json("GET", fmt.Sprintf("/tracks/%d/similar", a.ID), nil, 200, &similar)
	if similar.Items == nil || len(similar.Items) != 0 {
		t.Fatalf("similar without embeddings: %+v", similar)
	}
	vec := make([]float32, store.EmbeddingDims)
	vec[0] = 1
	c.json("PUT", fmt.Sprintf("/tracks/%d/analysis", b.ID), map[string]any{
		"file_mtime": b.FileMtime, "analyzer": "test/1", "embedding": vec[:10]}, 400, nil)
	for _, j := range []store.AnalysisJob{a, b} {
		c.json("PUT", fmt.Sprintf("/tracks/%d/analysis", j.ID), map[string]any{
			"file_mtime": j.FileMtime, "analyzer": "test/1", "bpm": 120, "key": "A", "scale": "minor",
			"embedding": vec}, 204, nil)
	}
	c.json("GET", fmt.Sprintf("/tracks/%d/similar?limit=5", a.ID), nil, 200, &similar)
	if len(similar.Items) != 1 || similar.Items[0].ID != b.ID || similar.Items[0].Similarity != 1 ||
		similar.Items[0].Title == "" {
		t.Fatalf("similar: %+v", similar)
	}
	c.json("GET", "/tracks/999/similar", nil, 404, nil)
	c.json("DELETE", fmt.Sprintf("/tracks/%d/analysis", a.ID), nil, 204, nil)
	c.json("DELETE", "/tracks/999/analysis", nil, 404, nil)
	c.json("GET", "/analysis/queue", nil, 200, &queue)
	if len(queue.Items) != 1 || queue.Items[0].ID != a.ID {
		t.Fatalf("queue after reset: %+v", queue)
	}
	// "analyse audio" off: the recommender finds an empty queue.
	c.json("PATCH", "/analysis", map[string]any{"enabled": false}, 200, &st)
	if st.Enabled {
		t.Fatalf("status after turning off: %+v", st)
	}
	c.json("GET", "/analysis/queue", nil, 200, &queue)
	if len(queue.Items) != 0 {
		t.Fatalf("queue while off: %+v", queue)
	}
	c.json("PATCH", "/analysis", map[string]any{}, 400, nil)
	c.json("PATCH", "/analysis", map[string]any{"enabled": true}, 200, &st)
	c.json("GET", "/analysis/queue", nil, 200, &queue)
	if !st.Enabled || len(queue.Items) != 1 {
		t.Fatalf("back on: %+v %+v", st, queue)
	}
	c.json("DELETE", "/analysis", nil, 204, nil)
	c.json("GET", "/analysis", nil, 200, &st)
	if st.Pending != 2 {
		t.Fatalf("status after reset: %+v", st)
	}
}

func TestRadioAPI(t *testing.T) {
	c := setup(t)
	login(c)
	var queue struct {
		Items []store.AnalysisJob `json:"items"`
	}
	c.json("GET", "/analysis/queue?limit=10", nil, 200, &queue)
	a, b := queue.Items[0], queue.Items[1]
	var radio store.Radio
	// Nothing analysed yet: the fallback still plays the other track.
	c.json("GET", fmt.Sprintf("/radio?track=%d", a.ID), nil, 200, &radio)
	if radio.Mode != "fallback" || radio.Seed.Kind != "track" || len(radio.Items) != 1 || radio.Items[0].ID != b.ID {
		t.Fatalf("fallback radio: %+v", radio)
	}
	vec := make([]float32, store.EmbeddingDims)
	vec[0] = 1
	for _, j := range []store.AnalysisJob{a, b} {
		c.json("PUT", fmt.Sprintf("/tracks/%d/analysis", j.ID), map[string]any{
			"file_mtime": j.FileMtime, "analyzer": "test/1", "embedding": vec}, 204, nil)
	}
	c.json("GET", fmt.Sprintf("/radio?track=%d&limit=5", a.ID), nil, 200, &radio)
	if radio.Mode != "similar" || len(radio.Items) != 1 || radio.Items[0].ID != b.ID || radio.Items[0].Similarity == nil {
		t.Fatalf("radio: %+v", radio)
	}
	artist := radio.Items[0].ArtistID
	c.json("GET", fmt.Sprintf("/radio?track=%d&exclude=%d", a.ID, b.ID), nil, 200, &radio)
	if len(radio.Items) != 0 {
		t.Fatalf("radio with the only other track excluded: %+v", radio)
	}
	c.json("GET", fmt.Sprintf("/radio?artist=%d&recent=%d", artist, a.ID), nil, 200, &radio)
	if radio.Seed.Kind != "artist" || len(radio.Items) != 1 || radio.Items[0].ID != b.ID {
		t.Fatalf("artist radio: %+v", radio)
	}
	c.json("GET", "/radio", nil, 400, nil)
	c.json("GET", "/radio?track=1&artist=1", nil, 400, nil)
	c.json("GET", "/radio?track=x", nil, 400, nil)
	c.json("GET", fmt.Sprintf("/radio?track=%d&recent=1,x", a.ID), nil, 400, nil)
	c.json("GET", "/radio?track=999", nil, 404, nil)
	c.json("GET", "/radio?artist=999", nil, 404, nil)

	// No listening history: no mixes of the day yet.
	var mixes struct {
		Items []store.Mix `json:"items"`
	}
	c.json("GET", "/mixes", nil, 200, &mixes)
	if mixes.Items == nil || len(mixes.Items) != 0 {
		t.Fatalf("mixes: %+v", mixes)
	}
	c.json("GET", "/mixes/1", nil, 404, nil)
	c.json("GET", "/mixes/x", nil, 400, nil)
	var home map[string]any
	c.json("GET", "/home", nil, 200, &home)
	if m, ok := home["mixes"].([]any); !ok || len(m) != 0 {
		t.Fatalf("home mixes: %v", home["mixes"])
	}
}
