#!/usr/bin/env bash
# loom-drift-nudge.sh — SessionStart hook (loom-ig3p.3, extended by
# loom-oktm). For a LOOM-MANAGED project (one carrying
# `.claude/workflow.json`), emits ONE non-blocking, one-time-per-session
# nudge pointing at `/audit-project --apply-drift` in either of two
# states: the project has NEVER synced (no `.claude/.loom-sync` stamp),
# or its STAMPED loom-convention-manifest hash is behind loom's CURRENT
# manifest hash. Silent otherwise.
#
# THE PROBLEM this closes out. `scripts/loom-convention-manifest`
# (loom-ig3p.1) computes loom's CURRENT convention hash over its
# `templates/` tree. `scripts/loom-sync-stamp` (loom-ig3p.2) writes a
# managed project's `.claude/.loom-sync` recording the hash as of the
# last sync. Neither alone detects drift — nothing compared the two.
# THIS hook is the detector: on every SessionStart it reads the
# project's stamp, recomputes loom's current hash, and nudges when
# they differ — or when the stamp is absent entirely (loom-oktm; see
# the OPT-IN GUARD note below).
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
# OPT-IN GUARD — three states, three outcomes (loom-oktm).
# LOOM-MANAGEDNESS is established by EITHER of two signals: the project
# carries `.claude/workflow.json` (the same signal session-startup step
# 1f uses for its constitution nudge), OR it carries a
# `.claude/.loom-sync` stamp (which only `/audit-project` writes, so its
# mere presence proves the project synced against loom at some point).
# Either signal alone suffices — hence `||`, not `&&`, at step 4. Given
# that:
#
#   * NEITHER signal → SILENT no-op. Never nudge a project that hasn't
#     opted into loom by either route. Mirrors constitution-enforce.sh's
#     "absent constitution → exit 0 silent" posture (most projects
#     don't carry loom state at all).
#   * `workflow.json` + NO `.claude/.loom-sync` → NEVER-SYNCED nudge.
#     `workflow.json` is REQUIRED to reach this branch: it is the only
#     managedness signal left once the stamp is known absent. This is
#     the case an earlier revision silently swallowed — it treated "no
#     stamp" as "nothing to compare" and exited quietly, so a CURRENT
#     project and a project that had never received loom's conventions
#     at all were indistinguishable. The never-synced case is the one
#     that most needs the nudge — by definition it has received nothing.
#     (Live instance: ~/repos/liza_base carried no stamp while its
#     priming drifted 26+ days.)
#   * stamp present (with OR WITHOUT `workflow.json`) → the
#     `last_synced` comparison below (stale → nudge, matching →
#     silent; no `last_synced` at all → the never-synced nudge, since
#     the loom-uh4i branch keys on that field's ABSENCE, not on the
#     stamp file's). The
#     without-`workflow.json` half of that is deliberate BACKWARD
#     COMPAT: every project that nudged before this change had a stamp,
#     and some carry no `workflow.json`; requiring both signals would
#     take previously-nudging projects silently quiet. Do NOT
#     "simplify" step 4's `||` into an `&&` — cases A/D/E/F/G in
#     lib/tests/loom-drift-nudge.test.sh pin exactly that grandfathered
#     stamped-but-no-workflow.json shape and would go red.
#
# CHECKED vs SYNCED — which field this hook compares (loom-uh4i).
# `.claude/.loom-sync` carries TWO facts, and this hook reads exactly
# one of them:
#
#   last_synced / last_synced_date   — written ONLY by an
#     `/audit-project` invocation that actually APPLIED remediation.
#     THIS is what the comparison below uses.
#   last_checked / last_checked_date — written by ANY invocation,
#     including a read-only `--check=` run. Purely informational; this
#     hook never compares it, and only reads it to tell "checked but
#     never synced" apart from a malformed stamp.
#
# THE BUG THIS CLOSES. The stamp used to carry a single `hash=`,
# rewritten unconditionally on every `/audit-project` invocation. A
# read-only `--check=drift` that applied nothing therefore stamped
# loom's CURRENT hash, this hook's comparison matched, and the nudge
# went silent — the detector could be quieted by LOOKING at it.
# Measured 2026-07-25: ~/repos/liza_base stamped 14:23:51 with a hash
# matching loom exactly, nudge silent, zero remediation applied, its
# CLAUDE.md (mtime 07-15) and .claude/rules/dispatched-agents.md
# (mtime 07-10) byte-unchanged and still missing every current
# convention.
#
# LEGACY MIGRATION. A pre-loom-uh4i stamp carries only `hash=`/`date=`.
# It is read as `last_synced`/`last_synced_date` — NOT as last_checked
# — because under the old semantics that write happened at what was
# called a sync. Grandfathering it any other way would take every
# already-stamped project from silent to nudging overnight. This is the
# same rule scripts/loom-sync-stamp applies on the write side, so no
# downstream project needs any action; its next `/audit-project` run
# rewrites the stamp in the v2 shape.
#
# TWO SIGNALS, NOT ONE (loom-5od2). The manifest-hash comparison above
# is a comparison of NUMBERS: what loom's conventions hashed to when the
# project last applied remediation, vs what they hash to now. loom-f59h
# added a structurally different second signal — a BYTE comparison of
# loom's OWNED templates (`scripts/loom-owned-templates`) against the
# project's live copies — whose entire point is that it does not consult
# the stamp: the stamp is a CLAIM ABOUT THE PAST, the bytes are a FACT
# ABOUT THE PRESENT, and the fact wins. That check previously ran only
# inside `/audit-project` step 3.3a, i.e. on manual invocation.
#
# The hole that left: per loom-uh4i, an `--apply-drift` run with N>=1
# items applied re-stamps `last_synced` at loom's FULL current hash. A
# user who applies some items and SKIPS the `loom-conventions.md` item
# therefore ends up STAMPED-CURRENT with the owned file still absent —
# and this hook stayed silent until the next convention change happened
# to move the hash. That is a smaller version of exactly the false-green
# loom-uh4i fixed, one layer along.
#
# So step 6 no longer exits on a matching hash. It falls through to the
# owned-file check, and the hook nudges if EITHER signal fires. A hash
# mismatch takes precedence (see step 6) — both conditions carry the
# same fix command, and one nudge per session is the D4 loudness budget.
#
# The four nudges are deliberately worded differently: the never-synced
# one names the ABSENT stamp and asks for a first sync; the
# checked-but-never-synced one names the check date and the missing
# last_synced record; the stale one names both hashes and asks for a
# resync; the owned-file one names the FILE and says explicitly that the
# stamp is current but the bytes disagree. Same fix command
# (`/audit-project --apply-drift`), different emphasis — a reader can
# tell which condition tripped from the nudge alone, because only the
# stale one prints hashes and only the owned-file one prints a path.
#
# The never-synced branch does NOT compute loom's current manifest hash
# — there is nothing to compare it against, and skipping it keeps the
# nudge robust even where the manifest script can't be resolved.
#
# ONE-TIME-PER-SESSION. `SessionStart` fires on fresh start, resume,
# AND `/clear` (see docs/reference/claude-code-hook-semantics.md) — not
# just once at process boot — so a naive "always nudge on drift" would
# repeat across every `/clear` in one sitting. Reuses the loom-1lj
# age-skew nudge's sentinel: a marker file under $XDG_RUNTIME_DIR
# (falling back to $TMPDIR/tmp), keyed on a hash of the payload's
# `session_id` plus the managed project's `.claude/.loom-sync` path.
#
# The session_id half of that key is what makes "once per session" true
# (loom-5sfb). The directory alone does not scope a session:
# $XDG_RUNTIME_DIR is per-LOGIN, and a desktop stays logged in for days,
# so a path-only key let one nudge cover every session until reboot. See
# the emitter's own note for the measurement and for what happens when
# session_id cannot be read.
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

