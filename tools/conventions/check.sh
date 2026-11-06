#!/usr/bin/env bash
# Checks branch names, pull request titles and commit messages against
# doc/conventions.md. Used by .github/workflows/conventions.yml and by the
# git hooks in tools/git-hooks.
#
#   check.sh branch <name>
#   check.sh title <text>
#   check.sh message <file> [--allow-fixup]   (commit-msg hook)
#   check.sh commits <base> <head>            (every non-merge commit in base..head)
#
# Exits with 1 and lists every problem found. Written for bash 3.2 (macOS).
set -u

TYPES='feat|fix|refactor|chore|docs|test|ci|build|perf|style'
# A branch is named after the type of its change: feat/..., fix/..., revert/...
PREFIXES="$TYPES|revert"
SCOPES='server|app|recommender|design|doc|repo'
MAX_HEADER=72

errors=0

fail() {
  errors=$((errors + 1))
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "::error::$1"
  else
    echo "✗ $1" >&2
  fi
}

check_branch() {
  local re="^($PREFIXES)/[a-z0-9]+(-[a-z0-9]+)*$"
  if ! [[ $1 =~ $re ]]; then
    fail "branch \"$1\": expected <prefix>/<lowercase-words-with-dashes>, prefix one of ${PREFIXES//|/, }"
  fi
}

# check_header <header> <where>: "<type>(<scope>[,<scope>...])!: <description>",
# the scope being required, or
# "revert(#<PR number>): <header of the reverted commit>".
check_header() {
  local header=$1 where=$2
  if [[ $header =~ ^revert ]]; then
    if ! [[ $header =~ ^revert\(#[0-9]+\):\ (.*)$ ]]; then
      fail "$where: \"$header\": expected revert(#<PR number>): <header of the reverted commit>"
      return
    fi
    local inner=${BASH_REMATCH[1]}
    if [[ $inner =~ ^revert ]]; then
      fail "$where: \"$header\": to undo a revert, revert the original commit's change again, not revert(#n): revert(#n):"
      return
    fi
    check_header "$inner" "$where (reverted header)"
    return
  fi
  local re="^($TYPES)\(($SCOPES)(,($SCOPES))*\)!?: (.*)$"
  if ! [[ $header =~ $re ]]; then
    if [[ $header =~ ^($TYPES)!?: ]]; then
      fail "$where: \"$header\": the scope is required: <type>(<scope>): <description>, scope one of ${SCOPES//|/, }"
    else
      fail "$where: \"$header\": expected <type>(<scope>): <description>, type one of ${TYPES//|/, } (or revert(#<PR number>):), scope one of ${SCOPES//|/, }"
    fi
    return
  fi
  local desc=${BASH_REMATCH[5]}
  if [ -z "$desc" ] || [[ $desc =~ ^[[:space:]] ]]; then
    fail "$where: \"$header\": the description is missing"
  elif [[ $desc =~ ^[[:upper:]] ]]; then
    fail "$where: \"$header\": start the description with a lowercase letter"
  fi
  if [[ $desc == *. ]]; then
    fail "$where: \"$header\": no period at the end of the description"
  fi
  if [ ${#header} -gt $MAX_HEADER ]; then
    fail "$where: \"$header\": ${#header} characters, $MAX_HEADER at most"
  fi
}

# check_message <message> <where> <allow-fixup: yes|no>
check_message() {
  local msg=$1 where=$2 allow_fixup=$3
  local header line2
  header=$(printf '%s\n' "$msg" | sed -n 1p)
  line2=$(printf '%s\n' "$msg" | sed -n 2p)

  case $header in
    "Merge "*) return ;; # merges are not checked: the PR title is
    "fixup! "* | "squash! "* | "amend! "*)
      if [ "$allow_fixup" = no ]; then
        fail "$where: \"$header\": squash it into the commit it fixes (git rebase -i --autosquash origin/main)"
      fi
      return
      ;;
    'Revert "'*)
      fail "$where: \"$header\": write revert(#<PR number>): <reverted header>, with Refs: <sha>"
      return
      ;;
  esac

  check_header "$header" "$where"
  if [ -n "$line2" ]; then
    fail "$where: leave a blank line between the header and the body"
  fi
  if [[ $header =~ ^revert\( ]] && ! printf '%s\n' "$msg" | grep -Eq '^Refs: [0-9a-f]{7,64}$'; then
    fail "$where: a revert needs a Refs: <sha of the reverted commit> footer"
  fi
  if [[ $header =~ ^[a-z]+\([a-z,]+\)!: ]] && ! printf '%s\n' "$msg" | grep -Eq '^BREAKING CHANGE: .+'; then
    fail "$where: a breaking change (!) needs a BREAKING CHANGE: <what breaks> footer"
  fi
}

# Drops the comments git leaves in the message file, and everything below
# the scissors line of git commit --verbose, then leading blank lines.
read_message_file() {
  awk '
    /^# -+ >8 -+$/ { exit }
    /^#/ { next }
    !started && /^[[:space:]]*$/ { next }
    { started = 1; print }
  ' "$1"
}

check_commits() {
  local base=$1 head=$2 shas sha
  if ! shas=$(git rev-list --no-merges --reverse "$base..$head"); then
    fail "cannot list the commits in $base..$head"
    return
  fi
  for sha in $shas; do
    check_message "$(git log -1 --format=%B "$sha")" "commit $(git rev-parse --short "$sha")" no
  done
}

usage() {
  sed -n '6,9p' "$0" | sed 's/^# *//' >&2
  exit 2
}

[ $# -ge 2 ] || usage
case $1 in
  branch) check_branch "$2" ;;
  title) check_header "$2" "PR title" ;;
  message)
    allow=no
    [ "${3:-}" = --allow-fixup ] && allow=yes
    msg=$(read_message_file "$2")
    # An empty message: git aborts the commit itself, with its own message.
    [ -n "$msg" ] && check_message "$msg" "commit message" "$allow"
    ;;
  commits)
    [ $# -eq 3 ] || usage
    check_commits "$2" "$3"
    ;;
  *) usage ;;
esac

if [ $errors -gt 0 ]; then
  echo "See doc/conventions.md." >&2
  exit 1
fi
