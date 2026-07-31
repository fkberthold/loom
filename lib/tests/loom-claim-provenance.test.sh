#!/usr/bin/env bash
# Fixture tests for scripts/loom-claim-provenance.
#
# Pins loom-myhi.1 (T1 of epic loom-myhi; design-doc drawer
# drawer_loom_decisions_1a296178707cdc55c872b467, decisions D3 + D4): a
# CENTRAL-SIDE transcript reader — NOT a hook. Stop/SubagentStop do not
# reliably fire on sidechains (docs/reference/claude-code-hook-semantics.md;
# loom-0ahj D7, codified by loom-z3m.9), so no hook can observe a dispatched
# worker's return. The reader walks the session's subagent agent-*.jsonl
# transcripts the same way scripts/loom-stage-spend does, and its interface
# deliberately MIRRORS that sibling: <transcript> is an `agent-XXXX[.jsonl]`
# basename OR a path, `--json` switches to machine output, exit code carries
# the verdict.
#
# RED spec (verbatim from the bead):
#   Given a worker transcript whose report cites `go test -run TestScan`
#   When  that command does not appear among the worker's tool calls
#   Then  the reader FAILS, naming the claim and the missing command
#
#   Given an in-scope subagent report containing zero evidence slots
#   When  the reader runs over it
#   Then  the reader FAILS (non-zero exit) and its message names the report
#
#   Given a report with N claims marked INFERRED and all citations resolvable
#   When  the reader runs over it
#   Then  the reader SUCCEEDS (zero exit) and emits the N claims as a worklist
#
# EVIDENCE-SLOT FORMAT (D2). Each load-bearing claim line ends in a bracketed
# slot carrying either a citation or the literal marker INFERRED:
#     FIFO ordering is broken by the map range.   [INFERRED]
#     The deleted test pinned FIFO.               [test_methods.go:151]
#     All 4 mutants die under the new test.       [go test -run TestScan -count=1 -> 4/4]
# A slot containing ` -> ` is a COMMAND citation; the command is the text
# before the arrow, the result is the text after. A slot of the `path:line`
# shape is a FILE citation. `INFERRED` is the bare marker.
#
# THE GATE IS EXACTLY TWO MECHANICAL CONDITIONS — do not widen it (D4):
#   F1. the FINAL report carries ZERO evidence slots            -> non-zero
#   F2. the report cites a command absent from that worker's
#       tool calls                                              -> non-zero
# Everything else SUCCEEDS, emitting every INFERRED claim as a worklist.
# The reader must NEVER judge whether an INFERRED claim is TRUE — that is
# attended judgment, and gating it produces a rubber-stamp in the
# alert-fatigue zone. Test 7 pins that non-behaviour; tests 9 + 10 pin the
# two other ways the gate could wrongly widen (file citations are NOT
# resolved against the filesystem; zero INFERRED is NOT zero slots).
#
# Env overrides (for tests), mirroring LOOM_STAGE_SPEND_TRANSCRIPT_DIR:
#   LOOM_CLAIM_PROVENANCE_TRANSCRIPT_DIR   dir to resolve bare agent-* names
#
# Run:  bash lib/tests/loom-claim-provenance.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$LOOM_ROOT/scripts/loom-claim-provenance"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }
run() { echo "TEST: $1"; }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not available"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SUB="$TMP/subagents"
mkdir -p "$SUB"

# ----------------------------------------------------------------------
# Fixture builders — synthesize subagent transcripts in the shape the
# Claude Code harness writes: one JSONL record per line, assistant records
# carrying content[] blocks that are either {type:"text"} or
# {type:"tool_use", name:"Bash", input:{command:...}}.
# ----------------------------------------------------------------------

