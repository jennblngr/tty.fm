#!/usr/bin/env bash
# Tests for check.sh: tools/conventions/test.sh
set -u
cd "$(dirname "$0")"
unset GITHUB_ACTIONS

failures=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# expect <ok|ko> <what> <check.sh arguments...>
expect() {
  local want=$1 what=$2 got
  shift 2
  if ./check.sh "$@" 2>/dev/null; then got=ok; else got=ko; fi
  if [ "$got" != "$want" ]; then
    failures=$((failures + 1))
    echo "FAIL ($want expected): $what"
  fi
}

# message <ok|ko> <what> <message> [--allow-fixup]
message() {
  printf '%s\n' "$3" >"$tmp/msg"
  expect "$1" "$2" message "$tmp/msg" ${4:+"$4"}
}

expect ok "feat branch" branch feat/audio-analysis
expect ok "branch with an issue number" branch fix/27-previous-restarts-track
expect ok "revert branch" branch revert/shuffle-playback-gap
expect ok "perf branch" branch perf/track-list-query
expect ko "old feature/ prefix" branch feature/audio-analysis
expect ko "old bugfix/ prefix" branch bugfix/shuffle-playback-gap
expect ko "old refactoring/ prefix" branch refactoring/track-select-query
expect ko "unknown prefix" branch claude/notifications-f1903d
expect ko "uppercase in a branch" branch feat/Audio
expect ko "underscore in a branch" branch feat/audio_analysis
expect ko "trailing dash" branch docs/conventions-
expect ko "main" branch main

expect ok "type and scope" title "feat(recommender): analyse tempo, key and loudness of each track"
expect ko "missing scope" title "ci: run the recommender tests on every pull request"
expect ko "missing scope, breaking change" title "feat!: return bpm in track lists"
expect ko "empty scope" title "fix(): keep playing"
expect ok "repo scope" title "ci(repo): check commit messages on every pull request"
expect ok "several scopes" title "feat(server,app): show the bpm in track lists"
expect ko "space between scopes" title "feat(server, app): show the bpm in track lists"
expect ok "breaking change, several scopes" title "feat(server,app)!: return bpm in track lists"
expect ok "breaking change" title "feat(server)!: return bpm and camelot in track lists"
expect ok "revert" title "revert(#36): fix(app): keep playing while toggling shuffle"
expect ko "revert without the PR number" title "revert: fix(app): keep playing"
expect ko "revert with a scope instead of the PR number" title "revert(app): fix(app): keep playing"
expect ko "PR number without #" title "revert(36): fix(app): keep playing"
expect ko "revert of a revert" title "revert(#40): revert(#36): fix(app): keep playing"
expect ko "unknown type" title "feature(app): add a thing"
expect ko "unknown scope" title "fix(ui): keep playing"
expect ko "capitalised description" title "fix(app): Keep playing"
expect ko "period at the end" title "fix(app): keep playing."
expect ko "no space after the colon" title "fix(app):keep playing"
expect ko "empty description" title "fix(app): "
expect ko "GitHub merge title" title "Merge pull request #39 from jennblngr/feature/audio-analysis"
expect ko "old style title" title "CI: golangci-lint on the server"
expect ko "73 characters" title "docs(doc): $(printf 'a%.0s' $(seq 1 62))"
expect ok "72 characters" title "docs(doc): $(printf 'a%.0s' $(seq 1 61))"
expect ok "revert of a 72-character header" title "revert(#123): docs(doc): $(printf 'a%.0s' $(seq 1 61))"
expect ko "revert of a bad header" title "revert(#36): Fix stuff"
expect ko "revert of a header without scope" title "revert(#36): fix: keep playing"

message ok "header, body and footer" "fix(app): keep playing while toggling shuffle

The queue was rebuilt on every toggle.

Closes #1"
message ok "comments and scissors are ignored" "
fix(app): keep playing
# Please enter the commit message
# ------------------------ >8 ------------------------
diff --git a/x b/x"
message ko "no blank line after the header" "fix(app): keep playing
The queue was rebuilt."
message ok "revert with Refs" "revert(#36): fix(app): keep playing

It drops the queue on Android.

Refs: 1a2b3c4"
message ko "revert without Refs" "revert(#36): fix(app): keep playing

It drops the queue on Android."
message ko "git revert message" 'Revert "fix(app): keep playing"

This reverts commit 1a2b3c4d.'
message ok "breaking change with footer" "feat(server)!: return bpm in track lists

BREAKING CHANGE: track lists have a new bpm field."
message ko "breaking change without footer" "feat(server)!: return bpm in track lists"
message ok "merge commit" "Merge remote-tracking branch 'origin/main' into feat/x"
message ok "fixup allowed locally" "fixup! fix(app): keep playing" --allow-fixup
message ko "fixup refused otherwise" "fixup! fix(app): keep playing"
message ok "empty message left to git" "# only a comment"

# commits: a throwaway repository with one good and one bad commit.
repo="$tmp/repo"
git init -q "$repo"
git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "chore: start"
base=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "fix(app): keep playing"
good=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "WIP"
bad=$(git -C "$repo" rev-parse HEAD)
check=$PWD/check.sh
if ! (cd "$repo" && "$check" commits "$base" "$good" 2>/dev/null); then
  failures=$((failures + 1)); echo "FAIL (ok expected): commits, all good"
fi
if (cd "$repo" && "$check" commits "$base" "$bad" 2>/dev/null); then
  failures=$((failures + 1)); echo "FAIL (ko expected): commits, one bad"
fi

if [ $failures -gt 0 ]; then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