# 3b. The session this payload belongs to (loom-5sfb). Read the same way
#     as `.cwd` above, and for the same reason: jq when the host has it, a
#     documented degradation when it does not. An empty value here is not
#     an error — see the sentinel-key note below.
SESSION_ID=""
if [ -n "$INPUT" ] && command -v jq >/dev/null 2>&1; then
  SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || true)
fi

STAMP="$CWD/.claude/.loom-sync"
WORKFLOW_JSON="$CWD/.claude/workflow.json"

# --- ONE-TIME-PER-SESSION emitter ---------------------------------------
# Shared by BOTH nudge modes (never-synced and stale-stamp). Mirrors
# constitution-enforce.sh's loom-1lj age-skew nudge. Keyed on the SESSION
# plus the STAMP path — present or not — so distinct managed projects in
# one session each get their own one-shot slot, and a new session gets a
# fresh one.
#
# WHY THE SESSION IS IN THE KEY (loom-5sfb). The sentinel used to be keyed
# on the STAMP path alone, and the directory holding it was read as the
# session's own lifetime. $XDG_RUNTIME_DIR does not have that lifetime:
# systemd keeps /run/user/<uid> for the whole login, so the key made "once
# per session" mean "once per login". Measured 2026-08-20 on a box booted
# ten days earlier: a never-synced project's sentinel was written three
# hours after boot and was still there, so the nudge had fired once, on
# day one, and had been silent in every session since. The payload's
# session_id is the fact the old key was missing.
#
# NO session_id → the path-only key, unchanged. It can be missing: an
# empty payload, malformed JSON, or a host without jq. That degrades to
# exactly today's behavior, which is the right floor — keying on anything
# per-invocation instead would turn a one-shot into a per-turn spammer,
# which is worse than the bug this fixes.
emit_nudge_once() {
  local msg="$1" sentinel_base sentinel_key sentinel key_input
  sentinel_base="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"
  if [ -n "$SESSION_ID" ]; then
    key_input="$SESSION_ID:$STAMP"
  else
    key_input="$STAMP"
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    sentinel_key=$(printf '%s' "$key_input" | sha256sum | cut -d' ' -f1)
  else
    sentinel_key=$(printf '%s' "$key_input" | cksum | tr -d ' ')
  fi
  sentinel="$sentinel_base/loom-drift-nudge-$sentinel_key"
  [ -e "$sentinel" ] && return 0   # already nudged this session

  # A single concise stderr line (D4 loudness: proportional/non-blocking).
  echo "$msg" >&2

  # Best-effort one-shot: a write failure is non-fatal (we'd just nudge
  # again next call — degrades to the pre-sentinel behavior, not a crash).
  # NOTE the redirection ORDER: `2>/dev/null` must come FIRST. Bash
  # applies redirections left to right, so the older `: >"$s" 2>/dev/null`
  # form let the shell's own "No such file or directory" complaint escape
  # to the real stderr when $sentinel's parent dir didn't exist (a
  # nonexistent $XDG_RUNTIME_DIR) — turning a clean one-line nudge into
  # two lines, the second of them noise.
  : 2>/dev/null >"$sentinel" || true
}

