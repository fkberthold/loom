#!/usr/bin/env bash
# Fixture tests for scripts/loom-stage-spend.
#
# Closes loom-0ahj.3 (Move-3a / design-doc 14f08e6d D7): a CENTRAL-SIDE
# transcript reader (NOT a hook — sidechain Stop/SubagentStop hooks do not
# fire, per loom-7zy/loom-98x) that walks the session's subagent
# agent-*.jsonl transcripts, reads cache_read_input_tokens +
# cache_creation_input_tokens (+ output_tokens) off each worker's
# first/last assistant records (loom-7zy proved these parseable),
# attributes spend per stage (test-author / implementer / verify — central
# knows dispatch order), and emits per-stage spend NET of the ~9-20K
# invariant SessionStart preamble (loom-nsb).
#
# RED invariant (from the bead):
#   INVARIANT: loom-stage-spend emits per-stage
#   (test-author/implementer/verify) token spend net of the invariant
#   SessionStart preamble.
#
# The transcript-walk engine mirrors scripts/loom-retro-prescan (sibling):
# find agent-*.jsonl under a transcript dir, jq the usage block off each
# assistant record.
#
# Spend model (per worker transcript):
#   gross = last_assistant(cache_read + cache_creation) + sum(output)
#   net   = gross - PREAMBLE_TOKENS         (one preamble charge per worker)
# Per-stage attribution: central supplies the ordered dispatch list
# (stage:transcript), so each worker maps to exactly one stage.
#
# Env overrides (for tests):
#   LOOM_STAGE_SPEND_TRANSCRIPT_DIR   transcript root to walk
#   LOOM_STAGE_SPEND_PREAMBLE         preamble tokens to net out (default ~14000)
#
# Run:  bash lib/tests/loom-stage-spend.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$LOOM_ROOT/scripts/loom-stage-spend"
WS="$LOOM_ROOT/scripts/workflow-state"
SL="$LOOM_ROOT/scripts/statusline.sh"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not available"
  exit 0
fi

# ----------------------------------------------------------------------
# Fixture builder — synthesizes a subagents/ dir with three agent-*.jsonl
# worker transcripts carrying KNOWN token counts so the per-stage net
# arithmetic is fully deterministic.
#
# Convention (matching real CC transcripts): each assistant record carries
# its usage block at .message.usage.
# ----------------------------------------------------------------------

# emit_assistant <file> <cache_read> <cache_creation> <output>
emit_assistant() {
  local out="$1" cr="$2" cc="$3" o="$4"
  jq -nc --argjson cr "$cr" --argjson cc "$cc" --argjson o "$o" \
    '{type:"assistant", isSidechain:false,
      timestamp:"2026-06-09T12:00:00.000Z",
      message:{role:"assistant",
               content:[{type:"text", text:"work"}],
               usage:{input_tokens:1,
                      cache_read_input_tokens:$cr,
                      cache_creation_input_tokens:$cc,
                      output_tokens:$o}}}' >> "$out"
}

# emit_user <file> <text>  (tool_result wrapper / non-assistant noise)
emit_user() {
  local out="$1" text="$2"
  jq -nc --arg t "$text" \
    '{type:"user", isSidechain:false,
      timestamp:"2026-06-09T12:00:00.000Z",
      message:{role:"user", content:$t}}' >> "$out"
}

# Known fixture token counts.
#   PREAMBLE netted per worker = 10000
#
#   test-author worker (agent-aaa):
#     first asst: cr=7000  cc=23000 out=5
#     ...middle records...
#     last  asst: cr=40000 cc=500   out=200
#     gross = last_cr(40000) + last_cc(500) + sum_out(5+200) = 40705
#     net   = 40705 - 10000 = 30705
#
#   implementer worker (agent-bbb):
#     first asst: cr=8000  cc=22000 out=10
#     last  asst: cr=90000 cc=1000  out=800
#     gross = 90000 + 1000 + (10+800) = 91810
#     net   = 91810 - 10000 = 81810
#
#   verify worker (agent-ccc):
#     single asst: cr=8000 cc=20000 out=300  (first==last)
#     gross = 8000 + 20000 + 300 = 28300
#     net   = 28300 - 10000 = 18300
PREAMBLE=10000
EXP_TESTAUTHOR_NET=30705
EXP_IMPLEMENTER_NET=81810
EXP_VERIFY_NET=18300

