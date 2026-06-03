#!/usr/bin/env bash
# Fixture tests for scripts/loom-mine-history (the user-facing wrapper).
#
# Builds loom-bn7.4: the wrapper that resolves repo + wing and invokes
# the ALREADY-BUILT engine lib/loom-mine-history.sh. The wrapper owns
# resolution + invocation; the SKILL (skills/loom-mine-history/SKILL.md)
# owns the two-pass cost gate orchestration + MCP palace filing. This
# test exercises the WRAPPER only — bash-only, no MCP.
#
# Design source: drawer_loom_decisions_e43e3693c8ee82e3bc6e34c6
# (loom/decisions wing). Tracks loom-bn7.4.
#
# Test strategy (mirrors check-upstream-prs.test.sh + the bn7.1
# loom-mine-history.test.sh PATH-stub + real-git-fixture pattern):
#   - PATH-prepend stubs for BOTH `gh` and `claude`, driven by
#     side-channel env-var files. `gh` degrades (auth fails) so harvest
#     is git-only; `claude` records every call so spend can be asserted
#     ABSENT on the --dry-run path and PRESENT on the real path.
#   - A REAL temp git repo seeded with a decision commit + a tagged
#     release commit — the genuine integration surface.
#
# What the wrapper commits to (the contract this test pins):
#   scripts/loom-mine-history [--root <dir>] [--wing <name>] \
#       [--since=DATE] [--since-release=TAG] [--max-units=N] \
#       [--dry-run] [--model=MODEL]
#   - repo resolution: --root override, else cwd git toplevel.
#   - wing resolution: --wing override, else basename of repo VERBATIM
#     (no _↔- substitution; e.g. e2e-api-tests → e2e-api-tests). loom-kx2.
#   - --dry-run  → invoke lib --dry-run, NO --out, zero spend.
#   - real pass  → invoke lib --yes --out <dir>; writes drafts.jsonl +
#     kg-triples.jsonl (from the lib) AND <dir>/wing (single line, the
#     resolved wing — the lib does not emit wing, the wrapper does).
#   - bad --root (nonexistent / not-a-git-dir) → nonzero exit + stderr.
#
# Run:  bash lib/tests/loom-mine-history-cmd.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WRAPPER="$LOOM_ROOT/scripts/loom-mine-history"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# --- Stub directory --------------------------------------------------
#
# `gh` and `claude` stubs, PATH-prepended by the caller. Steered by
# env-var files so each case sets its own fixtures.
#   GH_AUTH_OK        — if "1", `gh auth status` exits 0; else exits 1.
#   CLAUDE_REPLY_FILE — JSON body emitted by `claude -p ...`.
#   CLAUDE_CALLS_FILE — appended one "CALL" line per `claude` call.
mk_stubs_dir() {
  local d
  d=$(mktemp -d)

  cat > "$d/gh" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  auth) [ "${GH_AUTH_OK:-0}" = "1" ] && exit 0 || { echo "not logged in" >&2; exit 1; } ;;
  pr)   echo "[]" ;;
  api)  : ;;
  *)    exit 1 ;;
esac
EOF

  cat > "$d/claude" <<'EOF'
#!/usr/bin/env bash
echo "CALL" >> "${CLAUDE_CALLS_FILE:-/dev/null}"
if [ -n "${CLAUDE_REPLY_FILE:-}" ] && [ -f "$CLAUDE_REPLY_FILE" ]; then
  cat "$CLAUDE_REPLY_FILE"
else
  echo '{"salient":false}'
fi
EOF

  chmod +x "$d/gh" "$d/claude"
  echo "$d"
}

