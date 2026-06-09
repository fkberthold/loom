#!/usr/bin/env bash
# post-rewrite — restore .beads/issues.jsonl from dolt after a git
# history rewrite (rebase, commit --amend).
#
# Closes loom-yjo (follow-up to loom-4um): git rebase — especially
# `git pull --rebase=merges` — can land stale `.beads/issues.jsonl`
# in HEAD even though dolt (authoritative) has the correct state.
# The loom-4um merge driver covers `git merge` but the rebase-replay
# path can still leak past it (observed N=4 across 2026-05-25 →
# 2026-05-26: commits 3691069, db8fc74, 766f69f, c8ebc6b). The
# canonical workaround was a hand-typed `bd export > .beads/
# issues.jsonl && git add && git commit -m 'bd: post-rebase
# re-export'` — this hook automates that, scoped to the operations
# git defines for the `post-rewrite` event.
#
# Composes orthogonally with bd-merge-driver (loom-4um) and bd-
# worktree-preseed (loom-x4m). Dolt is the source of truth across
# all three.
#
# Invocation: git invokes the hook as `post-rewrite <command>`,
# where <command> is `rebase` or `amend`. Stdin carries a list of
# `<old-sha> <new-sha>` lines we do not consume — re-exporting from
# dolt makes whichever SHAs got rewritten irrelevant; we just align
# jsonl to dolt.
#
# Skip when:
#   * LOOM_BD_POST_REWRITE_SKIP=1 — explicit opt-out.
#   * Not inside a git work tree.
#   * `.beads/` directory absent — not a bd workspace.
#   * `bd` binary unavailable — don't break non-loom repos.
#   * HEAD detached — can't safely create a follow-up commit.
#   * Other staged changes present — would entangle them in the
#     auto-commit.
#
# When jsonl already matches dolt, hook exits 0 without committing.
#
# Bypass flags for tests + manual recovery:
#   LOOM_BD_POST_REWRITE_SKIP=1     — full no-op
#   LOOM_BD_POST_REWRITE_NO_COMMIT=1 — re-export the working tree
#                                       but skip the commit
#
# Wired via install.sh into $GIT_COMMON_DIR/hooks/post-rewrite as a
# symlink (mirrors hooks/pre-push-mkdocs-strict.sh wiring, loom-kbo
# pattern). Downstream loom-managed projects opt in via
# /audit-project.

set -uo pipefail

# shellcheck source=../lib/loom-hook-helpers.sh
. "$HOME/.claude/lib/loom-hook-helpers.sh" 2>/dev/null || \
  . "$(dirname "${BASH_SOURCE[0]}")/../lib/loom-hook-helpers.sh"

loom_env_enabled LOOM_BD_POST_REWRITE_SKIP && exit 0

# Drain stdin (git pipes <old> <new> pairs). We don't use it.
cat >/dev/null 2>&1 || true

# Resolve toplevel; degrade to no-op outside a git work tree.
TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$TOPLEVEL" || exit 0

# Not a bd workspace? No-op.
[ -d .beads ] || exit 0

# bd unavailable? No-op (don't break non-loom-managed projects).
BD_BIN="${BD_BIN:-bd}"
export BD_BIN
command -v "$BD_BIN" >/dev/null 2>&1 || exit 0

# Canonical-export wrapper (loom-0ahj.1): byte-stable `bd export` that
# sorts the `_type:memory` lines into a stable order. Without it the
# hook would rewrite .beads/issues.jsonl on every rebase whenever bd's
# randomized map iteration flipped the memory-line order (loom-n1sk).
CANON_EXPORT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/bd-canonical-export.sh"

# Detached HEAD? Can't safely create a follow-up commit.
git symbolic-ref -q HEAD >/dev/null 2>&1 || exit 0

# Other staged changes present? Would entangle them in the auto-commit.
if [ -n "$(git diff --cached --name-only 2>/dev/null)" ]; then
  exit 0
fi

# Re-export from dolt (canonical). On failure, no-op — surface in
# stderr for debuggability but don't break the user's git operation.
TMP=$(mktemp) || exit 0
trap 'rm -f "$TMP"' EXIT
if ! bash "$CANON_EXPORT" > "$TMP" 2>/dev/null; then
  exit 0
fi

# If unchanged from current jsonl, no-op.
if [ -f .beads/issues.jsonl ] && cmp -s "$TMP" .beads/issues.jsonl; then
  exit 0
fi

# Write the canonical state into the working tree.
cat "$TMP" > .beads/issues.jsonl

# NO_COMMIT bypass: leave working tree dirty, let the caller commit.
loom_env_enabled LOOM_BD_POST_REWRITE_NO_COMMIT && exit 0

# Stage + commit. core.hooksPath=/dev/null bypasses the bd pre-commit
# hook (which would re-export from dolt — already canonical — and
# auto-stage, recursing through this same hook chain). This commit is
# a no-op from bd's perspective: jsonl already matches dolt.
git add .beads/issues.jsonl
git -c core.hooksPath=/dev/null commit --quiet \
  -m "bd: post-rewrite re-export from dolt (loom-yjo)" \
  -m "Auto-committed by hooks/post-rewrite.sh after rebase/amend left .beads/issues.jsonl out of sync with the authoritative dolt store. Composes with bd-merge-driver (loom-4um) covering git merge." || true

exit 0
