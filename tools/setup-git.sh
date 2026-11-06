#!/bin/sh
# Sets up this clone for doc/conventions.md: the commit message template
# (.gitmessage) and the hooks in tools/git-hooks, which run the same checks
# as the CI. Once per clone: tools/setup-git.sh
# To undo: git config --unset commit.template; git config --unset core.hooksPath
set -e
cd "$(git rev-parse --show-toplevel)"

# core.hooksPath replaces .git/hooks: say so if hooks were installed there.
hooks_dir=$(git rev-parse --git-common-dir)/hooks
for hook in "$hooks_dir"/*; do
  case $hook in *.sample | "$hooks_dir/*") continue ;; esac
  echo "warning: $hook will no longer run (core.hooksPath now points to tools/git-hooks)" >&2
done

git config commit.template .gitmessage
git config core.hooksPath tools/git-hooks
echo "commit.template = .gitmessage"
echo "core.hooksPath  = tools/git-hooks (commit-msg, pre-push)"
