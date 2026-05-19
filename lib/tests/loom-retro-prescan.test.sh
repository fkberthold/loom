#!/usr/bin/env bash
# Fixture tests for scripts/loom-retro-prescan.
#
# Closes loom-z3m.1.1: emit hit-list JSONL per project from CC transcripts,
# rows {session_id, ts, signal_class, evidence_offset_start, evidence_offset_end, raw_excerpt}.
#
# Signal classes (transcript-only — diary deferred to T2 per bead notes):
#   A_steering    user turn <=200 chars matching steering regex AND >=3 preceding
#                 agent tool calls in current session
#   A_diagnostic  user turn matching diagnostic regex (no length filter)
#   B_abandon    >=20 consecutive assistant turns followed by user turn with
#                Jaccard distance >0.7 from concatenated last 5 assistant turns
#   B_reversion  user turn matching explicit-reversion regex
#
# A_upgrade is a per-hit annotation, not a standalone class — the script
# augments an A_steering or A_diagnostic hit with upgrade_weight=1 when the
# next assistant turn matches the upgrade regex.
#
# Env-var overrides for testing:
#   LOOM_RETRO_TRANSCRIPT_DIR   override transcript root
#   LOOM_RETRO_OUTPUT_DIR       override output dir
#   LOOM_RETRO_DAYS             override 14-day mtime filter
#
# Run:  bash lib/tests/loom-retro-prescan.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$LOOM_ROOT/scripts/loom-retro-prescan"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not available"
  exit 0
fi

# ----------------------------------------------------------------------
# Fixture builder — synthesizes a transcript dir with 10 sessions.
# 5 sessions carry known signals; 5 are clean (no hits expected).
# ----------------------------------------------------------------------

# emit_user <out> <session> <content> [meta=0] [sidechain=0]
emit_user() {
  local out="$1" sid="$2" content="$3"
  local meta="${4:-0}" sidechain="${5:-0}"
  jq -nc --arg sid "$sid" --arg c "$content" \
         --argjson meta "$meta" --argjson sc "$sidechain" \
    '{type:"user", sessionId:$sid, isMeta:($meta==1), isSidechain:($sc==1),
      timestamp:"2026-05-18T12:00:00.000Z",
      message:{role:"user", content:$c}}' >> "$out"
}

# emit_assistant <out> <session> <text> [with_tool=0]
emit_assistant() {
  local out="$1" sid="$2" text="$3" tool="${4:-0}"
  if [ "$tool" = "1" ]; then
    jq -nc --arg sid "$sid" --arg t "$text" \
      '{type:"assistant", sessionId:$sid, isSidechain:false,
        timestamp:"2026-05-18T12:00:00.000Z",
        message:{role:"assistant",
                 content:[{type:"text", text:$t},
                          {type:"tool_use", name:"Read", input:{}}]}}' >> "$out"
  else
    jq -nc --arg sid "$sid" --arg t "$text" \
      '{type:"assistant", sessionId:$sid, isSidechain:false,
        timestamp:"2026-05-18T12:00:00.000Z",
        message:{role:"assistant",
                 content:[{type:"text", text:$t}]}}' >> "$out"
  fi
}

