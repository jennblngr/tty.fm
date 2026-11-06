package store

import (
	"context"
	"errors"
	"testing"
)

func TestHiddenTracks(t *testing.T) {
	db := openTest(t)
	ctx := context.Background()
	ids := seed(t, db,
		TrackFile{Path: "a.flac", Title: "A", Artist: "X", Album: "Y"},
		TrackFile{Path: "b.flac", Title: "B", Artist: "X", Album: "Y"})

	for range 2 { // idempotent
		if err := db.SetHidden(ctx, ids[1], true); err != nil {
			t.Fatal(err)
		}
	}
	if err := db.SetHidden(ctx, 999, true); !errors.Is(err, ErrNotFound) {
		t.Fatalf("unknown track: got %v", err)
	}
	got, err := db.HiddenTrackIDs(ctx)
	if err != nil || len(got) != 1 || got[0] != ids[1] {
		t.Fatalf("hidden: %v %v", got, err)
	}
	if err := db.SetHidden(ctx, ids[1], false); err != nil {
		t.Fatal(err)
	}
	if got, _ := db.HiddenTrackIDs(ctx); len(got) != 0 {
		t.Fatalf("after show: %v", got)
	}
}
