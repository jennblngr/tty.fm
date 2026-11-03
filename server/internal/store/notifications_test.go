package store

import (
	"context"
	"encoding/json"
	"errors"
	"slices"
	"testing"
	"time"
)

func TestNotificationsAdded(t *testing.T) {
	db := openTest(t)
	ctx := context.Background()
	user, err := db.CreateUser(ctx, "me", "x")
	if err != nil {
		t.Fatal(err)
	}
	seed(t, db,
		TrackFile{Path: "old/1.flac", Title: "O1", Artist: "Ancien", Album: "Archives"},
		TrackFile{Path: "b/1.flac", Title: "B1", Artist: "Kassette", Album: "Cassette 92"},
		TrackFile{Path: "a/1.flac", Title: "A1", Artist: "Faune", Album: "Racines", TrackNo: 1},
		TrackFile{Path: "a/2.flac", Title: "A2", Artist: "Faune", Album: "Racines", TrackNo: 2},
		TrackFile{Path: "c/1.flac", Title: "C1", Artist: "Kassette", Album: "Bande"})
	// Archives ten days ago (too old), Cassette 92 two days ago, the rest now.
	for title, days := range map[string]int{"O1": 10, "B1": 2} {
		if _, err := db.w.ExecContext(ctx, `UPDATE tracks SET created_at = created_at - ? WHERE title = ?`, days*86400, title); err != nil {
			t.Fatal(err)
		}
	}
	added := func(n Notification) AddedData {
		var d AddedData
		if err := json.Unmarshal(n.Data, &d); err != nil {
			t.Fatal(err)
		}
		return d
	}
	list := func() []Notification {
		t.Helper()
		if err := db.SyncNotifications(ctx, user, time.Now()); err != nil {
			t.Fatal(err)
		}
		ns, err := db.Notifications(ctx, user, 0)
		if err != nil {
			t.Fatal(err)
		}
		return ns
	}
	unread := func() int {
		t.Helper()
		n, err := db.UnreadNotifications(ctx, user)
		if err != nil {
			t.Fatal(err)
		}
		return n
	}

	ns := list()
	if len(ns) != 2 {
		t.Fatalf("want 2 notifications, got %+v", ns)
	}
	if d := added(ns[0]); d.Tracks != 3 || d.Albums != 2 || d.AlbumID != 0 || !slices.Equal(d.Artists, []string{"Faune", "Kassette"}) {
		t.Fatalf("today: %+v", d)
	}
	if d := added(ns[1]); d.Tracks != 1 || d.AlbumID == 0 || !slices.Equal(d.Artists, []string{"Kassette"}) {
		t.Fatalf("two days ago: %+v", d)
	}
	if len(list()) != 2 || unread() != 2 {
		t.Fatal("sync is not idempotent")
	}

	// Read, then one more Racines track: the same notification grows and
	// comes back unread.
	if err := db.MarkNotificationRead(ctx, user, ns[0].ID, true); err != nil {
		t.Fatal(err)
	}
	if unread() != 1 {
		t.Fatalf("unread after read: %d", unread())
	}
	seed(t, db, TrackFile{Path: "a/3.flac", Title: "A3", Artist: "Faune", Album: "Racines", TrackNo: 3})
	ns = list()
	if len(ns) != 2 || ns[0].Read || added(ns[0]).Tracks != 4 || unread() != 2 {
		t.Fatalf("after another track: %+v", ns)
	}

	if err := db.MarkAllNotificationsRead(ctx, user); err != nil || unread() != 0 {
		t.Fatalf("read all: %v, %d unread", err, unread())
	}
	if err := db.MarkNotificationRead(ctx, user, ns[0].ID, false); err != nil || unread() != 1 {
		t.Fatalf("unread again: %v", err)
	}
	if err := db.MarkNotificationRead(ctx, user+1, ns[0].ID, true); !errors.Is(err, ErrNotFound) {
		t.Fatalf("other user's notification: %v", err)
	}

	// Turned off: hidden, and none generated.
	if err := db.SetNotificationSettings(ctx, user, map[string]bool{"added": false}); err != nil {
		t.Fatal(err)
	}
	if ns := list(); len(ns) != 0 || unread() != 0 {
		t.Fatalf("turned off: %+v", ns)
	}
	if set, _ := db.NotificationSettings(ctx, user); set["added"] {
		t.Fatalf("settings: %+v", set)
	}
	if err := db.SetNotificationSettings(ctx, user, map[string]bool{"bogus": true}); !errors.Is(err, ErrInvalid) {
		t.Fatalf("unknown kind: %v", err)
	}
}
