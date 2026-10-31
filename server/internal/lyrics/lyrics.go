// Package lyrics finds the lyrics of a track: a sidecar file next to it
// (song.lrc, then song.txt) or lyrics embedded in its tags. LRC timestamps
// make them "synced" (one start time per line).
package lyrics

import (
	"errors"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"go.senan.xyz/taglib"
)

// ErrNone means the track has no lyrics.
var ErrNone = errors.New("no lyrics")

type Line struct {
	Ms   int64  `json:"ms"` // start time; 0 for unsynced lyrics
	Text string `json:"text"`
}

type Lyrics struct {
	Synced bool   `json:"synced"`
	Source string `json:"source"` // lrc | txt | tag
	Lines  []Line `json:"lines"`
}

type Finder struct {
	root string
}

func New(root string) *Finder { return &Finder{root: root} }

// Find returns the lyrics for the file at relPath (relative to the music root).
func (f *Finder) Find(relPath string) (Lyrics, error) {
	abs := filepath.Join(f.root, filepath.FromSlash(relPath))
	base := strings.TrimSuffix(abs, filepath.Ext(abs))
	for _, ext := range []string{".lrc", ".LRC", ".txt", ".TXT"} {
		b, err := os.ReadFile(base + ext)
		if err != nil {
			continue
		}
		l := Parse(string(b))
		if len(l.Lines) == 0 {
			continue
		}
		l.Source = strings.ToLower(ext[1:])
		return l, nil
	}
	tags, err := taglib.ReadTags(abs)
	if err != nil {
		return Lyrics{}, ErrNone
	}
	for _, key := range []string{taglib.Lyrics, "SYNCEDLYRICS", "UNSYNCEDLYRICS", "UNSYNCED LYRICS"} {
		if v := tags[key]; len(v) > 0 && strings.TrimSpace(v[0]) != "" {
			l := Parse(v[0])
			if len(l.Lines) > 0 {
				l.Source = "tag"
				return l, nil
			}
		}
	}
	return Lyrics{}, ErrNone
}

var (
	timeTag   = regexp.MustCompile(`\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]`)
	metaTag   = regexp.MustCompile(`^\[[a-zA-Z#]+:.*\]$`)
	offsetTag = regexp.MustCompile(`(?i)^\[offset:\s*([+-]?\d+)\s*\]$`)
)

// Parse reads LRC (timed) or plain text lyrics. A line may carry several
// time tags ("[00:12.00][01:30.50]chorus"); [offset:ms] shifts every line.
func Parse(s string) Lyrics {
	s = strings.TrimPrefix(s, "\ufeff")
	var lines []Line
	var plain []Line
	var offset int64
	synced := false
	for _, raw := range strings.Split(strings.ReplaceAll(s, "\r\n", "\n"), "\n") {
		raw = strings.TrimSpace(raw)
		if m := offsetTag.FindStringSubmatch(raw); m != nil {
			offset, _ = strconv.ParseInt(m[1], 10, 64)
			continue
		}
		tags := timeTag.FindAllStringSubmatchIndex(raw, -1)
		if len(tags) == 0 || tags[0][0] != 0 {
			if metaTag.MatchString(raw) {
				continue
			}
			plain = append(plain, Line{Text: raw})
			continue
		}
		synced = true
		end := 0
		var times []int64
		for _, t := range tags {
			if t[0] != end { // time tags must be contiguous at the start
				break
			}
			end = t[1]
			min, _ := strconv.ParseInt(raw[t[2]:t[3]], 10, 64)
			sec, _ := strconv.ParseInt(raw[t[4]:t[5]], 10, 64)
			var frac int64
			if t[6] >= 0 {
				digits := raw[t[6]:t[7]]
				frac, _ = strconv.ParseInt(digits, 10, 64)
				switch len(digits) { // .5 → 500 ms, .50 → 500 ms, .500 → 500 ms
				case 1:
					frac *= 100
				case 2:
					frac *= 10
				}
			}
			times = append(times, min*60000+sec*1000+frac)
		}
		text := strings.TrimSpace(raw[end:])
		for _, ms := range times {
			lines = append(lines, Line{Ms: ms, Text: text})
		}
	}
	if !synced {
		// Trim leading/trailing blank lines, keep inner ones (verse breaks).
		for len(plain) > 0 && plain[0].Text == "" {
			plain = plain[1:]
		}
		for len(plain) > 0 && plain[len(plain)-1].Text == "" {
			plain = plain[:len(plain)-1]
		}
		return Lyrics{Lines: plain}
	}
	for i := range lines {
		lines[i].Ms = max(0, lines[i].Ms-offset) // positive offset = lyrics come earlier
	}
	sort.SliceStable(lines, func(i, j int) bool { return lines[i].Ms < lines[j].Ms })
	return Lyrics{Synced: true, Lines: lines}
}