# emit_bash <file> <command>   — one assistant record making a Bash tool call
emit_bash() {
  local out="$1" cmd="$2"
  jq -nc --arg c "$cmd" \
    '{type:"assistant", isSidechain:true,
      timestamp:"2026-07-31T12:00:00.000Z",
      message:{role:"assistant",
               content:[{type:"tool_use", id:"toolu_01", name:"Bash",
                         input:{command:$c, description:"step"}}]}}' >> "$out"
}

# emit_read <file> <path>  — a NON-Bash tool call (no .input.command).
# Present so a reader that blindly reads .input.command trips over a null.
emit_read() {
  local out="$1" p="$2"
  jq -nc --arg p "$p" \
    '{type:"assistant", isSidechain:true,
      timestamp:"2026-07-31T12:00:00.000Z",
      message:{role:"assistant",
               content:[{type:"tool_use", id:"toolu_02", name:"Read",
                         input:{file_path:$p}}]}}' >> "$out"
}

# emit_result <file> <text>  — the user-role tool_result record between calls
emit_result() {
  local out="$1" text="$2"
  jq -nc --arg t "$text" \
    '{type:"user", isSidechain:true,
      timestamp:"2026-07-31T12:00:00.000Z",
      message:{role:"user", content:$t}}' >> "$out"
}

# emit_text <file> <text>  — an assistant TEXT record. The LAST one in a
# transcript is the worker's FINAL report; earlier ones are in-flight prose
# and are NOT the report. Pinned from both directions: agent-nocite (mid
# prose must not RESCUE a slotless report) and agent-midbogus (mid prose
# must not CONDEMN a clean one).
emit_text() {
  local out="$1" text="$2"
  jq -nc --arg t "$text" \
    '{type:"assistant", isSidechain:true,
      timestamp:"2026-07-31T12:00:00.000Z",
      message:{role:"assistant", content:[{type:"text", text:$t}]}}' >> "$out"
}

# --- agent-good: 2 INFERRED claims, all citations resolvable ----------
# The command citation is `go test -run TestScan -count=1` while the tool
# call that ran it was decorated (`2>&1 | tail -5`), so matching must be
# lenient enough not to fire (test 8). The file citation points at a file
# that does NOT exist on disk — file citations are not resolved (test 10).
GOOD="$SUB/agent-good.jsonl"
emit_bash   "$GOOD" 'go test -run TestScan -count=1 2>&1 | tail -5'
emit_result "$GOOD" 'ok  4/4'
emit_read   "$GOOD" 'test_methods.go'
emit_result "$GOOD" '151: // FIFO'
emit_bash   "$GOOD" 'grep -n FIFO test_methods.go'
emit_result "$GOOD" '151: // FIFO'
emit_text   "$GOOD" 'Running the suite now.'
emit_text   "$GOOD" 'Bead complete. Report below.

FIFO ordering is broken by the map range.   [INFERRED]
The map iteration order is unspecified.   [INFERRED]
The deleted test pinned FIFO.   [test_methods.go:151]
All 4 mutants die under the new test.   [go test -run TestScan -count=1 -> 4/4]'

# --- agent-nocite: FINAL report has ZERO evidence slots (F1) ----------
# A MID-transcript text record DOES carry a slot. A reader that scans all
# assistant text instead of the FINAL report would wrongly pass this.
NOCITE="$SUB/agent-nocite.jsonl"
emit_bash   "$NOCITE" 'ls -la'
emit_result "$NOCITE" 'total 0'
emit_text   "$NOCITE" 'Early note: the build is clean.   [ls -la -> total 0]'
emit_text   "$NOCITE" 'Everything works fine now and the bead is done. I refactored the
handler, tightened the loop, and the suite is green.'

# --- agent-badcmd: cites a command absent from the tool calls (F2) -----
BADCMD="$SUB/agent-badcmd.jsonl"
emit_bash   "$BADCMD" 'ls -la'
emit_result "$BADCMD" 'total 0'
emit_bash   "$BADCMD" 'cat README.md'
emit_result "$BADCMD" '# readme'
emit_text   "$BADCMD" 'Implementation landed.