make_fixture() {
  local fix; fix=$(mktemp -d)
  local sub="$fix/subagents"
  mkdir -p "$sub"

  # test-author: first + a middle + last assistant record
  local f="$sub/agent-aaa.jsonl"
  emit_assistant "$f" 7000 23000 5
  emit_user "$f" "tool result"
  emit_assistant "$f" 20000 800 100
  emit_user "$f" "tool result"
  emit_assistant "$f" 40000 500 200

  # implementer: first + last (two records)
  f="$sub/agent-bbb.jsonl"
  emit_assistant "$f" 8000 22000 10
  emit_user "$f" "tool result"
  emit_assistant "$f" 90000 1000 800

  # verify: single assistant record (first == last)
  f="$sub/agent-ccc.jsonl"
  emit_assistant "$f" 8000 20000 300

  echo "$fix"
}

# ----------------------------------------------------------------------
# Tests
# ----------------------------------------------------------------------

run() { echo "TEST: $1"; }

# 1. script exists and is executable
run "script exists and is executable"
if [ -x "$SCRIPT" ]; then pass "executable at scripts/loom-stage-spend"
else fail "script missing or not executable at $SCRIPT"; fi

# 2. usage on missing args
run "usage on missing args"
out=$("$SCRIPT" 2>&1); rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -qi 'usage'; then
  pass "exits non-zero + usage when no stage:transcript args given"
else
  fail "expected non-zero+usage on missing args" "rc=$rc out=$out"
fi

# Build the fixture corpus.
FIX=$(make_fixture)
trap 'rm -rf "$FIX"' EXIT
SUB="$FIX/subagents"

# 3. JSON output carries one object per stage, with net field
run "emits one JSON object per stage with net spend (NET of preamble)"
out=$(LOOM_STAGE_SPEND_TRANSCRIPT_DIR="$SUB" LOOM_STAGE_SPEND_PREAMBLE="$PREAMBLE" \
  "$SCRIPT" --json test-author:agent-aaa implementer:agent-bbb verify:agent-ccc 2>/dev/null)
rc=$?
if [ "$rc" -eq 0 ] && [ -n "$out" ]; then
  pass "ran cleanly and produced JSON output"
else
  fail "no JSON output / non-zero exit (rc=$rc)" "$out"
fi

# 4. RED INVARIANT — per-stage net spend matches the known arithmetic.
run "per-stage net spend is correct (gross minus preamble) — RED invariant"
ta=$(printf '%s\n' "$out" | jq -r 'select(.stage=="test-author") | .net' 2>/dev/null)
im=$(printf '%s\n' "$out" | jq -r 'select(.stage=="implementer") | .net' 2>/dev/null)
ve=$(printf '%s\n' "$out" | jq -r 'select(.stage=="verify") | .net' 2>/dev/null)
ok=1
[ "$ta" = "$EXP_TESTAUTHOR_NET" ] || { ok=0; echo "    test-author net=$ta expected $EXP_TESTAUTHOR_NET"; }
[ "$im" = "$EXP_IMPLEMENTER_NET" ] || { ok=0; echo "    implementer net=$im expected $EXP_IMPLEMENTER_NET"; }
[ "$ve" = "$EXP_VERIFY_NET" ] || { ok=0; echo "    verify net=$ve expected $EXP_VERIFY_NET"; }
if [ "$ok" = "1" ]; then
  pass "test-author=$ta implementer=$im verify=$ve (all net of $PREAMBLE preamble)"
else
  fail "per-stage net spend mismatch"
fi

# 5. gross is also reported and equals net + preamble
run "gross is reported and gross == net + preamble for each stage"
bad=$(printf '%s\n' "$out" | jq -c --argjson p "$PREAMBLE" \
  'select((.gross - .net) != $p)' 2>/dev/null | head -1)
if [ -z "$bad" ]; then pass "gross - net == preamble on every stage row"
else fail "a stage row violates gross-net==preamble" "$bad"; fi

# 6. preamble is netted ONCE per worker — verify net != gross (preamble > 0)
run "preamble actually netted out (net strictly below gross)"
n_violations=$(printf '%s\n' "$out" | jq -c 'select(.net >= .gross)' 2>/dev/null | wc -l)
if [ "$n_violations" -eq 0 ]; then pass "every stage net < gross (preamble subtracted)"
else fail "$n_violations stage(s) had net >= gross — preamble not netted"; fi

