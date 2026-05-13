#!/usr/bin/env bash
# worktree-detect.sh — detect whether cwd (or a given dir) is inside
# a git worktree that is NOT the main working tree.
#
# A "linked worktree" (added via `git worktree add`) has a `.git`
# FILE pointing at `<main>/.git/worktrees/<name>/`. The main working
# tree has a `.git` DIRECTORY. Compare `--show-toplevel` against
# `--git-common-dir`/`..` to distinguish.
#
# Sourceable library. API:
#   loom_is_git_worktree [DIR]           # exit 0 if linked worktree
#   loom_worktree_main_dir [DIR]         # echo main repo working tree
#                                        # (or just toplevel if main)

loom_is_git_worktree() {
  local start="${1:-$PWD}"
  local toplevel common_dir main_dir
  toplevel=$(cd "$start" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || return 1
  common_dir=$(cd "$start" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null) || return 1
  # Resolve common_dir to absolute (it can be relative to cwd).
  if [ "${common_dir#/}" = "$common_dir" ]; then
    common_dir=$(cd "$start" && cd "$common_dir" 2>/dev/null && pwd) || return 1
  fi
  main_dir=$(dirname "$common_dir")
  # If start's toplevel matches main_dir, we're in the main tree.
  [ "$toplevel" != "$main_dir" ]
}

loom_worktree_main_dir() {
  local start="${1:-$PWD}"
  local common_dir
  common_dir=$(cd "$start" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null) || return 1
  if [ "${common_dir#/}" = "$common_dir" ]; then
    common_dir=$(cd "$start" && cd "$common_dir" 2>/dev/null && pwd) || return 1
  fi
  dirname "$common_dir"
}
