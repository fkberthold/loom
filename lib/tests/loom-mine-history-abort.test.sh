#!/usr/bin/env bash
# Fixture tests for lib/loom-mine-history.sh — the TRANSIENT-BURST
# RESILIENCE behaviour (loom-wzcn).
#
# CONTEXT (loom-417 529-playbook, .claude/rules/dispatched-agents.md):
#   The salience loop calls `claude -p` per unit. The aggregate
#   LLM-failure gate (loom-ug4p) ABORTS the whole harvest once the
#   failure fraction exceeds _LMH_FAIL_THRESHOLD_PCT over
#   _LMH_FAIL_MIN_PROCESSED units. That floor is correct for a
#   SUSTAINED throttle but BRITTLE AT THE START: a transient API burst
#   in the first few units trips the gate and discards everything
#   (the rnxp 4/4 abort — the same units passed minutes later).
#
# THE FIX this test pins (loom-wzcn):
#   When the aggregate threshold is hit, the engine no longer aborts
#   immediately. It PAUSES, runs a HEALTH-PROBE (one cheap `claude -p`
#   call), and if the probe FAILS it backs off exponentially through a
#   schedule (default `30 60 120 240`s, ~4 cycles), re-probing each
#   cycle. On a CLEAN probe it RESUMES the SAME loop (accumulated drafts
#   kept). Only when the backoff schedule is EXHAUSTED does it fall back
#   to the loud non-zero abort. A _LMH_WARMUP_UNITS grace also disables
#   the gate until that many units have been processed.
#
# Test strategy (mirrors loom-mine-history-claude-failure.test.sh):
#   - PATH-prepended `claude` + `gh` stubs steered by env-var files.
#   - The `claude` stub fails the FIRST N calls then succeeds, so a
#     transient burst can be simulated (CLAUDE_FAIL_FIRST_N), OR fails
#     EVERY call (CLAUDE_FAIL_ALWAYS=1) for the sustained-outage case.
#     Both the salience calls AND the health-probe go through this
#     SAME stub (the probe is a `claude -p` call) — so the probe
#     recovers naturally once the burst's fail-window has elapsed.
#   - With _LMH_LLM_RETRIES=1 (one call per unit, no within-unit retry
#     absorbing the burst), the LOCKED invariant reads literally: the
#     first 4 calls = the first 4 units, all failing, tripping the
#     4-unit floor — exactly the rnxp shape.
#   - _LMH_BACKOFF_SCHEDULE is set to all-zeros so NO real sleeping
#     happens — the test runs in milliseconds, not minutes.
#   - A REAL temp git repo seeded with SEVERAL substantial decision
#     commits, so the heuristic gate yields >= N survivors.
#
# Run:  bash lib/tests/loom-mine-history-abort.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$LOOM_ROOT/lib/loom-mine-history.sh"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# --- Stub directory --------------------------------------------------
#
# `gh` is the standard degrade-to-git-only stub (auth always fails).
# `claude` is a BURST stub:
#   - records every call to CLAUDE_CALLS_FILE (one "CALL" line each),
#   - emits its body to stderr (so the engine's stderr-capture has
#     something to surface),
#   - CLAUDE_FAIL_FIRST_N=k makes the FIRST k calls (across BOTH
#     salience units AND health-probes — they share the counter) FAIL
#     (empty stdout, non-zero exit, throttle-like stderr); call k+1 and
#     onward SUCCEED with a valid salient reply. This simulates a
#     TRANSIENT burst that clears.
#   - CLAUDE_FAIL_ALWAYS=1 makes EVERY call fail forever (the SUSTAINED
#     outage case). Takes precedence over CLAUDE_FAIL_FIRST_N.
mk_stubs_dir() {
  local d
  d=$(mktemp -d)

  cat > "$d/gh" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  auth) exit 1 ;;          # always unauthenticated → git-only harvest
  pr)   echo "[]" ;;
  api)  : ;;
  *)    exit 1 ;;
