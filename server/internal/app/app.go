// Package app holds the application identity: Title is the product name,
// Name the technical identifier (binary, database file, env prefix).
package app

const (
	// Title is the product name, used in logs and headers.
	Title = "tty.fm"
	// Name is the technical identifier, used for defaults such as the database file.
	Name = "ttyfm"
	// LegacyName is the former technical identifier; its database is renamed on start.
	LegacyName = "selfstream"
	// EnvPrefix is prepended to every configuration environment variable.
	EnvPrefix = "TTYFM_"
	// APIVersion is the current REST API version segment.
	APIVersion = "v1"
)

// Version is overridden at build time with -ldflags "-X .../app.Version=...".
var Version = "dev"
