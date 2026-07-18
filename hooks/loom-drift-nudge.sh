#!/usr/bin/env bash
# loom-drift-nudge.sh — SessionStart hook (loom-ig3p.3). Compares a
# managed project's STAMPED loom-convention-manifest hash against
# loom's CURRENT manifest hash; on drift, emits ONE non-blocking,
# one-time-per-session nudge pointing at `/audit-project --apply-drift`.
#
# THE PROBLEM this closes out. `scripts/loom-convention-manifest`
# (loom-ig3p.1) computes loom's CURRENT convention hash over its
# `templates/` tree. `scripts/loom-sync-stamp` (loom-ig3p.2) writes a
# managed project's `.claude/.loom-sync` recording the hash as of the
# last sync. Neither alone detects drift — nothing compared the two.
# THIS hook is the detector: on every SessionStart it reads the
# project's stamp, recomputes loom's current hash, and nudges when
# they differ.
#
# GENERALIZES loom-1lj (constitution-enforce.sh's tooling age-skew
# nudge): same shape — one-time-per-session, non-blocking, INFO-only
# stderr line — applied to convention-manifest drift instead of
# constitution-file mtime skew. Mirrors that hook's session-sentinel
# mechanism verbatim (see below).
#
# NUDGE, NOT GATE (loom-yb5). This hook ALWAYS exits 0. A drifted
# project must never be blocked from starting a session over this —
# contrast the correctness GATES elsewhere in the loom-ig3p epic
# (loom-ig3p.5), which DO fail on a real violation. Drift is an
# ATTENDED decision (does the user want to resync now?), not a
# correctness invariant.
#
# OPT-IN GUARD. Only nudges a project that carries a
# `.claude/.loom-sync` stamp — i.e. has synced against loom at least
# once (via install.sh or `/audit-project`). No stamp → the project is
# either not loom-managed or has never synced → SILENT no-op. Mirrors
# constitution-enforce.sh's "absent constitution → exit 0 silent"
# posture (most projects don't carry loom state at all).
#
# ONE-TIME-PER-SESSION. `SessionStart` fires on fresh start, resume,
# AND `/clear` (see docs/reference/claude-code-hook-semantics.md) — not
# just once at process boot — so a naive "always nudge on drift" would
# repeat across every `/clear` in one sitting. Reuses the loom-1lj
# age-skew nudge's sentinel: a marker file under $XDG_RUNTIME_DIR
# (falling back to $TMPDIR/tmp), keyed on a hash of the managed
# project's `.claude/.loom-sync` path. $XDG_RUNTIME_DIR is
# per-login-session and cleared on logout, so the sentinel naturally
# scopes "once per session" the same way constitution-enforce.sh's
# age-skew sentinel does.
#
# HASH COMPUTATION — why this hook resolves its OWN real path first.
# `scripts/loom-convention-manifest`'s root-resolution
# (`dirname "${BASH_SOURCE[0]}"`) breaks when invoked via the
# `~/.claude/scripts/` symlink install.sh creates: BASH_SOURCE reflects
# the INVOCATION path, not the symlink target, so `--root` would
# resolve to `~/.claude` (where `templates/` doesn't exist) instead of
# the real loom checkout. This hook resolves ITS OWN real path via
# `readlink -f` first (the same idiom constitution-enforce.sh uses to
# find `lib/loom-hook-helpers.sh`), derives loom's checkout root from
# that, and passes `--root` explicitly.
#
# Bypass: LOOM_DRIFT_NUDGE_SKIP=1 (literal-"1" only, per loom-b1l).
#
# Test injection points (mirrors LOOM_TEST_LIB_DIR elsewhere):
#   LOOM_TEST_LIB_DIR — override for lib/ helper resolution.
#   LOOM_TEST_ROOT    — override for "loom's own checkout root" used to
#                       compute the CURRENT manifest hash. Points the
#                       comparison at an isolated fixture tree instead
#                       of this hook's real symlink target, so tests
#                       never read/hash the real repo's templates/.
#
# settings.snippet.json wires this into the SessionStart hook group
# alongside workflow-mode-onboarding.sh / bd-prime-wrapper.sh /
# pytest-tempdir-prune.sh.
#
# Run:  bash hooks/loom-drift-nudge.sh <<<'{}'
#       bash lib/tests/loom-drift-nudge.test.sh

set -uo pipefail

# --- Source shared helpers (loom_env_enabled) ---------------------------
# shellcheck source=../lib/loom-hook-helpers.sh
if [ -n "${LOOM_TEST_LIB_DIR:-}" ] && [ -f "$LOOM_TEST_LIB_DIR/loom-hook-helpers.sh" ]; then
  . "$LOOM_TEST_LIB_DIR/loom-hook-helpers.sh"
