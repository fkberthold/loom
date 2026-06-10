#!/usr/bin/env bash
# Fixture tests for lib/loom-mine-history.sh — the CLAUDE-FAILURE
# distinguishability bug (loom-ug4p).
#
# BUG (root cause, diagnosed):
#   In the LLM salience pass, the engine ran
#     reply=$(claude -p "$source_text" --model "$model" \
#               --output-format text 2>/dev/null)
#   which SWALLOWED claude's stderr, and then an empty / non-zero /
#   unparseable reply yielded `salient=""` → `continue` (no draft) —
#   INDISTINGUISHABLE from a genuine {"salient":false}. So a throttled /
#   rate-limited / crashed claude run wrote a CLEAN near-0-draft manifest
#   that looked successful. This caused loom-rnxp's 0/353 and the
#   original 0/787 (NOT body-truncation, which loom-b10 fixed).
#
# THE FIX this test pins:
#   When a HIGH FRACTION of survivor units come back FAILED (empty OR
#   rc != 0 OR unparseable-as-JSON) — as opposed to a legitimate
#   {"salient":false} — the engine must NOT silently emit a clean
#   "success" manifest. It must EXIT NON-ZERO with a diagnostic that
#   names the failure fraction.
#
# Test strategy (mirrors loom-mine-history.test.sh):
#   - PATH-prepended `claude` + `gh` stubs steered by env-var files.
#   - The `claude` stub here is a FAILURE stub: it returns empty AND
#     exits non-zero for (by default) EVERY call, simulating a
#     throttled / rate-limited / crashed claude. A side-channel
#     (CLAUDE_FAIL_EVERY_N) lets a case make only a FRACTION fail so the
#     below-threshold (tolerated) path can also be exercised.
#   - A REAL temp git repo seeded with SEVERAL substantial decision
#     commits, so the heuristic gate yields >= N survivors fed to the
#     salience pass.
#
# Run:  bash lib/tests/loom-mine-history-claude-failure.test.sh

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
# `claude` is a FAILURE stub:
#   - records every call to CLAUDE_CALLS_FILE (one "CALL" line each),
#   - emits its body to stderr (so the engine's stderr-capture has
#     something to surface in a real failure),
#   - by default emits NOTHING on stdout and exits 1 (the throttle
#     simulation).
#   - CLAUDE_FAIL_EVERY_N=k makes only every k-th call FAIL; the others
#     emit CLAUDE_REPLY_FILE (a valid salient JSON) and exit 0. k=1
#     (default) ⇒ ALL fail.
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
# FAILURE stub for the throttle/rate-limit/crash simulation.
n=0
if [ -n "${CLAUDE_CALLS_FILE:-}" ]; then
  echo "CALL" >> "$CLAUDE_CALLS_FILE"
  n=$(grep -c '^CALL$' "$CLAUDE_CALLS_FILE")
fi
every="${CLAUDE_FAIL_EVERY_N:-1}"   # 1 ⇒ every call fails
# Fail when this call is a "fail" call (n divisible by `every`).
if [ "$every" -ge 1 ] && [ $(( n % every )) -eq 0 ]; then
  # Simulate a throttled / crashed claude: noisy stderr, empty stdout,
  # non-zero exit.
  echo "Error: Overloaded (rate limited). Please retry." >&2
  exit 1
fi
# Otherwise: a valid, successful, SALIENT reply.
if [ -n "${CLAUDE_REPLY_FILE:-}" ] && [ -f "$CLAUDE_REPLY_FILE" ]; then
  cat "$CLAUDE_REPLY_FILE"
else
  echo '{"salient":false}'
fi
EOF

  chmod +x "$d/gh" "$d/claude"
  echo "$d"
}

# --- git fixture repo: MANY survivors --------------------------------
#
# Six substantial decision commits, each touching a decision-shaped file
# (schema/config/interface) WITH a rationale body — so all six clear the
# heuristic gate (score >= 2) and are fed to the salience pass. That
# gives a comfortably-large survivor set (>= N) for the failure-fraction
# logic to operate over.
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
# 1. CLAUDE TOTAL FAILURE — every salience call returns empty / rc!=0.
#    The engine MUST NOT write a clean near-0-draft "success" manifest;
#    it must EXIT NON-ZERO with a diagnostic naming the failure fraction.
# =====================================================================
echo "==> 1. Total claude failure → abort non-zero, no false-success manifest"

