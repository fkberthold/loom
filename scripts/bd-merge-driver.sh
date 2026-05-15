#!/usr/bin/env bash
# bd-merge-driver — custom git merge driver for .beads/issues.jsonl.
#
# Closes loom-4um: git's line-based three-way merge of
# .beads/issues.jsonl can SILENTLY reconcile bead-state lines across
# semantic boundaries when a feature branch based on stale main is
# merged into post-newer-work main. The `--ours` conflict pattern
# only fires on textual conflicts; auto-merges look successful but
# revert closed beads to in_progress (etc.) because the JSONL rows
# happen to line up.
#
# Structural fix: bypass git's line-merge entirely for this file.
# Git invokes a merge driver as:
#     <driver> %O %A %B %P
#   %O = ancestor's version
#   %A = current branch's version (must be overwritten with the result)
#   %B = other branch's version
#   %P = pathname being merged
#
# This driver runs `bd export` from the repo toplevel — that's the
# canonical resolver established in Wave-1 close-out (loom/decisions
# 2026-05-04) and reused across the codebase. The dolt store IS the
# authoritative source of truth; the exported JSONL is just a view.
# Whatever git's line-merge produced, the dolt knows the real state.
#
# Wired via .gitattributes (`.beads/issues.jsonl merge=bd-export`)
# and `git config merge.bd-export.driver` (set by install.sh).
#
# Failure semantics:
#   * If `bd export` fails, the driver exits non-zero. Git treats
#     that as a merge conflict and stops with the file unchanged,
#     surfacing the failure to the user (the safer choice — silent
#     overwrite of %A with garbage on failure would re-introduce the
#     class of bug we're closing).
#   * If `bd export` produces output that doesn't parse as JSONL
#     (one object per line), the driver exits non-zero. Same
#     rationale.
#
# Composes with bd-worktree-preseed (loom-x4m): the preseed hook
# populates the worktree's dolt from .beads/issues.jsonl on the first
# write-class bd call. That ensures `bd export` in the worktree
# returns the full state, not just the worktree's local edits. The
# preseed fires on bd Bash tool-calls; this driver fires on
# `git merge`. They are orthogonal and don't share state.

set -uo pipefail

# Args.
if [ "$#" -lt 4 ]; then
  echo "bd-merge-driver: usage: $0 %O %A %B %P" >&2
  exit 2
fi

# We intentionally ignore %O and %B — bd is the source of truth, and
# both sides of the merge derive from it. We only need %A (the file
# we write the result into) and %P (informational, for error logs).
# Names them for documentation rather than usage so the shape of the
# git-merge-driver contract is legible from the script.
# shellcheck disable=SC2034
ANCESTOR="$1"
CURRENT="$2"
# shellcheck disable=SC2034
OTHER="$3"
# shellcheck disable=SC2034
PATHNAME="$4"

BD_BIN="${BD_BIN:-bd}"

# Resolve repo toplevel so `bd export` runs in the right place. Git
# invokes merge drivers from the worktree root, but be explicit so
# this works correctly even when called from subdirs in tests.
TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null) || TOPLEVEL="$(pwd)"

# Capture bd export into a temp file. If it fails, leave %A untouched
# so the caller sees a partial state rather than empty.
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

if ! (cd "$TOPLEVEL" && "$BD_BIN" export > "$TMP" 2>/dev/null); then
  echo "bd-merge-driver: bd export failed in $TOPLEVEL; leaving %A unchanged so the conflict surfaces" >&2
  exit 1
fi

# Validate JSONL — one JSON object per non-empty line.
# python3 is widely available in this repo's environment per CLAUDE.md.
if ! python3 - "$TMP" <<'PY' 2>/dev/null
import json, sys
with open(sys.argv[1]) as f:
    for i, line in enumerate(f, 1):
        s = line.strip()
        if not s:
            continue
        try:
            obj = json.loads(s)
        except Exception as e:
            print(f"line {i}: {e}", file=sys.stderr)
            sys.exit(1)
        if not isinstance(obj, dict):
            print(f"line {i}: not a JSON object", file=sys.stderr)
            sys.exit(1)
sys.exit(0)
PY
then
  echo "bd-merge-driver: bd export produced malformed JSONL; refusing to overwrite %A" >&2
  exit 1
fi

# Overwrite %A with the canonical export. Use cat redirect rather
# than mv so we preserve %A's inode (git uses it after we return).
cat "$TMP" > "$CURRENT"

exit 0