make_fixture() {
  local fix; fix=$(mktemp -d)
  local td="$fix/transcripts" od="$fix/out"
  mkdir -p "$td" "$od"

  # --- STRUGGLE FIXTURES (expect 5 hits total) ---

  # s1: A_steering — 5 preceding tool calls, user "no wait" (<=200 chars)
  local f="$td/s1.jsonl"
  for i in 1 2 3 4 5; do emit_assistant "$f" "s1" "doing thing $i" 1; done
  emit_user "$f" "s1" "no wait"

  # s2: A_diagnostic — long user turn matches diagnostic regex
  f="$td/s2.jsonl"
  emit_assistant "$f" "s2" "ok let me try this approach" 1
  emit_user "$f" "s2" "you should have checked the spec first, I think we're going down the wrong path and this whole thing needs to back up"

  # s3: A_steering w/ A_upgrade — preceding tool calls, steering word,
  #     and NEXT assistant turn contains "you're right" → upgrade_weight=1
  f="$td/s3.jsonl"
  for i in 1 2 3 4; do emit_assistant "$f" "s3" "step $i" 1; done
  emit_user "$f" "s3" "stop, that's wrong"
  emit_assistant "$f" "s3" "you're right, apologies — let me back up" 0

  # s4: B_reversion — 8 assistant turns then explicit reversion phrase
  f="$td/s4.jsonl"
  for i in 1 2 3 4 5 6 7 8; do emit_assistant "$f" "s4" "doing $i" 1; done
  emit_user "$f" "s4" "let me back up, this is the wrong approach"

  # s5: B_abandon — 22 consecutive assistant turns on topic X,
  #     then substantive user turn on topic Y (Jaccard distance > 0.7,
  #     >=10 tokens to clear the short-continuation guard)
  f="$td/s5.jsonl"
  for i in $(seq 1 22); do
    emit_assistant "$f" "s5" "kubernetes pod deployment yaml manifest container registry" 1
  done
  emit_user "$f" "s5" "totally unrelated, switching topic to weather forecast climate barometer humidity readings around paris france"

  # --- CLEAN FIXTURES (expect 0 hits) ---

  # c1: continue/agreement language; tool calls present but no steering word
  f="$td/c1.jsonl"
  for i in 1 2 3 4 5; do emit_assistant "$f" "c1" "step $i" 1; done
  emit_user "$f" "c1" "great, continue please"

  # c2: isMeta=1 user turn — must be skipped even though content matches
  f="$td/c2.jsonl"
  for i in 1 2 3 4; do emit_assistant "$f" "c2" "step $i" 1; done
  emit_user "$f" "c2" "no actually wait" 1 0

  # c3: isSidechain=1 user turn — must be skipped
  f="$td/c3.jsonl"
  for i in 1 2 3 4; do emit_assistant "$f" "c3" "step $i" 1; done
  emit_user "$f" "c3" "you should have done that differently" 0 1

  # c4: slash-command turn (starts with <command-name>) — must be skipped
  f="$td/c4.jsonl"
  for i in 1 2 3 4; do emit_assistant "$f" "c4" "step $i" 1; done
  emit_user "$f" "c4" "<command-name>/clear</command-name>"

  # c5: long-run abandonment guard — 22 assistant turns then SIMILAR user turn
  #     (Jaccard distance < 0.7 — same topic) — must NOT fire B_abandon
  f="$td/c5.jsonl"
  for i in $(seq 1 22); do
    emit_assistant "$f" "c5" "kubernetes pod deployment manifest container" 1
  done
  emit_user "$f" "c5" "ok so for that kubernetes pod manifest what container image"

  # c6: precision guard — "stop" as a noun mid-sentence with preceding tools.
  # The pre-tighten regex fired on "first stop"; the position-constrained
  # regex must reject (no comma / sentence boundary directly before "stop").
  f="$td/c6.jsonl"
  for i in 1 2 3 4 5; do emit_assistant "$f" "c6" "step $i" 1; done
  emit_user "$f" "c6" "ok we are at the first stop here"

  # c7: precision guard — "but" as conjunction. The word is dropped from
  # the regex entirely; turn must NOT fire even though it begins with But.
  f="$td/c7.jsonl"
  for i in 1 2 3 4 5; do emit_assistant "$f" "c7" "step $i" 1; done
  emit_user "$f" "c7" "But aren't we going to see this elsewhere"

  # c8: precision guard — "don't" mid-sentence (no comma/period right before).
  # Must NOT fire on "projects that I don't own" shape.
  f="$td/c8.jsonl"
  for i in 1 2 3 4 5; do emit_assistant "$f" "c8" "step $i" 1; done
  emit_user "$f" "c8" "I think A is fine, the concern is not cluttering up projects that I don't own"

  # c9: precision guard — short continuation turn after long agent activity.
  # Without the ">=10 distinct tokens" guard, Jaccard distance of "yes" or
  # "grab the next" vs the assistant ring is trivially ~1.0 and B_abandon
  # would fire 100% false positives across normal "proceed" exchanges.
  f="$td/c9.jsonl"
  for i in $(seq 1 22); do
    emit_assistant "$f" "c9" "kubernetes pod deployment yaml manifest container" 1
  done
  emit_user "$f" "c9" "yes"

  # c10: precision guard — slightly longer but still short proceed turn.
  f="$td/c10.jsonl"
  for i in $(seq 1 22); do
    emit_assistant "$f" "c10" "long agent activity about deployments and manifests" 1
  done
  emit_user "$f" "c10" "Grab the next in queue."

  echo "$fix"
}

