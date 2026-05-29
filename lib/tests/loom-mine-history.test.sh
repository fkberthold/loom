#!/usr/bin/env bash
# Fixture tests for lib/loom-mine-history.sh.
#
# Builds loom-bn7.1: the deterministic core of the brownfield
# "decision-archaeology" history miner. The lib owns stages 1-4 of a
# 5-stage pipeline (HARVEST → HEURISTIC GATE → COST-PREVIEW gate →
# LLM SALIENCE+DRAFT) plus the manifest emit (stage 5 EMIT). Stage-5
# *MCP palace filing* is OUT OF SCOPE (bn7.4); this lib's terminus is
# writing drafts.jsonl + kg-triples.jsonl to disk.
#
# Design source: drawer_loom_decisions_e43e3693c8ee82e3bc6e34c6
# (loom/decisions wing). Tracks loom-bn7.1.
#
# Test strategy (mirrors check-upstream-prs.test.sh + bd-post-
# rewrite.test.sh):
#   - PATH-prepend stubs for BOTH `gh` and `claude`, driven by
#     side-channel env-var files so each case prepares fixtures
#     without rewriting the stub bodies.
#   - A REAL temp git repo (no mocking of the git layer) seeded with
#     known commits + tags — the genuine integration surface.
#   - The `claude` stub writes a marker file on every invocation so
#     tests can assert it was NOT called (dry-run / abort paths).
#
# claude-stub invocation shape (the contract this lib commits to):
#   claude -p "<prompt with survivor source text>" \
#          --model "<MODEL>" --output-format json
#   The stub reads CLAUDE_REPLY_FILE for the JSON body to emit on
#   stdout, and appends one line per call to CLAUDE_CALLS_FILE.
#   `claude --output-format json` normally wraps the model reply in
#   an envelope ({"result": "..."}); to keep the stub simple we have
#   the lib tolerate EITHER a bare salience JSON or an enveloped one
#   — the stub emits a bare object and the lib parses it directly.
#
# Run:  bash lib/tests/loom-mine-history.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$LOOM_ROOT/lib/loom-mine-history.sh"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# --- Stub directory --------------------------------------------------
#
# Builds a dir with `gh` and `claude` stubs, PATH-prepended by the
# caller. Behavior is steered by env-var files so each test case sets
# its own fixtures.
#
#   GH_AUTH_OK         — if "1", `gh auth status` exits 0; else exits 1.
#   GH_PR_LIST_FILE    — JSON array emitted by `gh pr list ... --json`.
#   GH_API_FILE        — text emitted by `gh api <path>` (review threads).
#   CLAUDE_REPLY_FILE  — JSON body emitted by `claude -p ...`.
#   CLAUDE_CALLS_FILE  — appended one line per `claude` call (marker).
mk_stubs_dir() {
  local d
  d=$(mktemp -d)

  cat > "$d/gh" <<'EOF'
#!/usr/bin/env bash
# Stub gh.
#   gh auth status               → exit 0 iff GH_AUTH_OK=1
#   gh pr list ... --json ...     → cat GH_PR_LIST_FILE (or [] )
#   gh api <path>                 → cat GH_API_FILE (or empty)
case "$1" in
  auth)
    if [ "${GH_AUTH_OK:-0}" = "1" ]; then exit 0; else
      echo "not logged in" >&2; exit 1; fi
    ;;
  pr)
    # gh pr list ...
    if [ -n "${GH_PR_LIST_FILE:-}" ] && [ -f "$GH_PR_LIST_FILE" ]; then
      cat "$GH_PR_LIST_FILE"
    else
      echo "[]"
    fi
    ;;
  api)
    if [ -n "${GH_API_FILE:-}" ] && [ -f "$GH_API_FILE" ]; then
      cat "$GH_API_FILE"
    fi
    ;;
  *)
    exit 1
    ;;
esac
EOF

  cat > "$d/claude" <<'EOF'