# --- git fixture repo ------------------------------------------------
#
# Real temp git repo: one junk commit (dropped) + one decision commit
# touching schema.sql (survives the heuristic gate) + one tagged
# release commit (survives). The repo dir name is controllable so the
# wing-default (basename) assertions can use a `-`-containing name.
mk_fixture_repo() {
  local dirname="${1:-repo}"
  local work repo
  work=$(mktemp -d)
  repo="$work/$dirname"
  mkdir -p "$repo"
  (
    cd "$repo" || exit 1
    git init -q -b main
    git config user.email miner@test
    git config user.name "Decision Miner"

    echo "base" > README.md
    git add -A && git -c core.hooksPath=/dev/null commit -q -m "initial"

    echo "scratch" > scratch.txt
    git add -A && git -c core.hooksPath=/dev/null commit -q -m "wip: scratch"

    cat > schema.sql <<'SQL'
CREATE TABLE decisions (id INT PRIMARY KEY, body TEXT);
SQL
    git add -A
    git -c core.hooksPath=/dev/null commit -q -m "Add decisions schema

We chose a single-table design over the EAV pattern because query
latency on the decision timeline dominates; normalized EAV would
require N joins per timeline render. Trade-off accepted."

    cat > interfaces.go <<'GO'
package api
type Service interface { Decide() error }
GO
    git add -A
    git -c core.hooksPath=/dev/null commit -q -m "Freeze v1.0 API surface

Locking the Service interface for the 1.0 release. Downstream
consumers depend on this contract; breaking it requires an RFC."
    git tag v1.0
  ) || { echo "FIXTURE_BUILD_FAILED" >&2; return 1; }
  echo "$repo"
}

# Run the wrapper with stubs on PATH, from a given cwd. Echoes
# stdout+stderr; rc propagated.
#   run_wrapper <cwd> <stubs> [args...]
run_wrapper() {
  local cwd="$1"; local stubs="$2"; shift 2
  (
    cd "$cwd" || exit 99
    PATH="$stubs:$PATH" bash "$WRAPPER" "$@"
  ) 2>&1
}

# =====================================================================
# 0. Wrapper exists, is executable, sources without side effects.
# =====================================================================
echo "==> 0. Wrapper shape"

if [ -f "$WRAPPER" ]; then
  pass "scripts/loom-mine-history exists"
else
  fail "scripts/loom-mine-history missing"
fi

if [ -x "$WRAPPER" ]; then
  pass "scripts/loom-mine-history is executable"
else
  fail "scripts/loom-mine-history not executable"
fi

if head -1 "$WRAPPER" 2>/dev/null | grep -q '^#!.*bash'; then
  pass "wrapper is bash-shebanged"
else
  fail "wrapper missing bash shebang"
fi

# Sourcing the wrapper must NOT run the pipeline (no claude calls, no
# git harvest). The wrapper is exec-only; sourcing is a no-op-ish smoke.
SRC_CALLS=$(mktemp)
( CLAUDE_CALLS_FILE="$SRC_CALLS" source "$WRAPPER" >/dev/null 2>&1 ) || true
if [ ! -s "$SRC_CALLS" ]; then
  pass "sourcing wrapper triggers no LLM spend (exec-only side-effect sanity)"
else
  fail "sourcing wrapper invoked claude (should be exec-only)" "$(cat "$SRC_CALLS")"
fi
rm -f "$SRC_CALLS"

# =====================================================================
# 1. --dry-run: cost preview printed, NO drafts.jsonl, ZERO spend.
#    Wrapper must call the lib with --dry-run and WITHOUT --out (the
#    locked two-pass contract: dry-run never writes a manifest).
# =====================================================================
echo "==> 1. --dry-run → preview, no manifest, no spend"

STUBS=$(mk_stubs_dir)
REPO=$(mk_fixture_repo)
CALLS=$(mktemp)
export GH_AUTH_OK=0

out=$(CLAUDE_CALLS_FILE="$CALLS" run_wrapper "$REPO" "$STUBS" --dry-run); rc=$?

if [ "$rc" -eq 0 ]; then pass "dry-run exits 0"; else fail "dry-run rc=$rc" "$out"; fi

if echo "$out" | grep -q "cost-preview:"; then
  pass "dry-run surfaces cost preview (N harvested -> M gated)"
else
  fail "dry-run missing cost preview" "$out"
fi

if [ ! -s "$CALLS" ]; then
  pass "dry-run made ZERO claude calls (no spend)"
else
  fail "dry-run spent on claude (should be zero)" "$(cat "$CALLS")"
fi
rm -f "$CALLS"
rm -rf "$STUBS" "$REPO"

# =====================================================================
# 2. Real pass: writes drafts.jsonl + kg-triples.jsonl + wing.
#    The wrapper passes --yes --out <dir> to the lib, then writes the
#    resolved wing to <dir>/wing AND echoes it.
# =====================================================================
echo "==> 2. real pass → manifest + wing file"

