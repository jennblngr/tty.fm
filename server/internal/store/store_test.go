package store

import (
	"context"
	"errors"
	"fmt"
	"path/filepath"
	"testing"
)

func openTest(t *testing.T) *DB {
	t.Helper()
	db, err := Open(filepath.Join(t.TempDir(), "test.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close() })
	return db
}

// seed inserts tracks through the same writer the scanner uses.
func seed(t *testing.T, db *DB, files ...TrackFile) []int64 {
	t.Helper()
	var ids []int64
	err := db.WriteLibrary(context.Background(), func(w *LibWriter) error {
		for i := range files {
			f := files[i]
			if f.Format == "" {
				f.Format = "flac"
			}
			if f.DurationMs == 0 {
				f.DurationMs = 180000
			}
			id, err := w.UpsertTrack(&f, 0)
			if err != nil {
				return err
			}
			ids = append(ids, id)
		}
		return w.Finalize()
	})
	if err != nil {
		t.Fatal(err)
	}
	return ids
}

func TestMigrateIdempotent(t *testing.T) {
	path := filepath.Join(t.TempDir(), "m.db")
	for i := 0; i < 2; i++ {
		db, err := Open(path)
		if err != nil {
			t.Fatalf("open %d: %v", i, err)
		}
		db.Close()
	}
}

func TestArtistAndAlbumDedup(t *testing.T) {
	db := openTest(t)
	ctx := context.Background()
	seed(t, db,
		TrackFile{Path: "a/1.flac", Title: "One", Artist: "Beyoncé", Album: "Lemonade", TrackNo: 1},
		TrackFile{Path: "a/2.flac", Title: "Two", Artist: "beyonce ", Album: "LEMONADE", TrackNo: 2},
		TrackFile{Path: "b/1.flac", Title: "Song", Artist: "Guest", AlbumArtist: "Beyoncé", Album: "Lemonade", TrackNo: 3},
	)
	artists, err := db.Artists(ctx, "", 0, false)
	if err != nil {
		t.Fatal(err)
	}
	if len(artists.Items) != 2 {
		t.Fatalf("want 2 artists, got %+v", artists.Items)
	}
	albums, err := db.Albums(ctx, "name", "", 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(albums.Items) != 1 || albums.Items[0].TrackCount != 3 {
		t.Fatalf("want 1 album with 3 tracks, got %+v", albums.Items)
	}
	tracks, err := db.AlbumTracks(ctx, albums.Items[0].ID)
	if err != nil {
		t.Fatal(err)
	}
	if len(tracks) != 3 || tracks[2].Artist != "Guest" || tracks[2].AlbumArtist != "Beyoncé" {
		t.Fatalf("unexpected tracks %+v", tracks)
	}
}

func TestPagination(t *testing.T) {
	db := openTest(t)
	ctx := context.Background()
	var files []TrackFile
	for i := 0; i < 25; i++ {
		files = append(files, TrackFile{
			Path: fmt.Sprintf("x/%02d.flac", i), Title: fmt.Sprintf("Track %02d", i),
			Artist: fmt.Sprintf("Artist %02d", i), Album: fmt.Sprintf("Album %02d", i),
		})
	}
	seed(t, db, files...)

	for _, sort := range []string{"name", "added", "year"} {
		seen := map[int64]bool{}
		next := ""
		pages := 0
		for {
			p, err := db.Albums(ctx, sort, next, 10)
			if err != nil {
				t.Fatal(err)
			}
			for _, a := range p.Items {
				if seen[a.ID] {
					t.Fatalf("%s: duplicate album %d", sort, a.ID)
				}
				seen[a.ID] = true
			}
			pages++
			if p.Next == "" {
				break
			}
			next = p.Next
		}
		if len(seen) != 25 || pages != 3 {
			t.Fatalf("%s: got %d albums in %d pages", sort, len(seen), pages)
		}
	}

	seen := 0
	next := ""
	for {
		p, err := db.Artists(ctx, next, 7, false)
		if err != nil {
			t.Fatal(err)
		}
		seen += len(p.Items)
		if p.Next == "" {
			break
		}
		next = p.Next
	}
	if seen != 25 {
		t.Fatalf("artists: got %d", seen)
	}

	if _, err := db.Albums(ctx, "name", "garbage!", 10); !errors.Is(err, ErrInvalid) {
		t.Fatalf("bad cursor: want ErrInvalid, got %v", err)
	}
}

func TestSearch(t *testing.T) {
	db := openTest(t)
	ctx := context.Background()
	seed(t, db,
		TrackFile{Path: "1.flac", Title: "Hey Jude", Artist: "The Beatles", Album: "Past Masters"},
		TrackFile{Path: "2.flac", Title: "Dancing Queen", Artist: "ABBA", Album: "Arrival"},
		TrackFile{Path: "3.flac", Title: "Déjà vu", Artist: "Beyoncé", Album: "B'Day"},
	)
	cases := []struct {
		q                       string
		artists, albums, tracks int
	}{
		{"jud", 0, 0, 1},
		{"beat", 1, 1, 1},         // artist, its album, its track (artist column)
		{"beyonce deja", 0, 0, 1}, // accents ignored, all words must match
		{"arriv", 0, 1, 1},
		{"zzz", 0, 0, 0},
		{"  ", 0, 0, 0},
		{`"); DROP`, 0, 0, 0}, // FTS syntax is neutralised
	}
	for _, c := range cases {
		r, err := db.Search(ctx, c.q, Filter{}, 10)
		if err != nil {
			t.Fatalf("%q: %v", c.q, err)
		}
		if len(r.Artists) != c.artists || len(r.Albums) != c.albums || len(r.Tracks) != c.tracks {
			t.Errorf("%q: got %d/%d/%d, want %d/%d/%d", c.q,
				len(r.Artists), len(r.Albums), len(r.Tracks), c.artists, c.albums, c.tracks)
		}
	}
}

func TestSearchFilters(t *testing.T) {
	db := openTest(t)
	ctx := context.Background()
	seed(t, db,
		TrackFile{Path: "a/1.flac", Title: "Rolling", Artist: "Adele", Album: "21", Year: 2011, Genre: "Pop", Format: "flac"},
		TrackFile{Path: "a/2.flac", Title: "Rumour", Artist: "Adele", Album: "21", Year: 2011, Genre: "pop", Format: "flac"},
		TrackFile{Path: "b/1.mp3", Title: "Roxanne", Artist: "The Police", Album: "Outlandos", Year: 1978, Genre: "Rock", Format: "mp3"},
		TrackFile{Path: "c/1.mp3", Title: "Hello", Artist: "Adele", Album: "25", Year: 2015, Genre: "Pop", Format: "mp3"},
	)
	cases := []struct {
		q              string
		f              Filter
		albums, tracks int
	}{
		{"", Filter{}, 0, 0},
		{"", Filter{Genre: "POP"}, 2, 3}, // case-insensitive
		{"", Filter{YearMin: 1970, YearMax: 1989}, 1, 1},
		{"", Filter{Format: "MP3"}, 2, 2},
		{"ro", Filter{}, 0, 2}, // Rolling, Roxanne
		{"ro", Filter{Genre: "rock"}, 0, 1},
		{"ro", Filter{YearMin: 2000}, 0, 1},
		{"adele", Filter{Format: "mp3"}, 1, 1}, // album 25 and its track only
	}
	for _, c := range cases {
		r, err := db.Search(ctx, c.q, c.f, 50)
		if err != nil {
			t.Fatalf("%q %+v: %v", c.q, c.f, err)
		}
		if len(r.Albums) != c.albums || len(r.Tracks) != c.tracks {
			t.Errorf("%q %+v: got %d albums / %d tracks, want %d / %d", c.q, c.f, len(r.Albums), len(r.Tracks), c.albums, c.tracks)
		}
	}
	fa, err := db.SearchFacets(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if len(fa.Genres) != 2 || fa.Genres[0].Count != 3 || len(fa.Formats) != 2 || *fa.YearMin != 1978 || *fa.YearMax != 2015 {
		t.Fatalf("facets: %+v", fa)
	}
}

func ptr[T any](v T) *T { return &v }

// treeShape renders the tree as a compact string for assertions.
func treeShape(t *testing.T, db *DB) string {
	t.Helper()
	tree, err := db.PlaylistTree(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	var render func(fs []Folder, ps []Playlist) string
	render = func(fs []Folder, ps []Playlist) string {
		s := ""
		for _, f := range fs {
			s += f.Name + "[" + render(f.Folders, f.Playlists) + "]"
		}
		for _, p := range ps {
			s += p.Name + ";"
		}
		return s
	}
	return render(tree.Folders, tree.Playlists)
}

func TestPlaylistTree(t *testing.T) {
	db := openTest(t)
	ctx := context.Background()

	rock, _ := db.CreateFolder(ctx, "Rock", nil)
	jazz, _ := db.CreateFolder(ctx, "Jazz", nil)
	seventies, _ := db.CreateFolder(ctx, "70s", &rock)
	p1, _ := db.CreatePlaylist(ctx, "Classics", &seventies)
	p2, _ := db.CreatePlaylist(ctx, "Chill", nil)
	_, _ = db.CreatePlaylist(ctx, "Live", &seventies)

	if got, want := treeShape(t, db), "Rock[70s[Classics;Live;]]Jazz[]Chill;"; got != want {
		t.Fatalf("initial tree\n got %s\nwant %s", got, want)
	}

	// Move 70s under Jazz.
	if err := db.UpdateFolder(ctx, seventies, FolderUpdate{MoveTo: ptr(&jazz)}); err != nil {
		t.Fatal(err)
	}
	if got, want := treeShape(t, db), "Rock[]Jazz[70s[Classics;Live;]]Chill;"; got != want {
		t.Fatalf("after folder move\n got %s\nwant %s", got, want)
	}

	// Cycles are refused: Jazz into 70s (its child) or into itself.
	if err := db.UpdateFolder(ctx, jazz, FolderUpdate{MoveTo: ptr(&seventies)}); !errors.Is(err, ErrInvalid) {
		t.Fatalf("cycle: want ErrInvalid, got %v", err)
	}
	if err := db.UpdateFolder(ctx, jazz, FolderUpdate{MoveTo: ptr(&jazz)}); !errors.Is(err, ErrInvalid) {
		t.Fatalf("self: want ErrInvalid, got %v", err)
	}

	// Reorder root folders, then move a playlist to root at index 0.
	if err := db.UpdateFolder(ctx, jazz, FolderUpdate{Position: ptr(0)}); err != nil {
		t.Fatal(err)
	}
	var root *int64
	if err := db.UpdatePlaylist(ctx, p1, FolderUpdate{MoveTo: &root, Position: ptr(0)}); err != nil {
		t.Fatal(err)
	}
	if got, want := treeShape(t, db), "Jazz[70s[Live;]]Rock[]Classics;Chill;"; got != want {
		t.Fatalf("after reorder\n got %s\nwant %s", got, want)
	}

	// Positions stay dense after moves.
	tree, _ := db.PlaylistTree(ctx)
	for i, p := range tree.Playlists {
		if p.Position != i {
			t.Fatalf("root playlist %s has position %d, want %d", p.Name, p.Position, i)
		}
	}

	// Renaming with an empty name fails; unknown parent fails.
	if err := db.UpdatePlaylist(ctx, p2, FolderUpdate{Name: ptr(" ")}); !errors.Is(err, ErrInvalid) {
		t.Fatalf("empty name: got %v", err)
	}
	if _, err := db.CreatePlaylist(ctx, "X", ptr(int64(999))); !errors.Is(err, ErrInvalid) {
		t.Fatalf("bad folder: got %v", err)
	}

	// Deleting a folder deletes its subtree.
	if err := db.DeleteFolder(ctx, jazz); err != nil {
		t.Fatal(err)
	}
	if got, want := treeShape(t, db), "Rock[]Classics;Chill;"; got != want {
		t.Fatalf("after delete\n got %s\nwant %s", got, want)
	}
	if err := db.DeleteFolder(ctx, jazz); !errors.Is(err, ErrNotFound) {
		t.Fatalf("double delete: got %v", err)
	}
}

func TestPlaylistTracks(t *testing.T) {
	db := openTest(t)
	ctx := context.Background()
	ids := seed(t, db,
		TrackFile{Path: "a.flac", Title: "A", Artist: "X", Album: "Y"},
		TrackFile{Path: "b.flac", Title: "B", Artist: "X", Album: "Y"},
		TrackFile{Path: "c.flac", Title: "C", Artist: "X", Album: "Y"},
	)
	pl, _ := db.CreatePlaylist(ctx, "Mix", nil)

	order := func() string {
		es, err := db.PlaylistTracks(ctx, pl)
		if err != nil {
			t.Fatal(err)
		}
		s := ""
		for i, e := range es {
			if e.Position != i {
				t.Fatalf("entry %d has position %d", i, e.Position)
			}
			s += e.Track.Title
		}
		return s
	}

	if err := db.AddTracks(ctx, pl, []int64{ids[0], ids[2]}, nil); err != nil {
		t.Fatal(err)
	}
	if err := db.AddTracks(ctx, pl, []int64{ids[1]}, ptr(1)); err != nil {
		t.Fatal(err)
	}
	if err := db.AddTracks(ctx, pl, []int64{ids[0]}, nil); err != nil { // duplicates allowed
		t.Fatal(err)
	}
	if got := order(); got != "ABCA" {
		t.Fatalf("got %s", got)
	}
	if err := db.AddTracks(ctx, pl, []int64{9999}, nil); !errors.Is(err, ErrInvalid) {
		t.Fatalf("unknown track: got %v", err)
	}

	es, _ := db.PlaylistTracks(ctx, pl)
	if err := db.MoveEntry(ctx, pl, es[3].EntryID, 0); err != nil {
		t.Fatal(err)
	}
	if got := order(); got != "AABC" {
		t.Fatalf("after move got %s", got)
	}
	es, _ = db.PlaylistTracks(ctx, pl)
	if err := db.RemoveEntry(ctx, pl, es[1].EntryID); err != nil {
		t.Fatal(err)
	}
	if got := order(); got != "ABC" {
		t.Fatalf("after remove got %s", got)
	}
	p, _ := db.Playlist(ctx, pl)
	if p.TrackCount != 3 || p.DurationMs != 3*180000 {
		t.Fatalf("aggregates: %+v", p)
	}
}

func TestFavoritesAndPlays(t *testing.T) {
	db := openTest(t)
	ctx := context.Background()
	ids := seed(t, db, TrackFile{Path: "a.flac", Title: "A", Artist: "X", Album: "Y"})

	if err := db.SetFavorite(ctx, "tracks", ids[0], true); err != nil {
		t.Fatal(err)
	}
	if err := db.SetFavorite(ctx, "tracks", ids[0], true); err != nil { // idempotent
		t.Fatal(err)
	}
	if err := db.SetFavorite(ctx, "tracks", 999, true); !errors.Is(err, ErrNotFound) {
		t.Fatalf("unknown track: got %v", err)
	}
	if err := db.SetFavorite(ctx, "nope", 1, true); !errors.Is(err, ErrInvalid) {
		t.Fatalf("bad kind: got %v", err)
	}
	favs, _ := db.FavoriteIDs(ctx)
	if len(favs["tracks"]) != 1 {
		t.Fatalf("favs %+v", favs)
	}

	n, err := db.AddPlays(ctx, 0, []Play{
		{TrackID: ids[0], StartedAt: 1000, ListenedMs: 5000, Skipped: true},
		{TrackID: 999, StartedAt: 2000, ListenedMs: 1000},
	})
	if err != nil || n != 1 {
		t.Fatalf("plays: n=%d err=%v", n, err)
	}
	recent, _ := db.RecentlyPlayed(ctx, 10)
	if len(recent) != 1 || recent[0].Kind != "album" {
		t.Fatalf("recent: %+v", recent)
	}
}

func TestRecentlyPlayed(t *testing.T) {
	db := openTest(t)
	ctx := context.Background()
	ids := seed(t, db,
		TrackFile{Path: "a.flac", Title: "A", Artist: "X", Album: "Y"},
		TrackFile{Path: "b.flac", Title: "B", Artist: "Z", Album: "W"})
	pl, _ := db.CreatePlaylist(ctx, "Chill", nil)
	gone, _ := db.CreatePlaylist(ctx, "Gone", nil)
	a, _ := db.Track(ctx, ids[0])

	if _, err := db.AddPlays(ctx, 0, []Play{
		{TrackID: ids[0], StartedAt: 1000, ListenedMs: 1000, ContextKind: "album", ContextID: a.AlbumID},
		{TrackID: ids[1], StartedAt: 2000, ListenedMs: 1000, ContextKind: "playlist", ContextID: pl},
		{TrackID: ids[0], StartedAt: 3000, ListenedMs: 1000, ContextKind: "artist", ContextID: a.ArtistID},
		{TrackID: ids[1], StartedAt: 4000, ListenedMs: 1000, ContextKind: "search"},
		{TrackID: ids[1], StartedAt: 5000, ListenedMs: 1000, ContextKind: "playlist", ContextID: gone},
		{TrackID: ids[0], StartedAt: 6000, ListenedMs: 1000, ContextKind: "album", ContextID: a.AlbumID},
	}); err != nil {
		t.Fatal(err)
	}
	if err := db.DeletePlaylist(ctx, gone); err != nil {
		t.Fatal(err)
	}

	recent, err := db.RecentlyPlayed(ctx, 10)
	if err != nil {
		t.Fatal(err)
	}
	var got []string
	for _, it := range recent {
		switch it.Kind {
		case "album":
			got = append(got, "album:"+it.Album.Title)
		case "artist":
			got = append(got, "artist:"+it.Artist.Name)
		case "playlist":
			got = append(got, "playlist:"+it.Playlist.Name)
		}
	}
	// Y again at 6000; W from search at 4000; the deleted playlist is gone.
	want := "[album:Y album:W artist:X playlist:Chill]"
	if fmt.Sprint(got) != want {
		t.Fatalf("got %v, want %s", got, want)
	}
}

func TestRecentAdditions(t *testing.T) {
	db := openTest(t)
	ctx := context.Background()
	seed(t, db,
		TrackFile{Path: "a/1.flac", Title: "A1", Artist: "Faune", Album: "Racines", TrackNo: 1},
		TrackFile{Path: "a/2.flac", Title: "A2", Artist: "Faune", Album: "Racines", TrackNo: 2},
		TrackFile{Path: "b/1.flac", Title: "B1", Artist: "Kassette", Album: "Cassette 92", TrackNo: 1})
	// Back-date everything: Racines a day ago, Cassette 92 two days ago.
	if _, err := db.w.ExecContext(ctx, `UPDATE tracks SET created_at = created_at - 86400`); err != nil {
		t.Fatal(err)
	}
	if _, err := db.w.ExecContext(ctx, `UPDATE tracks SET created_at = created_at - 86400 WHERE title = 'B1'`); err != nil {
		t.Fatal(err)
	}
	// Three more Racines tracks today: the latest batch is those three.
	seed(t, db,
		TrackFile{Path: "a/3.flac", Title: "A3", Artist: "Faune", Album: "Racines", TrackNo: 3},
		TrackFile{Path: "a/4.flac", Title: "A4", Artist: "Faune", Album: "Racines", TrackNo: 4},
		TrackFile{Path: "a/5.flac", Title: "A5", Artist: "Faune", Album: "Racines", TrackNo: 5})

	got, err := db.RecentAdditions(ctx, 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 {
		t.Fatalf("want 2 additions, got %+v", got)
	}
	if got[0].Album.Title != "Racines" || got[0].Tracks != 3 || got[0].Album.TrackCount != 5 {
		t.Fatalf("partial batch: %+v", got[0])
	}
	if got[1].Album.Title != "Cassette 92" || got[1].Tracks != 1 || got[1].Album.TrackCount != 1 {
		t.Fatalf("whole album: %+v", got[1])
	}
	if got[0].AddedAt <= got[1].AddedAt {
		t.Fatalf("order: %+v", got)
	}
}