esac
EOF

  cat > "$d/claude" <<'EOF'
#!/usr/bin/env bash
# BURST stub. Counts calls; fails the first N (transient) or always.
n=0
if [ -n "${CLAUDE_CALLS_FILE:-}" ]; then
  echo "CALL" >> "$CLAUDE_CALLS_FILE"
  n=$(grep -c '^CALL$' "$CLAUDE_CALLS_FILE")
fi
if [ "${CLAUDE_FAIL_ALWAYS:-0}" = "1" ]; then
  echo "Error: Overloaded (rate limited). Please retry." >&2
  exit 1
fi
first="${CLAUDE_FAIL_FIRST_N:-0}"
if [ "$n" -le "$first" ]; then
  # Inside the transient burst window: fail.
  echo "Error: Overloaded (rate limited). Please retry." >&2
  exit 1
fi
# Burst cleared: a valid, successful, SALIENT reply.
if [ -n "${CLAUDE_REPLY_FILE:-}" ] && [ -f "$CLAUDE_REPLY_FILE" ]; then
  cat "$CLAUDE_REPLY_FILE"
else
  echo '{"salient":true,"verbatim":"v","synthesis":"s","decision":"d"}'
fi
EOF

  chmod +x "$d/gh" "$d/claude"
  echo "$d"
}

# --- git fixture repo: MANY survivors --------------------------------
#
# Six substantial decision commits, each touching a decision-shaped file
# WITH a rationale body — so all six clear the heuristic gate (score >= 2)
# and are fed to the salience pass. A comfortably-large survivor set for
# the burst/backoff logic to operate over.
mk_fixture_repo_many() {
  local work repo
  work=$(mktemp -d)
  repo="$work/repo"
  mkdir -p "$repo"
  (
    cd "$repo" || exit 1
    git init -q -b main
    git config user.email miner@test
    git config user.name "Decision Miner"

    echo "base" > README.md
    git add -A && git -c core.hooksPath=/dev/null commit -q -m "initial"

    local i
    for i in 1 2 3 4 5 6; do
      cat > "schema_$i.sql" <<SQL
CREATE TABLE t$i (id INT PRIMARY KEY, body TEXT);
SQL
      git add -A
      git -c core.hooksPath=/dev/null commit -q -m "Add schema variant $i

We chose design variant $i over the alternative because query latency
on the hot read path dominates; the trade-off is heavier migrations but
faster reads. Decision recorded for downstream consumers."
    done
  ) || { echo "FIXTURE_BUILD_FAILED" >&2; return 1; }
  echo "$repo"
}

# Source the lib with stubs on PATH and run the entry point.
run_mine() {
  local repo="$1"; shift
  (
    PATH="$STUBS:$PATH" bash -c '
      set -uo pipefail
      source "$1"; shift
      loom_mine_history "$@"
    ' _ "$LIB" "$repo" "$@"
  ) 2>&1
}

# =====================================================================
# 1. TRANSIENT BURST — claude FAILS the first 4 salience calls (tripping
#    the 4-unit floor), then SUCCEEDS. The pass must RIDE OUT the burst
#    (pause → health-probe → backoff → resume the SAME loop) and complete
#    WITH drafts, rather than aborting non-zero at the 4-unit floor.
#
#    This is the LOCKED RED invariant for loom-wzcn.
# =====================================================================
echo "==> 1. Transient burst (first 4 fail) → rides out, completes WITH drafts"

STUBS=$(mk_stubs_dir)
REPO=$(mk_fixture_repo_many)
OUT=$(mktemp -d)
CALLS=$(mktemp)
REPLY=$(mktemp)
printf '%s' '{"salient":true,"verbatim":"v","synthesis":"s","decision":"d"}' > "$REPLY"