STUBS=$(mk_stubs_dir)
REPO=$(mk_fixture_repo "myproj")
OUT=$(mktemp -d)
CALLS=$(mktemp)
REPLY=$(mktemp)
cat > "$REPLY" <<'JSON'
{"salient":true,"verbatim":"We chose single-table over EAV.","synthesis":"Single-table wins on read latency.","decision":"single-table schema"}
JSON
export GH_AUTH_OK=0

out=$(CLAUDE_CALLS_FILE="$CALLS" CLAUDE_REPLY_FILE="$REPLY" \
      run_wrapper "$REPO" "$STUBS" --out "$OUT"); rc=$?

if [ "$rc" -eq 0 ]; then pass "real pass exits 0"; else fail "real pass rc=$rc" "$out"; fi

if [ -s "$OUT/drafts.jsonl" ]; then
  pass "real pass wrote drafts.jsonl"
else
  fail "real pass did NOT write drafts.jsonl" "$out"
fi

if [ -f "$OUT/kg-triples.jsonl" ]; then
  pass "real pass wrote kg-triples.jsonl"
else
  fail "real pass did NOT write kg-triples.jsonl" "$out"
fi

if [ -f "$OUT/wing" ]; then
  pass "real pass wrote <out>/wing"
else
  fail "real pass did NOT write <out>/wing" "$out"
fi

if [ "$(cat "$OUT/wing" 2>/dev/null)" = "myproj" ]; then
  pass "wing file holds resolved wing (basename default)"
else
  fail "wing file wrong: got '$(cat "$OUT/wing" 2>/dev/null)' want 'myproj'" "$out"
fi

if echo "$out" | grep -q "myproj"; then
  pass "wrapper echoes the resolved wing"
else
  fail "wrapper did NOT echo resolved wing" "$out"
fi

if [ -s "$CALLS" ]; then
  pass "real pass invoked claude (spend on confirmed pass)"
else
  fail "real pass made no claude call (expected spend)" "$(cat "$CALLS")"
fi
rm -f "$CALLS" "$REPLY"
rm -rf "$STUBS" "$REPO" "$OUT"

# =====================================================================
# 3. --root override resolves a different repo than cwd.
#    Run the wrapper from a NON-git temp dir, point --root at the
#    fixture, and assert it still mines (dry-run preview present).
# =====================================================================
echo "==> 3. --root override"

STUBS=$(mk_stubs_dir)
REPO=$(mk_fixture_repo)
NONGIT=$(mktemp -d)
CALLS=$(mktemp)
export GH_AUTH_OK=0

out=$(CLAUDE_CALLS_FILE="$CALLS" run_wrapper "$NONGIT" "$STUBS" --root "$REPO" --dry-run); rc=$?

if [ "$rc" -eq 0 ]; then
  pass "--root override exits 0 from a non-git cwd"
else
  fail "--root override rc=$rc" "$out"
fi

if echo "$out" | grep -q "cost-preview:"; then
  pass "--root override mined the pointed-at repo"
else
  fail "--root override did not mine pointed-at repo" "$out"
fi
rm -f "$CALLS"
rm -rf "$STUBS" "$REPO" "$NONGIT"

# =====================================================================
# 4. Wing default = basename VERBATIM (no _↔- substitution); --wing
#    overrides. Verbatim matches scripts/loom-audit-resolve + the
#    audit-project skill, and is the only rule correct for both
#    underscore wings (liza_base) AND dash wings (e2e-api-tests,
#    golden-path). The old `-`→`_` mangled dash wings — loom-kx2,
#    confirmed live by the e2e-api-tests dogfood (e2e-api-tests →
#    e2e_api_tests, the wrong wing).
# =====================================================================
echo "==> 4. wing default verbatim + --wing override"

STUBS=$(mk_stubs_dir)
REPO=$(mk_fixture_repo "e2e-api-tests")
OUT=$(mktemp -d)
CALLS=$(mktemp)
REPLY=$(mktemp)
echo '{"salient":true,"verbatim":"v","synthesis":"s","decision":"d"}' > "$REPLY"
export GH_AUTH_OK=0