# 7. default preamble lands in the documented ~9-20K invariant band
run "default preamble (no override) lands in 9-20K invariant band (loom-nsb)"
def=$(LOOM_STAGE_SPEND_TRANSCRIPT_DIR="$SUB" \
  "$SCRIPT" --preamble-default 2>/dev/null)
if [ -n "$def" ] && [ "$def" -ge 9000 ] 2>/dev/null && [ "$def" -le 20000 ] 2>/dev/null; then
  pass "default preamble $def within [9000,20000]"
else
  fail "default preamble '$def' outside [9000,20000]"
fi

# 8. missing transcript for a stage degrades gracefully (skip, no crash)
run "missing transcript for a stage is skipped, not crashed"
out2=$(LOOM_STAGE_SPEND_TRANSCRIPT_DIR="$SUB" LOOM_STAGE_SPEND_PREAMBLE="$PREAMBLE" \
  "$SCRIPT" --json test-author:agent-aaa implementer:agent-DOESNOTEXIST 2>/dev/null)
rc=$?
ta2=$(printf '%s\n' "$out2" | jq -r 'select(.stage=="test-author") | .net' 2>/dev/null)
if [ "$rc" -eq 0 ] && [ "$ta2" = "$EXP_TESTAUTHOR_NET" ]; then
  pass "present stage still computed; missing transcript skipped without crash"
else
  fail "missing transcript caused crash or wrong value (rc=$rc ta=$ta2)" "$out2"
fi

# ----------------------------------------------------------------------
# Tee-to-workflow-state + statusline surfacing (additive — must not break
# existing fields).
# ----------------------------------------------------------------------

mk_project() {
  local d; d=$(mktemp -d)
  mkdir -p "$d/.claude" "$d/.beads"
  printf '{"v": 1, "mode": "full"}\n' > "$d/.claude/workflow.json"
  printf '{"v":1,"mode":"full","activity":"feature","bead":"loom-aaa","stage":"verify","updated":"2026-06-06T00:00:00Z"}\n' \
    > "$d/.claude/workflow-state.json"
  printf '%s' "$d"
}

# 9. --tee writes a stage_spend tally into workflow-state without
#    clobbering existing fields.
run "--tee writes stage_spend into workflow-state additively"
proj=$(mk_project)
LOOM_STAGE_SPEND_TRANSCRIPT_DIR="$SUB" LOOM_STAGE_SPEND_PREAMBLE="$PREAMBLE" \
  "$SCRIPT" --tee --start-dir="$proj" \
  test-author:agent-aaa implementer:agent-bbb verify:agent-ccc >/dev/null 2>&1
teed=$(bash "$WS" get stage_spend "$proj" 2>/dev/null)
existing=$(bash "$WS" get bead "$proj" 2>/dev/null)
if [ -n "$teed" ] && [ "$existing" = "loom-aaa" ]; then
  pass "stage_spend teed ('$teed') and existing bead field preserved"
else
  fail "tee broke existing fields or wrote nothing (stage_spend='$teed' bead='$existing')"
fi

# 10. statusline still renders cleanly with the new field present
run "statusline renders WITH stage_spend present (additive, no breakage)"
sl=$(cd "$proj" && printf '{"cwd":"%s"}' "$proj" | bash "$SL" 2>/dev/null)
if echo "$sl" | grep -q 'WORKFLOW:'; then
  pass "statusline emits WORKFLOW line with stage_spend present: $sl"
else
  fail "statusline broke with stage_spend present" "$sl"
fi
rm -rf "$proj"

# 11. workflow-state set of an UNRELATED field still round-trips with
#     stage_spend already in the file (no regression to the merge logic).
run "workflow-state set unrelated field round-trips alongside stage_spend"
proj=$(mk_project)
bash "$WS" set stage_spend="test-author:30705" --start-dir="$proj" >/dev/null 2>&1
bash "$WS" set stage=close --start-dir="$proj" >/dev/null 2>&1
ss=$(bash "$WS" get stage_spend "$proj" 2>/dev/null)
st=$(bash "$WS" get stage "$proj" 2>/dev/null)
if [ "$ss" = "test-author:30705" ] && [ "$st" = "close" ]; then
  pass "stage_spend survives an unrelated set; both fields present"
else
  fail "merge regression (stage_spend='$ss' stage='$st')"
fi
rm -rf "$proj"

# ----------------------------------------------------------------------
echo
echo "RESULTS: $passed passed, $failed failed"
[ "$failed" -eq 0 ] && exit 0 || exit 1