All 4 mutants die under the new test.   [go test -run TestScan -count=1 -> 4/4]
The helper was already present.   [helpers.sh:12]'

# --- agent-midbogus: a MID-transcript slot cites a never-run command ---
# The FINAL report is clean, so the verdict is SUCCESS. A reader that
# scanned all assistant text instead of the final report would find
# `go test -run TestNeverRan -count=1` among the "citations", miss it in
# the tool calls, and wrongly fire F2. This is the FINAL-report pin in the
# positive direction (a crash cannot satisfy it).
MIDBOGUS="$SUB/agent-midbogus.jsonl"
emit_bash   "$MIDBOGUS" 'echo hi'
emit_result "$MIDBOGUS" 'hi'
emit_text   "$MIDBOGUS" 'Interim: the mutants all died.   [go test -run TestNeverRan -count=1 -> 9/9]'
emit_text   "$MIDBOGUS" 'Done.

The loop is off by one.   [INFERRED]
The probe printed hi.   [echo hi -> hi]'

# --- agent-wild: INFERRED claims that are false/unverifiable ----------
# All citations resolvable => SUCCEEDS. The reader does not judge truth.
WILD="$SUB/agent-wild.jsonl"
emit_bash   "$WILD" 'echo hello'
emit_result "$WILD" 'hello'
emit_text   "$WILD" 'Analysis done.

The moon is made of cheese and that causes the deadlock.   [INFERRED]
Every user on earth will hit this within one second.   [INFERRED]
The echo probe printed hello.   [echo hello -> hello]'

# --- agent-allcited: slots present, ZERO of them INFERRED -------------
# N=0 boundary: zero INFERRED is NOT the F1 condition (which is zero
# SLOTS), so this SUCCEEDS with an empty worklist. Its file citation names
# a file that does not exist, pinning that file citations go unresolved.
ALLCITED="$SUB/agent-allcited.jsonl"
emit_bash   "$ALLCITED" 'shellcheck scripts/foo'
emit_result "$ALLCITED" 'no findings'
emit_text   "$ALLCITED" 'Cleanup complete.

The lint pass is clean.   [shellcheck scripts/foo -> no findings]
The helper lives here.   [nonexistent_file_xyz.go:42]'

# ----------------------------------------------------------------------
# Reader harness. Output always lands in a FILE which assertions grep
# DIRECTLY — never `printf "%s" "$out" | grep -q` (loom-9qlw): grep -q
# exits on first match and SIGPIPEs the producer, so under this file's
# `set -o pipefail` a SUCCESSFUL match reports 141 and the assertion
# silently INVERTS once the input grows past a pipe buffer. Test 0 is the
# control that makes such an inversion detectable.
# ----------------------------------------------------------------------
ncall=0
OUTF=""
RC=0

# reader <args...>  — resolves bare agent-* basenames via the env dir
reader() {
  ncall=$((ncall + 1))
  OUTF="$TMP/out.$ncall.txt"
  LOOM_CLAIM_PROVENANCE_TRANSCRIPT_DIR="$SUB" "$SCRIPT" "$@" > "$OUTF" 2>&1
  RC=$?
}

# reader_nodir <args...>  — NO env dir; every transcript must be a path
reader_nodir() {
  ncall=$((ncall + 1))
  OUTF="$TMP/out.$ncall.txt"
  "$SCRIPT" "$@" > "$OUTF" 2>&1
  RC=$?
}

# has <literal>  — greps the captured output FILE directly
has() { grep -qF -- "$1" "$OUTF"; }

# ----------------------------------------------------------------------
# Tests
# ----------------------------------------------------------------------