elif [ -f "$HOME/.claude/lib/loom-hook-helpers.sh" ]; then
  . "$HOME/.claude/lib/loom-hook-helpers.sh"
else
  . "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/loom-hook-helpers.sh"
fi

# 1. Always-bypass.
if loom_env_enabled LOOM_DRIFT_NUDGE_SKIP; then
  exit 0
fi

INPUT=$(cat 2>/dev/null || true)

# 2. Subagent (sidechain) sessions skip silently — same rationale as
#    the sibling SessionStart hooks (loom-w58 / loom-nsb / loom-b1l):
#    the dispatch brief carries the intent, and this preamble would
#    just be dead weight re-billed every turn.
# shellcheck source=../lib/subagent-detect.sh
if [ -n "${LOOM_TEST_LIB_DIR:-}" ] && [ -f "$LOOM_TEST_LIB_DIR/subagent-detect.sh" ]; then
  . "$LOOM_TEST_LIB_DIR/subagent-detect.sh"
elif [ -f "$HOME/.claude/lib/subagent-detect.sh" ]; then
  . "$HOME/.claude/lib/subagent-detect.sh"
else
  . "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/subagent-detect.sh"
fi
if declare -F loom_is_subagent_payload >/dev/null 2>&1; then
  loom_is_subagent_payload "$INPUT" && exit 0
fi

# 3. Determine the managed-project directory. Mirrors
#    workflow-mode-onboarding.sh's `.cwd` extraction with a $PWD
#    fallback (SessionStart payloads carry `.cwd`; a jq-less host or a
#    malformed/empty payload falls back to the process cwd).
CWD=""
if [ -n "$INPUT" ] && command -v jq >/dev/null 2>&1; then
  CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null || true)
fi
CWD="${CWD:-$PWD}"

STAMP="$CWD/.claude/.loom-sync"

# 4. OPT-IN GUARD: no stamp → not loom-synced (or not loom-managed at
#    all) → SILENT no-op. Never nudge a project that hasn't opted in.
[ -f "$STAMP" ] || exit 0

STAMPED_HASH=$(grep '^hash=' "$STAMP" 2>/dev/null | head -1 | cut -d= -f2-)
STAMPED_DATE=$(grep '^date=' "$STAMP" 2>/dev/null | head -1 | cut -d= -f2-)
# A stamp file with no parseable hash= line is malformed — fail open
# silent rather than guess.
[ -n "$STAMPED_HASH" ] || exit 0

# 5. Resolve loom's own checkout root, then compute the CURRENT
#    manifest hash against it (see HASH COMPUTATION header note).
if [ -n "${LOOM_TEST_ROOT:-}" ]; then
  LOOM_SELF_ROOT="$LOOM_TEST_ROOT"
else
  LOOM_SELF_ROOT="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"
fi

MANIFEST_BIN="$LOOM_SELF_ROOT/scripts/loom-convention-manifest"
# Can't compute the current hash (missing/non-executable manifest
# script) → fail open silent; never guess at drift.
[ -x "$MANIFEST_BIN" ] || exit 0

CURRENT_HASH=$("$MANIFEST_BIN" --root "$LOOM_SELF_ROOT" 2>/dev/null) || exit 0
[ -n "$CURRENT_HASH" ] || exit 0

# 6. Compare. Matching hash → in sync → silent no-op.
[ "$STAMPED_HASH" = "$CURRENT_HASH" ] && exit 0

# 7. ONE-TIME-PER-SESSION sentinel (mirrors constitution-enforce.sh's
#    loom-1lj age-skew nudge exactly). Keyed on the STAMP path so
#    distinct managed projects in the same session each get their own
#    one-shot nudge slot.
SENTINEL_BASE="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"
if command -v sha256sum >/dev/null 2>&1; then
  SENTINEL_KEY=$(printf '%s' "$STAMP" | sha256sum | cut -d' ' -f1)
else
  SENTINEL_KEY=$(printf '%s' "$STAMP" | cksum | tr -d ' ')
fi
SENTINEL="$SENTINEL_BASE/loom-drift-nudge-$SENTINEL_KEY"
[ -e "$SENTINEL" ] && exit 0   # already nudged this session

# 8. Emit the nudge — a single concise stderr line (D4 loudness:
#    proportional/non-blocking). Names the drift (stamped vs current
#    hash, short form) and points at the fix command.
echo "[loom-drift-nudge] INFO: this project's loom-convention stamp (hash=${STAMPED_HASH:0:12}..., synced ${STAMPED_DATE:-unknown}) is behind loom's current conventions (hash=${CURRENT_HASH:0:12}...) — run \`/audit-project --apply-drift\` to resync." >&2

# Best-effort one-shot: a write failure is non-fatal (we'd just nudge
# again next call — degrades to the pre-sentinel behavior, not a
# crash).
: >"$SENTINEL" 2>/dev/null || true

exit 0