# 4a. DECIDING CASE: dash-named repo → wing preserved verbatim (NOT
#     mangled to e2e_api_tests). This is the loom-kx2 regression.
out=$(CLAUDE_CALLS_FILE="$CALLS" CLAUDE_REPLY_FILE="$REPLY" \
      run_wrapper "$REPO" "$STUBS" --out "$OUT"); rc=$?
if [ "$(cat "$OUT/wing" 2>/dev/null)" = "e2e-api-tests" ]; then
  pass "wing default verbatim (e2e-api-tests stays e2e-api-tests, not e2e_api_tests)"
else
  fail "wing default not verbatim: got '$(cat "$OUT/wing" 2>/dev/null)' want 'e2e-api-tests'" "$out"
fi

# 4b. --wing override wins.
OUT2=$(mktemp -d)
out=$(CLAUDE_CALLS_FILE="$CALLS" CLAUDE_REPLY_FILE="$REPLY" \
      run_wrapper "$REPO" "$STUBS" --wing custom_wing --out "$OUT2"); rc=$?
if [ "$(cat "$OUT2/wing" 2>/dev/null)" = "custom_wing" ]; then
  pass "--wing override resolves verbatim"
else
  fail "--wing override ignored: got '$(cat "$OUT2/wing" 2>/dev/null)'" "$out"
fi
rm -f "$CALLS" "$REPLY"
rm -rf "$STUBS" "$REPO" "$OUT" "$OUT2"

# =====================================================================
# 5. Flag pass-through: --since / --max-units reach the lib.
#    --max-units=0 caps survivors to zero → the dry-run preview shows
#    "-> 0 gated". --since with a far-future date harvests nothing.
# =====================================================================
echo "==> 5. --since / --max-units reach the lib"

STUBS=$(mk_stubs_dir)
REPO=$(mk_fixture_repo)
export GH_AUTH_OK=0

# --max-units=0 → zero survivors fed to the (would-be) LLM pass.
out=$(run_wrapper "$REPO" "$STUBS" --dry-run --max-units=0); rc=$?
if echo "$out" | grep -qE '> 0 gated|-> 0 gated|0 gated'; then
  pass "--max-units=0 reaches lib (0 gated in preview)"
else
  fail "--max-units did not reach lib" "$out"
fi

# --since far future → nothing harvested.
out=$(run_wrapper "$REPO" "$STUBS" --dry-run --since=2099-01-01); rc=$?
if echo "$out" | grep -qE '0 harvested'; then
  pass "--since reaches lib (0 harvested for far-future date)"
else
  fail "--since did not reach lib" "$out"
fi
rm -rf "$STUBS" "$REPO"

# =====================================================================
# 6. NEGATIVES — bad --root → nonzero exit + stderr message.
# =====================================================================
echo "==> 6. negatives: bad --root"

STUBS=$(mk_stubs_dir)
HERE=$(mktemp -d)

# 6a. nonexistent --root.
out=$(run_wrapper "$HERE" "$STUBS" --root /no/such/path/at/all --dry-run); rc=$?
if [ "$rc" -ne 0 ]; then
  pass "nonexistent --root → nonzero exit"
else
  fail "nonexistent --root exited 0 (should fail)" "$out"
fi
if echo "$out" | grep -qiE 'not.*git|no.*such|does not exist|not a directory|invalid'; then
  pass "nonexistent --root emits diagnostic to stderr"
else
  fail "nonexistent --root: no diagnostic" "$out"
fi

# 6b. --root pointing at a real dir that is NOT a git repo.
NONGIT=$(mktemp -d)
out=$(run_wrapper "$HERE" "$STUBS" --root "$NONGIT" --dry-run); rc=$?
if [ "$rc" -ne 0 ]; then
  pass "not-a-git-dir --root → nonzero exit"
else
  fail "not-a-git-dir --root exited 0 (should fail)" "$out"
fi
if echo "$out" | grep -qiE 'not a git|git repos'; then
  pass "not-a-git-dir --root emits diagnostic"
else
  fail "not-a-git-dir --root: no git diagnostic" "$out"
fi
rm -rf "$STUBS" "$HERE" "$NONGIT"

# =====================================================================
# Summary
# =====================================================================
echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