#!/usr/bin/env bash
# Stub claude. Records every invocation as ONE marker line (so call
# counting via `wc -l` is accurate even when the -p prompt is
# multi-line) plus the full argv on a separate detail line (so flag-
# shape assertions can still grep it). Emits the canned salience-JSON.
{
  echo "CALL"                # one line per invocation — count this
  printf 'ARGV %s\n' "$*"    # detail line for --model/--output-format greps
} >> "${CLAUDE_CALLS_FILE:-/dev/null}"
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
# Real temp git repo with a known mix of commits + a release tag. The
# commit shapes exercise the heuristic gate:
#   - "wip: scratch"                  → DROP (wip)
#   - "fixup! earlier"                → DROP (fixup)
#   - "typo"                          → DROP (typo, too short)
#   - "bump deps to v2"               → DROP (bump)
#   - "Revert \"add schema\""         → DROP (revert)
#   - a substantial decision commit touching schema.sql → SURVIVE
#   - a tagged release commit                          → SURVIVE
mk_fixture_repo() {
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

    echo "scratch" > scratch.txt
    git add -A && git -c core.hooksPath=/dev/null commit -q -m "wip: scratch"

    echo "f" > f.txt
    git add -A && git -c core.hooksPath=/dev/null commit -q -m "fixup! earlier"

    echo "t" >> README.md
    git add -A && git -c core.hooksPath=/dev/null commit -q -m "typo"

    echo "deps" > deps.txt
    git add -A && git -c core.hooksPath=/dev/null commit -q -m "bump deps to v2"

    # The decision commit: substantial body, touches a schema file.
    cat > schema.sql <<'SQL'
CREATE TABLE decisions (id INT PRIMARY KEY, body TEXT);
SQL
    git add -A
    git -c core.hooksPath=/dev/null commit -q -m "Add decisions schema

We chose a single-table design over the EAV pattern because query
latency on the decision timeline dominates; normalized EAV would
require N joins per timeline render. Trade-off accepted: schema
migrations are heavier, but reads are the hot path."

    # A revert commit (should be dropped even though substantial).
    echo "reverted" > reverted.txt
    git add -A
    git -c core.hooksPath=/dev/null commit -q -m "Revert \"add schema\"

This reverts commit deadbeef because the migration broke staging."

    # A tagged release commit.
    cat > interfaces.go <<'GO'
package api
// Stable v1.0 interface surface — frozen for downstream consumers.
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

# Source the lib in a subshell with stubs on PATH and run the entry
# point. Echoes stdout+stderr; rc propagated.
run_mine() {
  # $1 = repo path; rest = flags. Env steering vars are inherited
  # from the caller's exported environment.
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
# 0. Lib file exists and sources without side effects.
# =====================================================================
echo "==> 0. Lib shape"

if [ -f "$LIB" ]; then
  pass "lib/loom-mine-history.sh exists"
else
  fail "lib/loom-mine-history.sh missing"
fi

# Sourcing must be side-effect-free and must define the entry fn.
if ( source "$LIB" 2>/dev/null && declare -F loom_mine_history >/dev/null ); then
  pass "sourcing defines loom_mine_history with no error"
else
  fail "sourcing failed or loom_mine_history undefined"
fi

# =====================================================================
# 1. HEURISTIC GATE — junk commits dropped, decision commits survive.
#    Asserted via --dry-run candidates output (no LLM, no spend).
# =====================================================================
echo "==> 1. Heuristic gate filters junk, keeps decisions"

STUBS=$(mk_stubs_dir)
REPO=$(mk_fixture_repo)
OUT=$(mktemp -d)
export GH_AUTH_OK=0   # git-only harvest for this case

out=$(run_mine "$REPO" --dry-run --out "$OUT"); rc=$?
cand="$OUT/candidates.jsonl"

if [ "$rc" -eq 0 ]; then pass "dry-run exits 0"; else fail "dry-run rc=$rc" "$out"; fi

if [ -f "$cand" ]; then
  pass "candidates.jsonl written with --out"
else
  fail "candidates.jsonl not written" "$out"
fi

# Survivors: the schema decision commit + the tagged release commit.
if grep -q "decisions schema" "$cand" 2>/dev/null; then
  pass "decision-file commit survived gate"
else
  fail "decision-file commit was dropped (should survive)" "$(cat "$cand" 2>/dev/null)"
fi

if grep -qi "Freeze v1.0 API" "$cand" 2>/dev/null; then
  pass "release/interface commit survived gate"
else
  fail "release commit was dropped (should survive)" "$(cat "$cand" 2>/dev/null)"
fi

# Junk: wip / fixup / typo / bump / revert all dropped.
for junk in "wip: scratch" "fixup! earlier" "bump deps" "Revert"; do
  if grep -q "$junk" "$cand" 2>/dev/null; then
    fail "junk commit survived gate: '$junk'" "$(cat "$cand" 2>/dev/null)"
  else
    pass "junk commit dropped: '$junk'"
  fi
done

rm -rf "$STUBS" "$(dirname "$REPO")" "$OUT"

# =====================================================================
# 2. --dry-run is side-effect-free: cost preview printed, NO claude
#    call, NO drafts.jsonl.
# =====================================================================
echo "==> 2. --dry-run side-effect-free"

STUBS=$(mk_stubs_dir)
REPO=$(mk_fixture_repo)
OUT=$(mktemp -d)
CALLS=$(mktemp)
rm -f "$CALLS"   # marker must be ABSENT if claude never called
export GH_AUTH_OK=0
export CLAUDE_CALLS_FILE="$CALLS"

out=$(run_mine "$REPO" --dry-run --out "$OUT"); rc=$?

if [ "$rc" -eq 0 ]; then pass "dry-run exits 0"; else fail "dry-run rc=$rc" "$out"; fi

# Cost preview must be printed.
if echo "$out" | grep -qiE "harvested.*->.*gated|est"; then
  pass "cost preview printed in dry-run"
else
  fail "cost preview NOT printed in dry-run" "$out"
fi

if [ ! -f "$CALLS" ]; then
  pass "claude NOT invoked in dry-run (marker absent)"
else
  fail "claude WAS invoked in dry-run" "$(cat "$CALLS")"
fi

if [ ! -f "$OUT/drafts.jsonl" ]; then
  pass "no drafts.jsonl written in dry-run"
else
  fail "drafts.jsonl written in dry-run (should be side-effect-free)"
fi

unset CLAUDE_CALLS_FILE
rm -rf "$STUBS" "$(dirname "$REPO")" "$OUT"

# =====================================================================
# 3. Cost preview cannot be silently bypassed: without --yes and
#    non-interactive, run ABORTS before any claude call; preview
#    still printed.
# =====================================================================
echo "==> 3. No --yes, non-interactive → abort before LLM"

STUBS=$(mk_stubs_dir)
REPO=$(mk_fixture_repo)
OUT=$(mktemp -d)
CALLS=$(mktemp); rm -f "$CALLS"
export GH_AUTH_OK=0
export CLAUDE_CALLS_FILE="$CALLS"

# No --dry-run, no --yes. stdin is /dev/null (non-interactive).
out=$(run_mine "$REPO" --out "$OUT" --model fake </dev/null); rc=$?

if [ "$rc" -ne 0 ]; then
  pass "run aborts (non-zero) without confirmation"
else
  fail "run did NOT abort without confirmation (rc=$rc)" "$out"
fi

if echo "$out" | grep -qiE "harvested.*->.*gated|est"; then
  pass "cost preview printed before abort"
else
  fail "cost preview NOT printed before abort" "$out"
fi

if [ ! -f "$CALLS" ]; then
  pass "claude NOT invoked when confirmation absent"
else
  fail "claude invoked despite missing confirmation" "$(cat "$CALLS")"
fi

unset CLAUDE_CALLS_FILE
rm -rf "$STUBS" "$(dirname "$REPO")" "$OUT"

# =====================================================================
# 4. Trust-gate skip: claude returns {"salient":false} → NO draft for
#    that survivor. {"salient":true,...} → draft emitted.
# =====================================================================
echo "==> 4. Trust-gate: salient=false → no draft, salient=true → draft"

# 4a. All survivors return salient=false → empty drafts.
STUBS=$(mk_stubs_dir)
REPO=$(mk_fixture_repo)
OUT=$(mktemp -d)
REPLY=$(mktemp)
printf '%s' '{"salient":false}' > "$REPLY"
export GH_AUTH_OK=0
export CLAUDE_REPLY_FILE="$REPLY"

out=$(run_mine "$REPO" --out "$OUT" --yes --model fake); rc=$?

if [ "$rc" -eq 0 ]; then pass "salient=false run exits 0"; else fail "rc=$rc" "$out"; fi

if [ ! -s "$OUT/drafts.jsonl" ]; then
  pass "salient=false → no drafts emitted (empty or absent)"
else
  fail "salient=false → drafts emitted anyway" "$(cat "$OUT/drafts.jsonl")"
fi

unset CLAUDE_REPLY_FILE
rm -rf "$STUBS" "$(dirname "$REPO")" "$OUT" "$REPLY"

# 4b. salient=true → at least one draft emitted.
STUBS=$(mk_stubs_dir)
REPO=$(mk_fixture_repo)
OUT=$(mktemp -d)
REPLY=$(mktemp)
printf '%s' '{"salient":true,"verbatim":"We chose a single-table design over EAV.","synthesis":"Read-latency-driven schema choice.","decision":"single-table decisions schema"}' > "$REPLY"
export GH_AUTH_OK=0
export CLAUDE_REPLY_FILE="$REPLY"

out=$(run_mine "$REPO" --out "$OUT" --yes --model fake); rc=$?

if [ "$rc" -eq 0 ]; then pass "salient=true run exits 0"; else fail "rc=$rc" "$out"; fi

if [ -s "$OUT/drafts.jsonl" ]; then
  pass "salient=true → drafts.jsonl non-empty"
else
  fail "salient=true → no drafts emitted" "$out"
fi

unset CLAUDE_REPLY_FILE
rm -rf "$STUBS" "$(dirname "$REPO")" "$OUT" "$REPLY"

# =====================================================================
# 5. Draft shape: verbatim quote, separated synthesis, source anchor
#    (sha + author + date), room=decisions, tag provenance:mined.
# =====================================================================
echo "==> 5. Draft shape"

STUBS=$(mk_stubs_dir)
REPO=$(mk_fixture_repo)
OUT=$(mktemp -d)
REPLY=$(mktemp)
printf '%s' '{"salient":true,"verbatim":"single-table design over EAV","synthesis":"reads are the hot path","decision":"single-table schema"}' > "$REPLY"
export GH_AUTH_OK=0
export CLAUDE_REPLY_FILE="$REPLY"

out=$(run_mine "$REPO" --out "$OUT" --yes --model fake); rc=$?
draft=$(head -1 "$OUT/drafts.jsonl" 2>/dev/null)

if [ -n "$draft" ]; then pass "a draft was emitted"; else fail "no draft to inspect" "$out"; fi

if echo "$draft" | grep -q "single-table design over EAV"; then
  pass "draft carries verbatim quote"
else
  fail "draft missing verbatim" "$draft"
fi

if echo "$draft" | grep -q "reads are the hot path"; then
  pass "draft carries synthesis"
else
  fail "draft missing synthesis" "$draft"
fi

if echo "$draft" | grep -q '"room":"decisions"'; then
  pass "draft room=decisions"
else
  fail "draft missing room=decisions" "$draft"
fi

if echo "$draft" | grep -q "provenance:mined"; then
  pass "draft tagged provenance:mined"
else
  fail "draft missing provenance:mined tag" "$draft"
fi

# Anchor: source SHA (40-hex or abbrev), author, date present.
if echo "$draft" | grep -qiE '"author":"[^"]*Miner'; then
  pass "draft anchor carries author"
else
  fail "draft anchor missing author" "$draft"
fi

if echo "$draft" | grep -qE '"date":"[0-9]{4}'; then
  pass "draft anchor carries date"
else
  fail "draft anchor missing date" "$draft"
fi

if echo "$draft" | grep -qE '"(source_id|id)":"[0-9a-f]{7,40}"'; then
  pass "draft anchor carries source commit SHA"
else
  fail "draft anchor missing source SHA" "$draft"
fi

# drawer_body should combine verbatim + synthesis (separated).
if echo "$draft" | grep -q "drawer_body"; then
  pass "draft carries drawer_body"
else
  fail "draft missing drawer_body" "$draft"
fi

unset CLAUDE_REPLY_FILE
rm -rf "$STUBS" "$(dirname "$REPO")" "$OUT" "$REPLY"

# =====================================================================
# 6. KG triples: subject→decided→object, subject→mined_from→repo,
#    subject→authored_by→author. One set per salient unit.
# =====================================================================
echo "==> 6. KG triples"

STUBS=$(mk_stubs_dir)
REPO=$(mk_fixture_repo)
OUT=$(mktemp -d)
REPLY=$(mktemp)
printf '%s' '{"salient":true,"verbatim":"v","synthesis":"s","decision":"single-table schema"}' > "$REPLY"
export GH_AUTH_OK=0
export CLAUDE_REPLY_FILE="$REPLY"

out=$(run_mine "$REPO" --out "$OUT" --yes --model fake); rc=$?
triples="$OUT/kg-triples.jsonl"

if [ -s "$triples" ]; then pass "kg-triples.jsonl non-empty"; else fail "no kg triples" "$out"; fi

for pred in decided mined_from authored_by; do
  if grep -q "\"$pred\"" "$triples" 2>/dev/null; then
    pass "kg triple predicate present: $pred"
  else
    fail "kg triple predicate missing: $pred" "$(cat "$triples" 2>/dev/null)"
  fi
done

# The `decided` triple must link the SOURCE unit (PR#/SHA) to the
# decision (design: PR#->decided->X), NOT be a tautology where the
# subject equals the object. Pin subject != object so the source
# anchor is recoverable from the graph.
decided_line=$(grep '"predicate":"decided"' "$triples" 2>/dev/null | head -1)
d_subj=$(printf '%s' "$decided_line" | sed -n 's/.*"subject":"\([^"]*\)".*/\1/p')
d_obj=$(printf '%s' "$decided_line"  | sed -n 's/.*"object":"\([^"]*\)".*/\1/p')
if [ -n "$d_subj" ] && [ "$d_subj" != "$d_obj" ]; then
  pass "decided triple links source-id to decision (not a tautology)"
else
  fail "decided triple is tautological (subject==object)" "$decided_line"
fi

# All three triples for one unit must share the SAME source-id subject
# so the graph clusters them on the source (PR#/SHA), not on the
# decision text.
mf_subj=$(grep '"predicate":"mined_from"' "$triples" 2>/dev/null | head -1 | sed -n 's/.*"subject":"\([^"]*\)".*/\1/p')
ab_subj=$(grep '"predicate":"authored_by"' "$triples" 2>/dev/null | head -1 | sed -n 's/.*"subject":"\([^"]*\)".*/\1/p')
if [ -n "$d_subj" ] && [ "$d_subj" = "$mf_subj" ] && [ "$d_subj" = "$ab_subj" ]; then
  pass "all three triples share the same source-id subject"
else
  fail "triple subjects diverge across predicates" "decided=$d_subj mined_from=$mf_subj authored_by=$ab_subj"
fi

unset CLAUDE_REPLY_FILE
rm -rf "$STUBS" "$(dirname "$REPO")" "$OUT" "$REPLY"

# =====================================================================
# 7. gh-absent graceful: gh auth status fails → git-only harvest, no
#    abort, candidates still produced.
# =====================================================================
echo "==> 7. gh-absent graceful degradation"

STUBS=$(mk_stubs_dir)
REPO=$(mk_fixture_repo)
OUT=$(mktemp -d)
export GH_AUTH_OK=0   # auth fails

out=$(run_mine "$REPO" --dry-run --out "$OUT"); rc=$?

if [ "$rc" -eq 0 ]; then
  pass "gh-absent: run does NOT abort (rc=0)"
else
  fail "gh-absent: run aborted (rc=$rc)" "$out"
fi

if [ -s "$OUT/candidates.jsonl" ]; then
  pass "gh-absent: git-only candidates still produced"
else
  fail "gh-absent: no candidates produced" "$out"
fi

rm -rf "$STUBS" "$(dirname "$REPO")" "$OUT"

# =====================================================================
# 8. gh-present: PR harvest contributes candidates. A merged PR with a
#    design-shaped body survives the gate.
# =====================================================================
echo "==> 8. gh-present: PR harvest feeds the gate"

STUBS=$(mk_stubs_dir)
REPO=$(mk_fixture_repo)
OUT=$(mktemp -d)
PRLIST=$(mktemp)
cat > "$PRLIST" <<'EOF'
[{"number":42,"title":"Adopt event-sourcing for the ledger","body":"Design decision: we move the ledger to event-sourcing. RFC discussed at length; breaking change for downstream. closes #17","labels":[{"name":"design"}],"files":[{"path":"ledger/schema.sql"}],"author":{"login":"alice"},"mergedAt":"2026-04-01T10:00:00Z","url":"https://github.com/org/repo/pull/42"}]
EOF
export GH_AUTH_OK=1
export GH_PR_LIST_FILE="$PRLIST"

out=$(run_mine "$REPO" --dry-run --out "$OUT"); rc=$?

if [ "$rc" -eq 0 ]; then pass "gh-present dry-run exits 0"; else fail "rc=$rc" "$out"; fi

if grep -qi "event-sourcing" "$OUT/candidates.jsonl" 2>/dev/null; then
  pass "merged design PR survived the gate"
else
  fail "merged design PR was dropped" "$(cat "$OUT/candidates.jsonl" 2>/dev/null)"
fi

# The candidate should be tagged type=PR with the PR number as id.
if grep -qiE '"(source_)?type":"PR"' "$OUT/candidates.jsonl" 2>/dev/null && \
   grep -q '42' "$OUT/candidates.jsonl" 2>/dev/null; then
  pass "PR candidate tagged type=PR with id=42"
else
  fail "PR candidate not tagged correctly" "$(cat "$OUT/candidates.jsonl" 2>/dev/null)"
fi

unset GH_PR_LIST_FILE
rm -rf "$STUBS" "$(dirname "$REPO")" "$OUT" "$PRLIST"

# =====================================================================
# 9. --max-units=N caps survivors fed to the LLM pass.
# =====================================================================
echo "==> 9. --max-units caps the LLM pass"

STUBS=$(mk_stubs_dir)
REPO=$(mk_fixture_repo)
OUT=$(mktemp -d)
REPLY=$(mktemp); printf '%s' '{"salient":false}' > "$REPLY"
CALLS=$(mktemp); rm -f "$CALLS"
export GH_AUTH_OK=0
export CLAUDE_REPLY_FILE="$REPLY"
export CLAUDE_CALLS_FILE="$CALLS"

# Two survivors exist (schema + release). Cap to 1.
out=$(run_mine "$REPO" --out "$OUT" --yes --model fake --max-units=1); rc=$?

if [ "$rc" -eq 0 ]; then pass "--max-units run exits 0"; else fail "rc=$rc" "$out"; fi

n_calls=0
[ -f "$CALLS" ] && n_calls=$(grep -c '^CALL$' "$CALLS")
if [ "$n_calls" -le 1 ]; then
  pass "--max-units=1 capped LLM calls to $n_calls (<=1)"
else
  fail "--max-units=1 did NOT cap calls (got $n_calls)" "$(cat "$CALLS")"
fi

unset CLAUDE_REPLY_FILE CLAUDE_CALLS_FILE
rm -rf "$STUBS" "$(dirname "$REPO")" "$OUT" "$REPLY"

# =====================================================================
# 10. INTEGRATION: end-to-end against the real git fixture + stubs.
#     Full manifest produced; drafts + triples coherent.
# =====================================================================
echo "==> 10. Integration: full pipeline end-to-end"

STUBS=$(mk_stubs_dir)
REPO=$(mk_fixture_repo)
OUT=$(mktemp -d)
REPLY=$(mktemp)
# salient for everything → both survivors yield drafts.
printf '%s' '{"salient":true,"verbatim":"verbatim text","synthesis":"synthesis text","decision":"a decision"}' > "$REPLY"
CALLS=$(mktemp); rm -f "$CALLS"
export GH_AUTH_OK=0
export CLAUDE_REPLY_FILE="$REPLY"
export CLAUDE_CALLS_FILE="$CALLS"

out=$(run_mine "$REPO" --out "$OUT" --yes --model fake); rc=$?

if [ "$rc" -eq 0 ]; then pass "integration exits 0"; else fail "integration rc=$rc" "$out"; fi

if echo "$out" | grep -qiE "harvested.*->.*gated"; then
  pass "integration printed cost preview"
else
  fail "integration missing cost preview" "$out"
fi

if [ -f "$CALLS" ] && [ "$(grep -c '^CALL$' "$CALLS")" -ge 1 ]; then
  pass "integration invoked claude for survivors"
else
  fail "integration did not invoke claude" "$out"
fi

# claude was called with --model fake and --output-format json.
if grep -q -- "--model fake" "$CALLS" 2>/dev/null && \
   grep -q -- "--output-format json" "$CALLS" 2>/dev/null; then
  pass "claude invoked with --model fake --output-format json"
else
  fail "claude invocation shape wrong" "$(cat "$CALLS" 2>/dev/null)"
fi

if [ -s "$OUT/drafts.jsonl" ] && [ -s "$OUT/kg-triples.jsonl" ]; then
  pass "integration produced full manifest (drafts + triples)"
else
  fail "integration manifest incomplete" "drafts=$(wc -l <"$OUT/drafts.jsonl" 2>/dev/null) triples=$(wc -l <"$OUT/kg-triples.jsonl" 2>/dev/null)"
fi

# Each drafts line should be valid one-object-per-line JSON-ish
# (starts with { ends with }).
bad=0
while IFS= read -r line; do
  case "$line" in
    "{"*"}") : ;;
    *) bad=1 ;;
  esac
done < "$OUT/drafts.jsonl"
if [ "$bad" -eq 0 ]; then
  pass "every drafts.jsonl line is one JSON object"
else
  fail "drafts.jsonl has malformed lines" "$(cat "$OUT/drafts.jsonl")"
fi

unset CLAUDE_REPLY_FILE CLAUDE_CALLS_FILE
rm -rf "$STUBS" "$(dirname "$REPO")" "$OUT" "$REPLY"

# =====================================================================
# Summary
# =====================================================================
echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
