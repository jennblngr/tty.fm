#!/usr/bin/env bash
# Installs the latest tty.fm release on this Mac, from the GitHub Releases of
# the repository. Does nothing if the installed version is already the latest.
#
# Uses `gh` when it is installed and logged in; otherwise the GitHub API with
# curl, which needs GITHUB_TOKEN (read-only token) when the repository is private.
#
#   tools/update-mac.sh            # or: GITHUB_TOKEN=... tools/update-mac.sh
#
# Environment: TTYFM_REPO (default jennblngr/tty.fm),
#              TTYFM_APP  (default /Applications/tty.fm.app).
set -euo pipefail

REPO="${TTYFM_REPO:-jennblngr/tty.fm}"
APP="${TTYFM_APP:-/Applications/tty.fm.app}"
APP_NAME="$(basename "$APP" .app)"
API="https://api.github.com/repos/$REPO"

die() { echo "update-mac: $*" >&2; exit 1; }
[ "$(uname)" = "Darwin" ] || die "macOS only"

# Reads a field of a JSON document on stdin, with JavaScript for Automation
# (always present on macOS, unlike jq or python3). $1 is a JS expression on `r`.
json() {
  osascript -l JavaScript -e "function run(a){var r=JSON.parse(a[0]);return String($1)}" "$(cat)"
}

use_gh=false
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then use_gh=true; fi

api() {
  local auth=()
  [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
  curl -fsSL ${auth[@]+"${auth[@]}"} -H "X-GitHub-Api-Version: 2022-11-28" "$@"
}

# Latest release.
if $use_gh; then
  release=$(gh api "repos/$REPO/releases/latest")
else
  release=$(api "$API/releases/latest") \
    || die "cannot read the latest release of $REPO (private repository? set GITHUB_TOKEN)"
fi
tag=$(echo "$release" | json 'r.tag_name')
latest="${tag#v}"

installed=""
if [ -d "$APP" ]; then
  installed=$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || true)
fi
echo "installed: ${installed:-none}, latest: $latest"
if [ "$installed" = "$latest" ]; then
  echo "tty.fm is up to date."
  exit 0
fi

# Download the macOS zip.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
if $use_gh; then
  gh release download "$tag" --repo "$REPO" --pattern '*-macos.zip' --dir "$tmp"
else
  asset_id=$(echo "$release" | json \
    '(r.assets.find(function(a){return /-macos\.zip$/.test(a.name)})||{id:""}).id')
  [ -n "$asset_id" ] || die "no macOS zip in release $tag"
  api -H "Accept: application/octet-stream" -o "$tmp/ttyfm-macos.zip" "$API/releases/assets/$asset_id"
fi
zip=$(ls "$tmp"/*.zip | head -n 1)
ditto -x -k "$zip" "$tmp/x"
new="$tmp/x/$(basename "$APP")"
[ -d "$new" ] || die "$(basename "$APP") not found in $(basename "$zip")"

# Quit the app if it is running.
if pgrep -xq "$APP_NAME"; then
  echo "quitting $APP_NAME..."
  osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
  for _ in $(seq 1 20); do pgrep -xq "$APP_NAME" || break; sleep 0.5; done
  pgrep -xq "$APP_NAME" && die "$APP_NAME is still running, quit it and try again"
fi

# Replace the app. Not signed or notarized by Apple: remove the quarantine.
rm -rf "$APP"
ditto "$new" "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "installed: $(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString)"
