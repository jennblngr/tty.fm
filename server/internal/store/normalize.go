package store

import (
	"strings"
	"unicode"

	"golang.org/x/text/runes"
	"golang.org/x/text/transform"
	"golang.org/x/text/unicode/norm"
)

var stripMarks = transform.Chain(norm.NFD, runes.Remove(runes.In(unicode.Mn)), norm.NFC)

// MatchKey normalises a name for de-duplication: lower case, no accents,
// collapsed whitespace. "Beyoncé " and "beyonce" share a key.
func MatchKey(s string) string {
	out, _, err := transform.String(stripMarks, s)
	if err != nil {
		out = s
	}
	return strings.Join(strings.Fields(strings.ToLower(out)), " ")
}

// SortName derives a sort key: explicit sort tag if given, otherwise the name
// without a leading article.
func SortName(name, sortTag string) string {
	if sortTag != "" {
		return sortTag
	}
	lower := strings.ToLower(name)
	for _, art := range []string{"the ", "les ", "le ", "la ", "l'"} {
		if strings.HasPrefix(lower, art) && len(name) > len(art) {
			return strings.TrimSpace(name[len(art):])
		}
	}
	return name
}