# 0. CONTROL — the assertion machinery is not inverted (loom-9qlw).
# A positive and a negative grep over the same fixture FILE. If grep-on-file
# ever reported 141-for-success, exactly one of these would flip, so a false
# pass elsewhere in this file becomes visible here.
run "CONTROL — grep assertions are not inverted (loom-9qlw SIGPIPE guard)"
ctl_ok=1
grep -qF 'INFERRED' "$GOOD" || { ctl_ok=0; echo "    positive control: 'INFERRED' NOT found in agent-good.jsonl"; }
if grep -qF 'ZZZ_SENTINEL_NEVER_PRESENT_ZZZ' "$GOOD"; then
  ctl_ok=0; echo "    negative control: absent sentinel reported as FOUND"
fi
if [ "$ctl_ok" = "1" ]; then
  pass "positive grep matches and negative grep does not — assertions read true"
else
  fail "assertion machinery is inverted — every result in this file is suspect"
fi

# 1. script exists and is executable
run "script exists and is executable"
if [ -x "$SCRIPT" ]; then
  pass "executable at scripts/loom-claim-provenance"
else
  fail "script missing or not executable at $SCRIPT"
fi

# 2. usage on missing args
run "usage on missing args"
reader_nodir
if [ "$RC" -ne 0 ] && grep -qi 'usage' "$OUTF"; then
  pass "exits non-zero + usage when no transcript args given"
else
  fail "expected non-zero+usage on missing args" "rc=$RC out=$(cat "$OUTF")"
fi

# 3. F1 — zero evidence slots in the FINAL report
run "F1: report with ZERO evidence slots FAILS and the message names the report"
reader agent-nocite
if [ "$RC" -ne 0 ] && has 'agent-nocite'; then
  pass "non-zero (rc=$RC) and the failure names the report"
else
  fail "expected non-zero exit naming 'agent-nocite'" "rc=$RC out=$(cat "$OUTF")"
fi

# 3b. The reader reads the FINAL report, not in-flight prose
run "slots in MID-transcript prose are ignored — only the FINAL report is read"
reader agent-midbogus
if [ "$RC" -eq 0 ] && ! has 'TestNeverRan'; then
  pass "a never-run command cited in in-flight prose did not trigger F2"
else
  fail "reader treated an earlier assistant text as the report" "rc=$RC out=$(cat "$OUTF")"
fi

# 4. F2 — cited command absent from the worker's tool calls
run "F2: cited command absent from the tool calls FAILS, naming claim + command"
reader agent-badcmd
if [ "$RC" -ne 0 ] \
  && has 'All 4 mutants die under the new test.' \
  && has 'go test -run TestScan -count=1'; then
  pass "non-zero (rc=$RC), names the claim AND the missing command"
else
  fail "expected non-zero naming both the claim and the missing command" \
    "rc=$RC out=$(cat "$OUTF")"
fi

# 5. Success path — N INFERRED claims emitted as a worklist
run "N INFERRED claims + resolvable citations SUCCEEDS and emits the worklist"
reader agent-good
if [ "$RC" -eq 0 ] \
  && has 'FIFO ordering is broken by the map range.' \
  && has 'The map iteration order is unspecified.'; then
  pass "zero exit and both INFERRED claims present in the worklist"
else
  fail "expected zero exit with both INFERRED claims on stdout" \
    "rc=$RC out=$(cat "$OUTF")"
fi

# 5b. the worklist is the INFERRED claims ONLY — cited claims are not work
run "cited (non-INFERRED) claims are NOT emitted as worklist items"
if [ "$RC" -eq 0 ] && ! has 'The deleted test pinned FIFO.'; then
  pass "the file-cited claim is absent from the worklist"
else
  fail "a cited claim leaked into the worklist (or the run failed)" \
    "rc=$RC out=$(cat "$OUTF")"
fi

# 6. --json emits exactly N objects, each carrying the claim text
run "--json emits exactly N objects, one per INFERRED claim, with a claim field"
reader --json agent-good
njson=$(jq -s 'length' "$OUTF" 2>/dev/null)
jq -s -r '.[].claim // empty' "$OUTF" > "$TMP/claims.txt" 2>/dev/null
if [ "$RC" -eq 0 ] && [ "$njson" = "2" ] \
  && grep -qF 'FIFO ordering is broken by the map range.' "$TMP/claims.txt" \
  && grep -qF 'The map iteration order is unspecified.' "$TMP/claims.txt"; then
  pass "2 JSON objects, both carrying their claim text"