export GH_AUTH_OK=0
export CLAUDE_CALLS_FILE="$CALLS"
export CLAUDE_REPLY_FILE="$REPLY"
export CLAUDE_FAIL_FIRST_N=4         # first 4 calls fail, then recover
unset CLAUDE_FAIL_ALWAYS 2>/dev/null || true
# Warm-up OFF so the 4-unit floor is the active gate (the rnxp shape).
export _LMH_WARMUP_UNITS=0
# Per-unit retry budget of 1 so each unit's FAILURE is counted promptly
# (we want the AGGREGATE gate, not the per-unit retry, to ride the burst).
export _LMH_LLM_RETRIES=1
# All-zero backoff schedule ⇒ NO real sleeping. The test runs in ms.
export _LMH_BACKOFF_SCHEDULE="0 0 0 0"

out=$(run_mine "$REPO" --out "$OUT" --yes --model fake); rc=$?

# 1a. The pass must NOT abort — it rides out the transient burst.
if [ "$rc" -eq 0 ]; then
  pass "transient burst ridden out → exit 0 (not aborted at the 4-unit floor)"
else
  fail "transient burst aborted (rc=$rc) — the brittle-start bug" "$out"
fi

# 1b. Drafts must be emitted (the units that succeeded post-burst).
if [ -s "$OUT/drafts.jsonl" ]; then
  pass "drafts emitted after the burst cleared"
else
  fail "no drafts.jsonl despite the burst clearing" "$out"
fi

# 1c. The health-probe must have actually fired (more claude calls than
#     the 6 survivors × 1 retry would alone produce). Sanity: the probe
#     path ran, not a silent skip.
if [ -s "$CALLS" ]; then
  pass "claude invoked (salience + probe)"
else
  fail "claude never invoked" "$out"
fi

# =====================================================================
# 2. SUSTAINED OUTAGE — claude fails EVERY call (salience AND probe).
#    The backoff schedule is exhausted with no clean probe, so the engine
#    must FALL BACK to the loud non-zero abort (the loom-ug4p behaviour
#    is preserved for a genuine sustained outage).
# =====================================================================
echo "==> 2. Sustained outage (every call fails) → still aborts non-zero after backoff cap"

STUBS=$(mk_stubs_dir)
REPO=$(mk_fixture_repo_many)
OUT=$(mktemp -d)
CALLS=$(mktemp)
REPLY=$(mktemp)
printf '%s' '{"salient":true,"verbatim":"v","synthesis":"s","decision":"d"}' > "$REPLY"

export GH_AUTH_OK=0
export CLAUDE_CALLS_FILE="$CALLS"
export CLAUDE_REPLY_FILE="$REPLY"
export CLAUDE_FAIL_ALWAYS=1          # every call fails forever
unset CLAUDE_FAIL_FIRST_N 2>/dev/null || true
export _LMH_WARMUP_UNITS=0
export _LMH_LLM_RETRIES=1
export _LMH_BACKOFF_SCHEDULE="0 0"   # short cap; all-zero ⇒ no sleeping

out=$(run_mine "$REPO" --out "$OUT" --yes --model fake); rc=$?

# 2a. A genuine sustained outage MUST still abort non-zero.
if [ "$rc" -ne 0 ]; then
  pass "sustained outage → non-zero exit (rc=$rc) after backoff cap"
else
  fail "sustained outage exited 0 (false success — abort-loud fallback lost)" "$out"
fi

# 2b. The diagnostic must still name the failure (loom-ug4p preserved).
if printf '%s' "$out" | grep -qiE 'fail|throttl|rate|abort'; then
  pass "abort diagnostic preserved on sustained outage"
else
  fail "no abort diagnostic on sustained outage" "$out"
fi

# 2c. No false-success drafts manifest on a total outage.
if [ ! -s "$OUT/drafts.jsonl" ]; then
  pass "no false-success drafts.jsonl on sustained outage"
else
  fail "drafts.jsonl written despite sustained outage" "$(cat "$OUT/drafts.jsonl")"
fi

# =====================================================================
# Summary
# =====================================================================
echo
echo "loom-mine-history-abort: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
exit 0
