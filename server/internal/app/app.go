// Package app holds the application identity. The product name is a working
// title: change it here (and in .env / app/lib/app_info.dart) to rename.
package app

const (
	// Name is the application name, used in logs, headers and defaults.
	Name = "selfstream"
	// EnvPrefix is prepended to every configuration environment variable.
	EnvPrefix = "SELFSTREAM_"
	// APIVersion is the current REST API version segment.
	APIVersion = "v1"
)

// Version is overridden at build time with -ldflags "-X .../app.Version=...".
var Version = "dev"