# ----------------------------------------------------------------------
# Tests
# ----------------------------------------------------------------------

run() {
  local name="$1"; shift
  echo "TEST: $name"
}

# Sanity: script exists and is executable
run "script exists and is executable"
if [ -x "$SCRIPT" ]; then pass "executable at scripts/loom-retro-prescan"
else fail "script missing or not executable at $SCRIPT"; fi

# Sanity: usage on bad invocation
run "usage on missing/bogus project arg"
out=$("$SCRIPT" 2>&1) ; rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -qi 'usage'; then
  pass "exits non-zero with usage on missing arg"
else
  fail "expected non-zero+usage on missing arg" "rc=$rc out=$out"
fi

# Build the fixture corpus once for the remaining tests
FIX=$(make_fixture)
trap 'rm -rf "$FIX"' EXIT
OUT_DIR="$FIX/out"
TR_DIR="$FIX/transcripts"

run "produces output file at \$OUT_DIR/loom-hits.jsonl"
LOOM_RETRO_TRANSCRIPT_DIR="$TR_DIR" LOOM_RETRO_OUTPUT_DIR="$OUT_DIR" \
  LOOM_RETRO_DAYS=9999 "$SCRIPT" loom >/dev/null 2>&1
if [ -f "$OUT_DIR/loom-hits.jsonl" ]; then
  pass "output file exists"
else
  fail "output file not created"
fi

run "every hit row has all 6 required schema fields"
if [ -f "$OUT_DIR/loom-hits.jsonl" ]; then
  bad=$(jq -c 'select(
        (has("session_id")|not) or
        (has("ts")|not) or
        (has("signal_class")|not) or
        (has("evidence_offset_start")|not) or
        (has("evidence_offset_end")|not) or
        (has("raw_excerpt")|not))' "$OUT_DIR/loom-hits.jsonl" | head -1)
  if [ -z "$bad" ]; then pass "schema fields present on every row"
  else fail "row missing required fields" "$bad"; fi
else
  fail "output file missing — cannot verify schema"
fi

run "5 struggle fixtures produce >=5 hits (one+ per session s1..s5)"
if [ -f "$OUT_DIR/loom-hits.jsonl" ]; then
  for sid in s1 s2 s3 s4 s5; do
    n=$(jq -c --arg s "$sid" 'select(.session_id==$s)' "$OUT_DIR/loom-hits.jsonl" | wc -l)
    if [ "$n" -ge 1 ]; then
      pass "session $sid produced $n hit(s)"
    else
      fail "session $sid produced 0 hits (expected >=1)"
    fi
  done
else
  fail "output missing"
fi

run "s1 hit is classified A_steering"
if [ -f "$OUT_DIR/loom-hits.jsonl" ]; then
  cls=$(jq -r 'select(.session_id=="s1") | .signal_class' "$OUT_DIR/loom-hits.jsonl" | head -1)
  if [ "$cls" = "A_steering" ]; then pass "s1 -> A_steering"
  else fail "s1 classified as '$cls', expected A_steering"; fi
fi

