package scanner

import (
	"path"
	"strconv"
	"strings"
	"unicode"

	"go.senan.xyz/taglib"

	"selfstream/internal/store"
)

func readFile(abs string, f walkedFile) (*store.TrackFile, error) {
	tags, err := taglib.ReadTags(abs)
	if err != nil {
		return nil, err
	}
	props, err := taglib.ReadProperties(abs)
	if err != nil {
		return nil, err
	}
	get := func(key string) string {
		if v := tags[key]; len(v) > 0 {
			return strings.TrimSpace(v[0])
		}
		return ""
	}
	tf := &store.TrackFile{
		Path:            f.rel,
		Size:            f.size,
		Mtime:           f.mtime,
		Title:           get(taglib.Title),
		Artist:          get(taglib.Artist),
		ArtistSort:      get(taglib.ArtistSort),
		AlbumArtist:     get(taglib.AlbumArtist),
		AlbumArtistSort: get(taglib.AlbumArtistSort),
		Album:           get(taglib.Album),
		TrackNo:         leadingInt(get(taglib.TrackNumber)),
		DiscNo:          leadingInt(get(taglib.DiscNumber)),
		Year:            year(get(taglib.Date), get("ORIGINALDATE"), get("YEAR")),
		Genre:           get(taglib.Genre),
		DurationMs:      props.Length.Milliseconds(),
		Format:          strings.TrimPrefix(strings.ToLower(path.Ext(f.rel)), "."),
		Codec:           codec(props),
		Bitrate:         int(props.BitRate),
		SampleRate:      int(props.SampleRate),
		BitDepth:        int(props.BitDepth),
		Channels:        int(props.Channels),
		RGTrackGain:     gain(get("REPLAYGAIN_TRACK_GAIN")),
		RGTrackPeak:     gain(get("REPLAYGAIN_TRACK_PEAK")),
		RGAlbumGain:     gain(get("REPLAYGAIN_ALBUM_GAIN")),
		RGAlbumPeak:     gain(get("REPLAYGAIN_ALBUM_PEAK")),
		MBID:            get(taglib.MusicBrainzTrackID),
		ArtistMBID:      get(taglib.MusicBrainzArtistID),
		AlbumMBID:       get(taglib.MusicBrainzAlbumID),
		AlbumArtistMBID: get(taglib.MusicBrainzAlbumArtistID),
	}
	return tf, nil
}

func codec(p taglib.Properties) string {
	if p.InnerCodec != "" {
		return p.InnerCodec
	}
	if p.Format == "mpeg" {
		return "mp3"
	}
	return p.Format
}

// leadingInt parses "3", "03" or "3/12".
func leadingInt(s string) int {
	end := strings.IndexFunc(s, func(r rune) bool { return !unicode.IsDigit(r) })
	if end == 0 {
		return 0
	}
	if end > 0 {
		s = s[:end]
	}
	n, _ := strconv.Atoi(s)
	return n
}

// year returns the first plausible 4-digit year from the candidates.
func year(candidates ...string) int {
	for _, c := range candidates {
		if len(c) >= 4 {
			if y, err := strconv.Atoi(c[:4]); err == nil && y > 1000 && y < 3000 {
				return y
			}
		}
	}
	return 0
}

// gain parses "-6.54 dB" or "0.98765".
func gain(s string) *float64 {
	s = strings.TrimSpace(strings.TrimSuffix(strings.TrimSpace(strings.ToLower(s)), "db"))
	if s == "" {
		return nil
	}
	v, err := strconv.ParseFloat(s, 64)
	if err != nil {
		return nil
	}
	return &v
}