else
  fail "expected 2 JSON objects with claim fields (got n=$njson rc=$RC)" \
    "out=$(cat "$OUTF")"
fi

# 7. DO NOT WIDEN THE GATE — the reader never judges whether INFERRED is true
run "reader does NOT judge the truth of an INFERRED claim (D4 — do not widen)"
reader agent-wild
if [ "$RC" -eq 0 ] && has 'The moon is made of cheese and that causes the deadlock.'; then
  pass "false/unverifiable INFERRED claims still SUCCEED and reach the worklist"
else
  fail "reader gated on the CONTENT of an INFERRED claim — the gate widened" \
    "rc=$RC out=$(cat "$OUTF")"
fi

# 8. Command matching is lenient enough not to fire on a decorated tool call
run "cited command found as a substring of a decorated tool call — no false positive"
reader agent-good
if [ "$RC" -eq 0 ]; then
  pass "cite 'go test -run TestScan -count=1' matched tool call '... 2>&1 | tail -5'"
else
  fail "F2 fired on a command that WAS run (decorated with a redirect + pipe)" \
    "rc=$RC out=$(cat "$OUTF")"
fi

# 9. Zero INFERRED is NOT the F1 condition (which is zero SLOTS)
run "report with slots but ZERO INFERRED SUCCEEDS with an empty worklist"
reader --json agent-allcited
njson=$(jq -s 'length' "$OUTF" 2>/dev/null)
if [ "$RC" -eq 0 ] && [ "$njson" = "0" ]; then
  pass "zero exit, zero worklist entries"
else
  fail "expected zero exit and an empty worklist (got n=$njson rc=$RC)" \
    "out=$(cat "$OUTF")"
fi

# 10. File citations are NOT resolved against the filesystem
run "file:line citations are not resolved on disk (F2 is command-only)"
reader agent-allcited
if [ "$RC" -eq 0 ] && ! has 'nonexistent_file_xyz.go'; then
  pass "a citation naming a file that does not exist is not a failure"
else
  fail "reader tried to resolve a file citation — F2 is command-only" \
    "rc=$RC out=$(cat "$OUTF")"
fi

# 11. Transcript resolution: bare basename (via env dir) OR a path
run "resolves a bare agent-* basename and a path to the same verdict"
reader --json agent-good
rc_base="$RC"; n_base=$(jq -s 'length' "$OUTF" 2>/dev/null)
reader_nodir --json "$SUB/agent-good.jsonl"
rc_path="$RC"; n_path=$(jq -s 'length' "$OUTF" 2>/dev/null)
if [ "$rc_base" -eq 0 ] && [ "$rc_path" -eq 0 ] && [ "$n_base" = "$n_path" ] && [ "$n_base" = "2" ]; then
  pass "basename and path agree (rc=0, 2 claims each)"
else
  fail "basename/path resolution disagree" \
    "basename rc=$rc_base n=$n_base ; path rc=$rc_path n=$n_path"
fi

# 12. Multiple transcripts in one invocation; one bad poisons the verdict
run "multiple transcripts: a failing one makes the whole run non-zero"
reader agent-good agent-badcmd
if [ "$RC" -ne 0 ] && has 'go test -run TestScan -count=1'; then
  pass "non-zero (rc=$RC) and the offending command is named"
else
  fail "expected non-zero naming the missing command across a multi-transcript run" \
    "rc=$RC out=$(cat "$OUTF")"
fi

# ----------------------------------------------------------------------
echo
echo "RESULTS: $passed passed, $failed failed"
[ "$failed" -eq 0 ] && exit 0 || exit 1
