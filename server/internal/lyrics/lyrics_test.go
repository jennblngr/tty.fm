package lyrics

import (
	"os"
	"path/filepath"
	"testing"
)

func TestParseLRC(t *testing.T) {
	l := Parse("\ufeff[ar:Adele]\n[ti:Hello]\n[offset:+200]\n[00:12.5]Hello\n[00:10.00][01:02.250]It's me\n\n[00:20.123] I was wondering\n")
	if !l.Synced {
		t.Fatal("want synced")
	}
	want := []Line{{0 + 10000 - 200, "It's me"}, {12500 - 200, "Hello"}, {20123 - 200, "I was wondering"}, {62250 - 200, "It's me"}}
	if len(l.Lines) != len(want) {
		t.Fatalf("lines: %+v", l.Lines)
	}
	for i, w := range want {
		if l.Lines[i] != w {
			t.Fatalf("line %d: got %+v, want %+v", i, l.Lines[i], w)
		}
	}
}

func TestParsePlain(t *testing.T) {
	l := Parse("\n\nFirst verse\nsecond line\n\nChorus\n\n")
	if l.Synced || len(l.Lines) != 4 || l.Lines[0].Text != "First verse" || l.Lines[2].Text != "" {
		t.Fatalf("plain: %+v", l)
	}
}

func TestFindSidecar(t *testing.T) {
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, "A"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "A", "01 Song.flac"), []byte("not audio"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := New(root).Find("A/01 Song.flac"); err != ErrNone {
		t.Fatalf("no lyrics: err=%v", err)
	}
	if err := os.WriteFile(filepath.Join(root, "A", "01 Song.txt"), []byte("la la"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "A", "01 Song.lrc"), []byte("[00:01.00]la"), 0o644); err != nil {
		t.Fatal(err)
	}
	l, err := New(root).Find("A/01 Song.flac")
	if err != nil || l.Source != "lrc" || !l.Synced || l.Lines[0].Ms != 1000 {
		t.Fatalf("lrc preferred: %+v %v", l, err)
	}
}