# 4. OPT-IN GUARD: NEITHER managedness signal (no workflow.json AND no
#    stamp) → SILENT no-op. Never nudge a project that hasn't opted into
#    loom by either route. Keep this `||`: a stamp alone is a valid
#    managedness signal (only /audit-project writes one), and narrowing
#    to `&&` would silence the grandfathered stamped-but-no-workflow.json
#    projects that already nudged before loom-oktm. See the OPT-IN GUARD
#    header note.
[ -f "$WORKFLOW_JSON" ] || [ -f "$STAMP" ] || exit 0

# 4b. NEVER-SYNCED: loom-managed but carrying no stamp at all. Nudge and
#     stop — there is no hash to compare (see the OPT-IN GUARD header
#     note). Reached only when WORKFLOW_JSON exists, per the guard above.
if [ ! -f "$STAMP" ]; then
  emit_nudge_once "[loom-drift-nudge] INFO: this loom-managed project has never been synced against loom's conventions (no .claude/.loom-sync stamp) — run \`/audit-project --apply-drift\` to sync it and write the stamp."
  exit 0
fi

# 4c. Read the stamp's SYNC record — see the CHECKED vs SYNCED header
#     note. `last_synced` is the only field this hook compares; a
#     `last_checked` written by a read-only audit must never silence it.
stamp_field() {
  grep "^$1=" "$STAMP" 2>/dev/null | head -1 | cut -d= -f2-
}
STAMPED_HASH=$(stamp_field last_synced)
STAMPED_DATE=$(stamp_field last_synced_date)
# LEGACY MIGRATION: a pre-loom-uh4i stamp carries only `hash=`/`date=`.
# Grandfather it as last_synced (see the header note) — reading it any
# other way would take every already-stamped project from silent to
# nudging overnight and would break loom-oktm's stamped-but-no-
# workflow.json fixtures.
if [ -z "$STAMPED_HASH" ]; then
  STAMPED_HASH=$(stamp_field hash)
  STAMPED_DATE=$(stamp_field date)