run "s2 hit is classified A_diagnostic"
if [ -f "$OUT_DIR/loom-hits.jsonl" ]; then
  cls=$(jq -r 'select(.session_id=="s2") | .signal_class' "$OUT_DIR/loom-hits.jsonl" | head -1)
  if [ "$cls" = "A_diagnostic" ]; then pass "s2 -> A_diagnostic"
  else fail "s2 classified as '$cls', expected A_diagnostic"; fi
fi

run "s3 hit carries upgrade_weight=1 (next-turn 'you're right')"
if [ -f "$OUT_DIR/loom-hits.jsonl" ]; then
  w=$(jq -r 'select(.session_id=="s3") | (.upgrade_weight // 0)' "$OUT_DIR/loom-hits.jsonl" | head -1)
  if [ "$w" = "1" ]; then pass "s3 upgrade_weight=1"
  else fail "s3 upgrade_weight='$w', expected 1"; fi
fi

run "s4 hit is classified B_reversion"
if [ -f "$OUT_DIR/loom-hits.jsonl" ]; then
  cls=$(jq -r 'select(.session_id=="s4") | .signal_class' "$OUT_DIR/loom-hits.jsonl" | head -1)
  if [ "$cls" = "B_reversion" ]; then pass "s4 -> B_reversion"
  else fail "s4 classified as '$cls', expected B_reversion"; fi
fi

run "s5 hit is classified B_abandon"
if [ -f "$OUT_DIR/loom-hits.jsonl" ]; then
  cls=$(jq -r 'select(.session_id=="s5") | .signal_class' "$OUT_DIR/loom-hits.jsonl" | head -1)
  if [ "$cls" = "B_abandon" ]; then pass "s5 -> B_abandon"
  else fail "s5 classified as '$cls', expected B_abandon"; fi
fi

run "10 clean fixtures produce 0 hits (c1..c10)"
if [ -f "$OUT_DIR/loom-hits.jsonl" ]; then
  for sid in c1 c2 c3 c4 c5 c6 c7 c8 c9 c10; do
    n=$(jq -c --arg s "$sid" 'select(.session_id==$s)' "$OUT_DIR/loom-hits.jsonl" | wc -l)
    if [ "$n" -eq 0 ]; then
      pass "session $sid produced 0 hits"
    else
      fail "session $sid produced $n hits (expected 0)" \
        "$(jq -c --arg s "$sid" 'select(.session_id==$s)' "$OUT_DIR/loom-hits.jsonl")"
    fi
  done
fi

run "14-day mtime filter excludes old sessions"
# Touch s1 to 30 days ago; with default DAYS=14 it should be excluded.
touch -d '30 days ago' "$TR_DIR/s1.jsonl"
LOOM_RETRO_TRANSCRIPT_DIR="$TR_DIR" LOOM_RETRO_OUTPUT_DIR="$OUT_DIR" \
  "$SCRIPT" loom >/dev/null 2>&1
n=$(jq -c 'select(.session_id=="s1")' "$OUT_DIR/loom-hits.jsonl" 2>/dev/null | wc -l)
if [ "$n" -eq 0 ]; then
  pass "s1 (mtime 30d) excluded by default 14d filter"
else
  fail "s1 (mtime 30d) included despite 14d filter (got $n hits)"
fi

run "evidence_offset_{start,end} are integers and start<=end"
LOOM_RETRO_TRANSCRIPT_DIR="$TR_DIR" LOOM_RETRO_OUTPUT_DIR="$OUT_DIR" \
  LOOM_RETRO_DAYS=9999 "$SCRIPT" loom >/dev/null 2>&1
bad=$(jq -c 'select(
        (.evidence_offset_start|type!="number") or
        (.evidence_offset_end|type!="number") or
        (.evidence_offset_start > .evidence_offset_end))' \
        "$OUT_DIR/loom-hits.jsonl" | head -1)
if [ -z "$bad" ]; then pass "offset fields are well-formed integers"
else fail "malformed offset fields" "$bad"; fi

# ----------------------------------------------------------------------
echo
echo "RESULTS: $passed passed, $failed failed"
[ "$failed" -eq 0 ] && exit 0 || exit 1