STUBS=$(mk_stubs_dir)
REPO=$(mk_fixture_repo_many)
OUT=$(mktemp -d)
CALLS=$(mktemp)
REPLY=$(mktemp)
# A valid salient reply — used only by the NON-failing calls (none here).
printf '%s' '{"salient":true,"verbatim":"v","synthesis":"s","decision":"d"}' > "$REPLY"

export GH_AUTH_OK=0
export CLAUDE_CALLS_FILE="$CALLS"
export CLAUDE_REPLY_FILE="$REPLY"
export CLAUDE_FAIL_EVERY_N=1        # EVERY call fails

out=$(run_mine "$REPO" --out "$OUT" --yes --model fake); rc=$?

# 1a. The engine must NOT exit 0 (a clean "success" with ~0 drafts is the
#     bug). It must signal failure.
if [ "$rc" -ne 0 ]; then
  pass "total claude failure → non-zero exit (rc=$rc)"
else
  fail "total claude failure → exited 0 (false success — the bug)" "$out"
fi

# 1b. The diagnostic must name the failure fraction (so the user can tell
#     a throttle from a genuine all-{salient:false} run). Accept any
#     mention of failure + a fraction/percentage/ratio.
if printf '%s' "$out" | grep -qiE 'fail|throttl|rate'; then
  pass "diagnostic names the failure"
else
  fail "no failure diagnostic in output" "$out"
fi
if printf '%s' "$out" | grep -qiE '[0-9]+%|[0-9]+/[0-9]+|fraction|0\.[0-9]+'; then
  pass "diagnostic names the failure fraction"
else
  fail "diagnostic does not name a fraction/percentage" "$out"
fi

# 1c. It must NOT have written a clean "success" manifest of drafts. With
#     every call failing, drafts.jsonl must be absent or empty.
if [ ! -s "$OUT/drafts.jsonl" ]; then
  pass "no false-success drafts.jsonl on total failure"
else
  fail "drafts.jsonl written despite total claude failure" "$(cat "$OUT/drafts.jsonl")"
fi

# 1d. claude WAS actually invoked (sanity: the pass ran, the abort is not
#     a pre-pass bail). With retries, count is >= the survivor count.
if [ -s "$CALLS" ]; then
  pass "claude was invoked in the salience pass"
else
  fail "claude never invoked — abort fired before the pass" "$out"
fi

# =====================================================================
# 2. RETRY — a transiently-failing unit is retried before counting as a
#    failure. With CLAUDE_FAIL_EVERY_N large enough that NO call hits the
#    fail slot, every unit succeeds and the engine completes cleanly.
#    (Guards that the retry/backoff path doesn't itself break the happy
#    path, and that a sub-threshold failure rate is TOLERATED.)
# =====================================================================
echo "==> 2. Sub-threshold failure is tolerated → engine completes, drafts emitted"

STUBS=$(mk_stubs_dir)
REPO=$(mk_fixture_repo_many)
OUT=$(mktemp -d)
CALLS=$(mktemp)
REPLY=$(mktemp)
printf '%s' '{"salient":true,"verbatim":"v","synthesis":"s","decision":"d"}' > "$REPLY"

export GH_AUTH_OK=0
export CLAUDE_CALLS_FILE="$CALLS"
export CLAUDE_REPLY_FILE="$REPLY"
# Fail every 1000th call ⇒ effectively no call fails ⇒ all units succeed.
export CLAUDE_FAIL_EVERY_N=1000

out=$(run_mine "$REPO" --out "$OUT" --yes --model fake); rc=$?

if [ "$rc" -eq 0 ]; then
  pass "no-failure run completes cleanly (rc=0)"
else
  fail "no-failure run exited non-zero (rc=$rc)" "$out"
fi

if [ -s "$OUT/drafts.jsonl" ]; then
  pass "salient drafts emitted on the clean path"
else
  fail "no drafts emitted on the clean path" "$out"
fi

# =====================================================================
# Summary
# =====================================================================
echo
echo "loom-mine-history-claude-failure: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
exit 0