fi

if [ -z "$STAMPED_HASH" ]; then
  # No sync record. Two sub-states, distinguished by whether the stamp
  # carries a CHECK record:
  CHECKED_HASH=$(stamp_field last_checked)
  CHECKED_DATE=$(stamp_field last_checked_date)
  if [ -n "$CHECKED_HASH" ] || [ -n "$CHECKED_DATE" ]; then
    # CHECKED BUT NEVER SYNCED — the loom-uh4i state. Somebody ran
    # `/audit-project` against this project, but no remediation ever
    # landed. Before the checked/synced split this looked identical to
    # "fully in sync". It is the never-synced case, so it gets the
    # never-synced nudge, with the check date named so the user can see
    # that looking already happened and did not count.
    emit_nudge_once "[loom-drift-nudge] INFO: this loom-managed project has been checked (last checked ${CHECKED_DATE:-unknown}) but has never been synced against loom's conventions (no last_synced record in .claude/.loom-sync — no remediation has ever been applied) — run \`/audit-project --apply-drift\` to sync it."
    exit 0
  fi
  # Neither a sync nor a check record — a malformed or hand-edited
  # stamp. Fail open silent rather than guess.
  exit 0
fi

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

# --- STAMP-INDEPENDENT owned-file check (loom-5od2) ----------------------
# Second signal (see the TWO SIGNALS header note): byte-compare loom's
# OWNED templates against the project's live copies via
# `scripts/loom-owned-templates --check`.
#
# CHEAPNESS. Exactly ONE subprocess, regardless of how many templates
# are in the owned set — the registry loops internally and prints one
# line per entry, so this does not shell out per file. At today's owned
# count of one it is a single `cmp` on top of the manifest hash this
# hook already computes.
#
# DEGRADATION. A missing or non-executable registry (an older loom
# checkout, a partial install) → return 0 and stay SILENT about it. The
# hook falls back to the hash-only behavior it had before; announcing
# the degradation would put a line on every session start in exchange
# for nothing the user can act on.
#
# [FAIL] vs [DRIFT]. The registry emits `[FAIL]` when LOOM's OWN copy of
# an owned template is missing, and exits non-zero for that too. That is
# loom's problem, not the project's — nudging the project to
# `--apply-drift` a file loom cannot supply would be a false positive.
# So this keys on `[DRIFT]` lines specifically, never on the exit code.
check_owned_drift() {
  local bin="$LOOM_SELF_ROOT/scripts/loom-owned-templates"
  [ -x "$bin" ] || return 0

  local out line rest drifted=""
  out=$("$bin" --check --root "$CWD" --loom "$LOOM_SELF_ROOT" 2>/dev/null) || true
  [ -n "$out" ] || return 0

  while IFS= read -r line; do
    case "$line" in
      "[DRIFT] "*) ;;
      *) continue ;;
    esac
    # `[DRIFT] <abs-target> (<reason>)` → project-relative, reason kept.
    rest="${line#\[DRIFT\] }"
    rest="${rest#"$CWD"/}"
    if [ -n "$drifted" ]; then drifted="$drifted; $rest"; else drifted="$rest"; fi
  done <<<"$out"

  [ -n "$drifted" ] || return 0

  emit_nudge_once "[loom-drift-nudge] INFO: this project's loom-OWNED convention file(s) do not match loom's current copies — $drifted. The sync stamp says current, but this is a byte comparison of the files themselves, so the stamp cannot vouch for them — run \`/audit-project --apply-drift\` to apply loom's copy."
}

# 6. Compare. A matching hash means the STAMP says in sync — which is a
#    claim about the past. Before believing it, run the byte-level
#    owned-file check (loom-5od2); it is the signal a partial
#    `--apply-drift` can leave firing while the hash reads current.
if [ "$STAMPED_HASH" = "$CURRENT_HASH" ]; then
  check_owned_drift
  exit 0
fi

# 7. STALE STAMP: emit the drift nudge, once per session. Names the
#    drift (stamped vs current hash, short form) and points at the fix
#    command.
emit_nudge_once "[loom-drift-nudge] INFO: this project's loom-convention stamp (hash=${STAMPED_HASH:0:12}..., synced ${STAMPED_DATE:-unknown}) is behind loom's current conventions (hash=${CURRENT_HASH:0:12}...) — run \`/audit-project --apply-drift\` to resync."

exit 0
