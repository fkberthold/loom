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
# EVIDENCE-SLOT FORMAT (D2) — TWO SURFACE FORMS. Every load-bearing claim
# carries a slot holding either a citation or the literal marker INFERRED,
# and the slot appears in one of two shapes depending on the report:
#
#   (1) BRACKET form — prose reports (drawer-author, bug-family-researcher,
#       project-onboarder). A trailing bracketed token ends the claim line:
#           FIFO ordering is broken by the map range.   [INFERRED]
#           The deleted test pinned FIFO.               [test_methods.go:151]
#           All 4 mutants die under the new test.       [go test -run TestScan -count=1 -> 4/4]
#
#   (2) FIELD form — triple reports (kg-relationship-extractor, loom-myhi.3).
#       Triples are structured, not sentences, and already carry a `*Why*`
#       line, so bracketing would collapse the slot into the rationale —
#       which D2 forbids. The slot is a line-leading `evidence:` field:
#           1. `subject` → `predicate` → `object`
#              valid_from: YYYY-MM-DD
#              source_closet: (optional drawer ref)
#              evidence: <command + result, or file:line, or INFERRED>
#              *Why*: <one sentence>
#       See agents/kg-relationship-extractor.md:35 + its "Evidence slot
#       (required)" section.
#
# The reader MUST recognise BOTH. A bracket-only parser silently skips every
# kg-relationship-extractor report — a whole agent's output passing the gate
# by being invisible to it, which is the exact failure this epic exists to
# kill. `evidence:` is matched LINE-LEADING (`^\s*evidence:`), parallel to
# loom's `Files:` / `RED:` / `AUTOFAN-EXCLUDE:` anchored-line convention, so
# a mid-prose mention of the word is not a slot.
#
# SLOT PAYLOADS, in either form. A payload containing an ARROW is a COMMAND
# citation — the command is the text before the arrow, the result after.
# BOTH arrow glyphs must be accepted: ASCII ` -> ` and Unicode ` → ` (U+2192).
# The shipped agent definitions use the Unicode arrow EXCLUSIVELY
# (`grep -c ' -> ' agents/*.md -> 0` on all three; `grep -c ' → ' -> 2/9/1`),
# while the bead's D2 example uses ASCII — so a reader that handles only one
# glyph misses real reports. A payload of the `path:line` shape is a FILE
# citation. `INFERRED` is the bare marker.
#
# THE GATE IS EXACTLY TWO MECHANICAL CONDITIONS — do not widen it (D4):
#   F1. the FINAL report carries ZERO evidence slots OF EITHER FORM
#       (NOT "zero brackets" — a bracket-free triple report is fully
#       evidenced and must PASS)                                 -> non-zero
#   F2. the report cites a command absent from that worker's
#       tool calls                                               -> non-zero
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

# --- agent-triples: FIELD form, and ZERO brackets anywhere ------------
# A kg-relationship-extractor-shaped report. Three triples: a command
# citation (Unicode arrow), a file:line, and a bare INFERRED. Contains NO
# bracketed slot at all, so a reader whose F1 counts brackets would wrongly
# fail it. N INFERRED = 1 (triple 3).
TRIPLES="$SUB/agent-triples.jsonl"
emit_bash   "$TRIPLES" 'bd show loom-x4m'
emit_result "$TRIPLES" 'closed; see loom-22h'
emit_text   "$TRIPLES" '# KG triples proposed for loom-x4m

1. `loom-x4m` → `is_sibling_of` → `loom-22h`
   valid_from: 2026-05-15
   evidence: bd show loom-x4m → close-reason names loom-22h as the sibling
   *Why*: both describe the worktree bd wipe.

2. `bd-worktree-preseed` → `mitigates` → `loom-x4m`
   valid_from: 2026-05-15
   evidence: hooks/bd-worktree-preseed.sh:12
   *Why*: the hook pre-seeds the dolt.

3. `loom-x4m` → `composes_with` → `loom-4um`
   valid_from: 2026-05-15
   evidence: INFERRED
   *Why*: both touch bd state on merge.'

# --- agent-triples-noev: FIELD form with ZERO evidence: lines (F1) ----
# Also pins LINE-LEADING anchoring: the closing sentence contains the word
# "evidence:" mid-line. If the reader matched it unanchored it would count
# one slot and wrongly PASS.
TRIPLESNOEV="$SUB/agent-triples-noev.jsonl"
emit_bash   "$TRIPLESNOEV" 'bd show loom-zzz'
emit_result "$TRIPLESNOEV" 'open'
emit_text   "$TRIPLESNOEV" '# KG triples proposed for loom-zzz

1. `loom-zzz` → `blocks` → `loom-yyy`
   valid_from: 2026-07-31
   *Why*: the dependency edge is declared in bd.

2. `loom-zzz` → `members` → `loom-www`
   valid_from: 2026-07-31
   *Why*: filed under the same epic.

I gathered no evidence: the triples came from memory.'

# --- agent-triples-badcmd: FIELD form citing a never-run command (F2) --
# Uses the Unicode arrow, the glyph the shipped agent defs actually emit.
TRIPLESBAD="$SUB/agent-triples-badcmd.jsonl"
emit_bash   "$TRIPLESBAD" 'echo probe'
emit_result "$TRIPLESBAD" 'probe'
emit_text   "$TRIPLESBAD" '# KG triples proposed for loom-qqq

1. `loom-qqq` → `verified_by` → `TestScan`
   valid_from: 2026-07-31
   evidence: go test -run TestNeverRan -count=1 → 9/9
   *Why*: the suite covers the scanner.'

# --- agent-mixed: BOTH forms in one report, cross-glyph ---------------
# 3 bracket slots + 2 field slots = 5 slots; INFERRED = 1 bracket + 1 field
# = 2, so the worklist must be exactly 2 (double-counting inflates it).
# Deliberately crossed against agent-good/agent-triples: the BRACKET slots
# here use the Unicode arrow and the FIELD slot uses ASCII, completing the
# 2x2 of {bracket,field} x {ASCII,Unicode} on the success side.
MIXED="$SUB/agent-mixed.jsonl"
emit_bash   "$MIXED" 'go test -run TestScan -count=1 2>&1 | tail -5'
emit_result "$MIXED" 'ok 4/4'
emit_bash   "$MIXED" 'git log --oneline -1'
emit_result "$MIXED" 'abc123 fix the range'
emit_text   "$MIXED" 'Mixed report — prose claims then triples.

FIFO ordering is broken by the map range.   [INFERRED]
The deleted test pinned FIFO.   [test_methods.go:151]
All 4 mutants die.   [go test -run TestScan -count=1 → 4/4]

# KG triples proposed for loom-mix

1. `loom-mix` → `caused_by` → `map_range`
   valid_from: 2026-07-31
   evidence: INFERRED
   *Why*: the range order is unspecified.

2. `loom-mix` → `fixed_in` → `abc123`
   valid_from: 2026-07-31
   evidence: git log --oneline -1 -> abc123 fix the range
   *Why*: the commit message names it.'

# --- agent-glyphs-badcmd: the two REMAINING 2x2 quadrants, failing ----
# A bracket slot with a UNICODE arrow and a field slot with an ASCII arrow,
# both citing never-run commands. A reader that parses only one glyph per
# form misses one of them; the assertion requires BOTH be named, which also
# pins that the reader reports every missing command, not just the first.
GLYPHS="$SUB/agent-glyphs-badcmd.jsonl"
emit_bash   "$GLYPHS" 'echo probe'
emit_result "$GLYPHS" 'probe'
emit_text   "$GLYPHS" 'Cross-glyph probe.

The bracket claim with a unicode arrow.   [go test -run TestBracketUni -count=1 → 1/1]

1. `a` → `b` → `c`
   valid_from: 2026-07-31
   evidence: go test -run TestFieldAscii -count=1 -> 2/2
   *Why*: probe.'

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

# ======================================================================
# FIELD-FORM (`evidence:`) coverage — the second surface form. Every
# behaviour pinned above for the bracket form must hold identically here.
# ======================================================================

# 13. Success path, field form
run "FIELD form: N INFERRED triples + resolvable citations SUCCEEDS"
reader --json agent-triples
njson=$(jq -s 'length' "$OUTF" 2>/dev/null)
jq -s -r '.[].claim // empty' "$OUTF" > "$TMP/claims.txt" 2>/dev/null
if [ "$RC" -eq 0 ] && [ "$njson" = "1" ] \
  && grep -qF 'composes_with' "$TMP/claims.txt"; then
  pass "zero exit, 1 worklist entry, and it names the INFERRED triple"
else
  fail "expected zero exit and 1 worklist entry naming the INFERRED triple (n=$njson rc=$RC)" \
    "out=$(cat "$OUTF")"
fi

# 14. F1 counts slots of EITHER form — not brackets
run "F1: a report with ZERO brackets but WITH evidence: lines PASSES"
if [ "$RC" -eq 0 ]; then
  pass "bracket-free triple report is fully evidenced — F1 did not fire"
else
  fail "F1 fired on a bracket-free report — it is counting brackets, not slots" \
    "rc=$RC out=$(cat "$OUTF")"
fi

# 15. A field slot's claim is the TRIPLE, not the rationale (D2 separation)
run "FIELD form: the worklist entry is the triple, not its *Why* rationale"
if [ "$RC" -eq 0 ] && ! grep -qF 'both touch bd state on merge' "$TMP/claims.txt"; then
  pass "the *Why* line stayed out of the worklist entry"
else
  fail "the slot collapsed into the rationale — D2 forbids this" \
    "claims=$(cat "$TMP/claims.txt")"
fi

# 16. F1, field form — and LINE-LEADING anchoring of `evidence:`
run "FIELD form F1: triple report with zero evidence: lines FAILS, names it"
reader agent-triples-noev
if [ "$RC" -ne 0 ] && has 'agent-triples-noev'; then
  pass "non-zero (rc=$RC), names the report; mid-line 'evidence:' did not count"
else
  fail "expected non-zero naming 'agent-triples-noev' (a mid-prose 'evidence:' must not count as a slot)" \
    "rc=$RC out=$(cat "$OUTF")"
fi

# 17. F2, field form, Unicode arrow
run "FIELD form F2: evidence: citing a never-run command FAILS (Unicode arrow)"
reader agent-triples-badcmd
if [ "$RC" -ne 0 ] \
  && has 'verified_by' \
  && has 'go test -run TestNeverRan -count=1'; then
  pass "non-zero (rc=$RC), names the triple AND the missing command"
else
  fail "expected non-zero naming the triple and the missing command" \
    "rc=$RC out=$(cat "$OUTF")"
fi

# 18. Mixed report — both forms counted, neither double-counted
run "MIXED report: slots counted from both forms, with no double-counting"
reader --json agent-mixed
njson=$(jq -s 'length' "$OUTF" 2>/dev/null)
jq -s -r '.[].claim // empty' "$OUTF" > "$TMP/claims.txt" 2>/dev/null
if [ "$RC" -eq 0 ] && [ "$njson" = "2" ] \
  && grep -qF 'FIFO ordering is broken by the map range.' "$TMP/claims.txt" \
  && grep -qF 'caused_by' "$TMP/claims.txt"; then
  pass "exactly 2 worklist entries — one bracket INFERRED, one field INFERRED"
else
  fail "expected exactly 2 entries spanning both forms (n=$njson rc=$RC)" \
    "claims=$(cat "$TMP/claims.txt")"
fi

# 19. Both arrow glyphs parse in BOTH forms — the remaining 2x2 quadrants
run "both arrow glyphs (ASCII -> and Unicode →) parse in both slot forms"
reader agent-glyphs-badcmd
if [ "$RC" -ne 0 ] \
  && has 'go test -run TestBracketUni -count=1' \
  && has 'go test -run TestFieldAscii -count=1'; then
  pass "bracket+Unicode and field+ASCII citations were both parsed and both named"
else
  fail "a glyph/form combination was not parsed as a command citation" \
    "rc=$RC out=$(cat "$OUTF")"
fi

# ======================================================================
# REAL-WORLD SURFACE SHAPES (loom-agug)
#
# Everything above this line was written by an author who shared the
# parser's assumptions about how a worker formats a slot. That is why the
# 22 blocks above were fully GREEN over a reader that FAILED on 7 of 7
# real contract-briefed worker reports (measured 2026-07-31: 5xF1, 2xF2 —
# a 100% false-fail rate). The spec encoded an assumption; the tests
# encoded the SAME assumption; the suite was therefore structurally
# incapable of failing on it.
#
# Every fixture below is DERIVED FROM a real transcript, and says which
# one. The shapes are not idealized — they are what workers actually
# wrote, warts included. Six distinct defects were diagnosed, and they do
# NOT share one root cause:
#
#   (a) BACKTICKS AROUND the bracket — `[cmd -> result]` — so the line
#       ends at a backtick, not at `]`, and RE_BRACKET never matches.
#       DERIVED FROM agent-a349f9a781c9d7829 (7 of 7 slots), agent-a83c0cc2d34744050 (8).
#   (b) BACKTICKS INSIDE the bracket wrapping the COMMAND —
#       [`cmd` -> `result`] — the slot parses, but the extracted command
#       carries its backticks and can never substring-match a tool call.
#       DERIVED FROM agent-a2eae422e1a2bf8f4 (5 false F2 hits).
#   (c) MID-LINE and LINE-LEADING slots — a marker followed by the prose
#       it qualifies (`**Claim.** [INFERRED] because ...`), or leading a
#       list item. NOT a backtick problem: agent-ae5325d47938a9e73's
#       markers are BARE brackets. DERIVED FROM agent-ae5325d47938a9e73,
#       agent-a53dacfbf75b8a671, agent-a698833afdad2798e.
#   (d) FENCED CODE BLOCKS read as report content — a report that quotes
#       this very contract's EXAMPLE slots is condemned by them.
#       DERIVED FROM agent-a25b90f9a6cad014f (7 false F2 hits, all of
#       them fixture text the worker pasted inside ```bash fences).
#   (e) ONE SLOT PER LINE — the greedy last-bracket rule silently DROPS
#       every earlier slot on a line, so its citation is never checked.
#       DERIVED FROM agent-a2eae422e1a2bf8f4:41.
#   (f) ARROW SPLIT ORDER — split_arrow tries Unicode BEFORE ASCII
#       regardless of position, so an ASCII-separated citation whose
#       RESULT text contains a Unicode arrow splits in the wrong place;
#       and an arrow inside a quoted pattern (`grep -c ' -> ' f`) splits
#       at the quote, truncating the command to a prefix so short it
#       matches almost any tool call — a silent FALSE NEGATIVE.
#       DERIVED FROM agent-a25b90f9a6cad014f:11-12,276.
#
# TWO of the blocks below are GUARDs, not RED — they pass against the
# current reader and must KEEP passing. They exist because (a)-(f) all
# push toward a MORE PERMISSIVE parse, and D4's whole justification is
# that a widened gate becomes a rubber stamp. They are marked GUARD.
# ======================================================================

# emit_heredoc <file>       — the FINAL report body, read from stdin.
# emit_bash_heredoc <file>  — one Bash tool call, command read from stdin.
# Both exist so a fixture can contain single quotes, backticks and `$`
# without shell-quoting gymnastics: a <<'EOF' body is fully literal.
emit_heredoc()      { emit_text "$1" "$(cat)"; }
emit_bash_heredoc() { emit_bash "$1" "$(cat)"; }

# --- agent-bt-outer: defect (a) — backticks AROUND the bracket --------
# DERIVED FROM agent-a349f9a781c9d7829's final report, whose every slot
# is of this shape. 4 slots, 1 INFERRED. Both arrow glyphs, so the fix
# cannot be glyph-specific.
BTOUT="$SUB/agent-bt-outer.jsonl"
emit_bash   "$BTOUT" 'bash lib/tests/foo.test.sh 2>&1 | tail -3'
emit_result "$BTOUT" 'RESULTS: 22 passed, 0 failed'
emit_bash   "$BTOUT" 'shellcheck --severity=warning scripts/foo'
emit_result "$BTOUT" ''
emit_heredoc "$BTOUT" <<'EOF'
GREEN. Report follows.

## 1. Test result

All 22 blocks green, no test modified.
`[bash lib/tests/foo.test.sh → RESULTS: 22 passed, 0 failed]`

## 2. shellcheck

Clean. `[shellcheck --severity=warning scripts/foo -> rc=0, no output]`

## 3. Notes

The helper was already present. `[helpers.sh:12]`
The map iteration order is unspecified. `[INFERRED]`
EOF

# --- agent-bt-inner: defect (b) — backticks INSIDE, command WAS run ---
# DERIVED FROM agent-a2eae422e1a2bf8f4:5,7,39. The slot parses today
# (the line does end at `]`), but every extracted command carries its
# wrapping backticks and so never matches the tool call that ran it —
# 5 of that worker's 6 reported F2 hits were commands it HAD run.
BTIN="$SUB/agent-bt-inner.jsonl"
emit_bash_heredoc "$BTIN" <<'EOF'
grep -n '^## Claim provenance in worker returns' .claude/rules/dispatched-agents.md
EOF
emit_result "$BTIN" '587'
emit_bash   "$BTIN" 'bash lib/tests/bar.test.sh 2>&1 | tail -50'
emit_result "$BTIN" '81 passed, 0 failed'
emit_heredoc "$BTIN" <<'EOF'
Both edits landed.

**`.claude/rules/dispatched-agents.md:587`** — new section, +113 lines. [`grep -n '^## Claim provenance in worker returns' .claude/rules/dispatched-agents.md` → `587`]

`bash lib/tests/bar.test.sh` → **81 passed, 0 failed**. [`bash lib/tests/bar.test.sh` → `81 passed, 0 failed`]

The placement is the best of the three. [INFERRED]
EOF

# --- agent-bt-inner-badcmd: (b) must not disable F2 -------------------
# The same shape citing a command that was NEVER run. Stripping the
# backticks must make the check WORK, not make it stop firing — and the
# command it names must be the bare command, not the backticked text.
BTINBAD="$SUB/agent-bt-inner-badcmd.jsonl"
emit_bash   "$BTINBAD" 'echo probe'
emit_result "$BTINBAD" 'probe'
emit_heredoc "$BTINBAD" <<'EOF'
Report.

The scanner is covered. [`go test -run TestNeverRan -count=1` → `9/9`]
EOF

# --- agent-field-bt: (b) in the FIELD form ----------------------------
# The bead asks explicitly whether an `evidence:` payload has the same
# problem. It does: the payload grammar is shared, so a backticked
# command in a triple fails identically. Completes the 2x2x2 the bead
# names — {bracket,field} x {ASCII,Unicode} x {bare,backticked}.
FIELDBT="$SUB/agent-field-bt.jsonl"
emit_bash   "$FIELDBT" 'bd show loom-x4m'
emit_result "$FIELDBT" 'closed; see loom-22h'
emit_heredoc "$FIELDBT" <<'EOF'
# KG triples proposed for loom-x4m

1. `loom-x4m` → `is_sibling_of` → `loom-22h`
   valid_from: 2026-05-15
   evidence: `bd show loom-x4m` → `close-reason names loom-22h as the sibling`
   *Why*: both describe the worktree bd wipe.

2. `loom-x4m` → `composes_with` → `loom-4um`
   valid_from: 2026-05-15
   evidence: INFERRED
   *Why*: both touch bd state on merge.
EOF

# --- agent-field-bt-badcmd: field form, backticked, never run ---------
FIELDBTBAD="$SUB/agent-field-bt-badcmd.jsonl"
emit_bash   "$FIELDBTBAD" 'echo probe'
emit_result "$FIELDBTBAD" 'probe'
emit_heredoc "$FIELDBTBAD" <<'EOF'
# KG triples proposed for loom-qqq

1. `loom-qqq` → `verified_by` → `TestFieldBt`
   valid_from: 2026-07-31
   evidence: `go test -run TestFieldBt -count=1` -> `2/2`
   *Why*: the suite covers the scanner.
EOF

# --- agent-midline: defect (c) — mid-line and leading slots -----------
# DERIVED FROM agent-ae5325d47938a9e73:84-86 (BARE mid-line [INFERRED],
# no backticks anywhere — the proof that backticks are not the whole
# story), agent-a53dacfbf75b8a671:97-101 (backticked mid-line) and
# agent-a698833afdad2798e:7,69-70 (mid-line file citation; leading
# marker on a list item).
#
# The `##` heading here carries the marker too, and must NOT count — 3
# INFERRED claims, not 4. A report must not clear F1 by titling a
# section after the marker.
MIDLINE="$SUB/agent-midline.jsonl"
emit_bash   "$MIDLINE" 'bash lib/tests/owned.test.sh'
emit_result "$MIDLINE" '30 passed, 0 failed'
emit_heredoc "$MIDLINE" <<'EOF'
Done. Both beads landed in one commit.

## Decision: OMIT the tool reference

1. **The brief's premise does not hold for this file.** `scan_dir` iterates two globs [`lib/tests/downstream-script-invocation.test.sh:81`]; neither path falls in them.

## `[INFERRED]` judgment calls

- **The parenthetical is worth its length.** [INFERRED] A bracket-only reading silently skips every structured triple report.
- **Placement under the dispatch section rather than a new one.** [INFERRED] Both clauses are dispatch-lifecycle facts.
- `[INFERRED]` The residue routes were verified on this machine's transcripts only.
EOF

# --- agent-midline-badcmd: (c) must not disable F2 --------------------
MIDBAD="$SUB/agent-midline-badcmd.jsonl"
emit_bash   "$MIDBAD" 'echo probe'
emit_result "$MIDBAD" 'probe'
emit_heredoc "$MIDBAD" <<'EOF'
Report.

- **Autodetect scans all projects** and picks newest-mtime [go test -run TestMidNever -count=1 -> 3/3] — documented as a warning admonition.
EOF

# --- agent-multislot: defect (e) — two slots on ONE line --------------
# DERIVED FROM agent-a2eae422e1a2bf8f4:41, which carries a `grep -cE`
# citation AND a `git status --porcelain` citation on one line. The
# greedy `^(.*)\[...\]$` keeps only the LAST, so the first slot's
# command is never checked at all — an under-count, and a hole in F2.
# Here the FIRST slot is the never-run one, so a last-bracket-only
# parse reports success.
MULTI="$SUB/agent-multislot.jsonl"
emit_bash   "$MULTI" 'git status --porcelain'
emit_result "$MULTI" ''
emit_heredoc "$MULTI" <<'EOF'
Report.

**Negative control**: counted all nine patterns. [go test -run TestFirstSlot -count=1 -> 0] Control file removed afterward. [git status --porcelain -> empty]
EOF

# --- agent-fenced: defect (d) — fenced blocks are not report claims ---
# DERIVED FROM agent-a25b90f9a6cad014f, whose report pastes the test
# file it wrote inside ```bash fences. All 7 of its reported F2 hits
# were EXAMPLE slots quoted from the contract, not citations. Quoting
# the contract's own examples must neither satisfy F1 nor trip F2 —
# otherwise the gate condemns every report that explains itself.
FENCED="$SUB/agent-fenced.jsonl"
emit_bash_heredoc "$FENCED" <<'EOF'
grep -c '^run "' lib/tests/foo.test.sh
EOF
emit_result "$FENCED" '22'
emit_heredoc "$FENCED" <<'EOF'
Field form pinned. Report follows.

## New section, verbatim

```bash
#   (1) BRACKET form — prose reports. A trailing bracketed token ends
#       the claim line:
#           FIFO ordering is broken by the map range.   [INFERRED]
#           The deleted test pinned FIFO.               [test_methods.go:151]
#           All 4 mutants die under the new test.       [go test -run TestScan -count=1 -> 4/4]
```

## Counts

22 test blocks, up from 15. `[grep -c '^run "' lib/tests/foo.test.sh -> 22]`
EOF

# --- agent-fenced-only: (d) must not become a loophole ----------------
# A report whose ONLY slot-shaped lines are quoted examples inside a
# fence is UNEVIDENCED — pasting the contract is not citing your work.
# This is the anti-widening pin for the fence rule: F1, not success.
FENCEDONLY="$SUB/agent-fenced-only.jsonl"
emit_bash   "$FENCEDONLY" 'echo probe'
emit_result "$FENCEDONLY" 'probe'
emit_heredoc "$FENCEDONLY" <<'EOF'
Here is the contract I was given, quoted for reference:

```
FIFO ordering is broken by the map range.   [INFERRED]
All 4 mutants die under the new test.       [go test -run TestScan -count=1 -> 4/4]
```

Everything works fine now and the bead is done. I refactored the handler,
tightened the loop, and the suite is green.
EOF

# --- agent-heading-only: (c) must not become a loophole ---------------
# GUARD (green against the current reader). Both agent-a53dacfbf75b8a671
# and agent-ae5325d47938a9e73 title a section "`[INFERRED]` judgment
# calls". Widening to mid-line slots must not let that heading alone
# clear F1 for a report that cites nothing.
HEADONLY="$SUB/agent-heading-only.jsonl"
emit_bash   "$HEADONLY" 'echo probe'
emit_result "$HEADONLY" 'probe'
emit_heredoc "$HEADONLY" <<'EOF'
Done.

## `[INFERRED]` judgment calls

None worth recording. I refactored the handler, tightened the loop, and
the suite is green.
EOF

# --- agent-arrow-order: defect (f) — glyph precedence vs position -----
# DERIVED FROM agent-a25b90f9a6cad014f:276, where an ASCII-separated
# citation's RESULT text itself contains a Unicode arrow. split_arrow
# tests Unicode FIRST, so it splits at the LATER arrow and swallows the
# result into the command. The separator is the FIRST arrow on the
# payload, whichever glyph it is.
ARROWORD="$SUB/agent-arrow-order.jsonl"
emit_bash   "$ARROWORD" 'git log --oneline -1'
emit_result "$ARROWORD" 'abc123 fix the range'
emit_heredoc "$ARROWORD" <<'EOF'
Report.

The commit message names the fix. [git log --oneline -1 -> abc123 fix a → b ordering]
EOF

# --- agent-arrow-quoted: defect (f) — arrow inside a quoted pattern ---
# DERIVED FROM agent-a25b90f9a6cad014f:11-12, which cites
# `grep -c ' -> ' <files>`. Splitting at the FIRST arrow truncates the
# command to `grep -c '` — a prefix so short it substring-matches almost
# any grep in the transcript, so F2 silently passes commands that were
# never run. That is the more dangerous direction: a FALSE NEGATIVE in
# the gate. Here nothing grep-shaped was run at all, so the truncated
# prefix cannot rescue it; the failure must name the FULL cited command.
ARROWQ="$SUB/agent-arrow-quoted.jsonl"
emit_bash   "$ARROWQ" 'echo probe'
emit_result "$ARROWQ" 'probe'
emit_heredoc "$ARROWQ" <<'EOF'
Report.

I re-counted the ASCII arrows. [grep -c ' -> ' agents/never-touched.md -> 0]
EOF

# ----------------------------------------------------------------------
# 20. (a) backticks AROUND the bracket
# ----------------------------------------------------------------------
run "backtick-WRAPPED bracket slots are recognised (loom-agug RED invariant)"
reader --json agent-bt-outer
njson=$(jq -s 'length' "$OUTF" 2>/dev/null)
jq -s -r '.[].claim // empty' "$OUTF" > "$TMP/claims.txt" 2>/dev/null
if [ "$RC" -eq 0 ] && [ "$njson" = "1" ] \
  && grep -qF 'The map iteration order is unspecified.' "$TMP/claims.txt"; then
  pass "4 backticked slots counted, 1 INFERRED on the worklist, no F1/F2"
else
  fail "a report whose slots are all \`[...]\`-wrapped was not read (n=$njson rc=$RC)" \
    "out=$(cat "$OUTF")"
fi

# ----------------------------------------------------------------------
# 21. (b) backticks INSIDE the bracket — no FALSE F2
# ----------------------------------------------------------------------
run "backticks INSIDE the slot do not make a command that WAS run look absent"
reader agent-bt-inner
if [ "$RC" -eq 0 ]; then
  pass "[\`cmd\` → \`result\`] matched the tool call that ran cmd"
else
  fail "F2 fired on commands the worker DID run — backticks were not stripped" \
    "rc=$RC out=$(cat "$OUTF")"
fi

# ----------------------------------------------------------------------
# 22. (b) stripping backticks must not disable F2
# ----------------------------------------------------------------------
run "backticked slot citing a NEVER-run command still FAILS, naming the bare command"
reader agent-bt-inner-badcmd
if [ "$RC" -ne 0 ] && has 'command: go test -run TestNeverRan -count=1'; then
  pass "F2 still fires and reports the command without its backticks"
else
  fail "expected F2 naming the unbackticked command" "rc=$RC out=$(cat "$OUTF")"
fi

# ----------------------------------------------------------------------
# 23. (b) in the FIELD form — the payload grammar is shared
# ----------------------------------------------------------------------
run "FIELD form: a backticked evidence: payload does not produce a false F2"
reader --json agent-field-bt
njson=$(jq -s 'length' "$OUTF" 2>/dev/null)
if [ "$RC" -eq 0 ] && [ "$njson" = "1" ]; then
  pass "backticked evidence: command matched, 1 INFERRED triple on the worklist"
else
  fail "backticks broke the field form too (n=$njson rc=$RC)" "out=$(cat "$OUTF")"
fi

# ----------------------------------------------------------------------
# 24. (b) FIELD form must keep failing on a never-run command
# ----------------------------------------------------------------------
run "FIELD form: backticked evidence: citing a NEVER-run command still FAILS"
reader agent-field-bt-badcmd
if [ "$RC" -ne 0 ] && has 'command: go test -run TestFieldBt -count=1'; then
  pass "F2 fires in the field form, naming the unbackticked command"
else
  fail "expected F2 naming the unbackticked field-form command" \
    "rc=$RC out=$(cat "$OUTF")"
fi

# ----------------------------------------------------------------------
# 25. (c) mid-line + leading slots, and headings excluded
# ----------------------------------------------------------------------
run "MID-LINE and LINE-LEADING slots count; a heading carrying the marker does not"
reader --json agent-midline
njson=$(jq -s 'length' "$OUTF" 2>/dev/null)
if [ "$RC" -eq 0 ] && [ "$njson" = "3" ]; then
  pass "3 INFERRED claims found mid-line/leading; the \`[INFERRED]\` heading not counted"
else
  fail "expected exactly 3 worklist entries (n=$njson rc=$RC) — mid-line slots missed, or the heading counted" \
    "out=$(cat "$OUTF")"
fi

# ----------------------------------------------------------------------
# 26. (c) widening to mid-line must not lose F2
# ----------------------------------------------------------------------
run "a MID-LINE citation of a never-run command still FAILS F2"
reader agent-midline-badcmd
if [ "$RC" -ne 0 ] && has 'command: go test -run TestMidNever -count=1'; then
  pass "F2 fires on a slot that is not at end-of-line"
else
  fail "expected F2 naming the mid-line command" "rc=$RC out=$(cat "$OUTF")"
fi

# ----------------------------------------------------------------------
# 27. (e) every slot on a line is a slot
# ----------------------------------------------------------------------
run "two slots on ONE line: the FIRST is checked too, not just the last"
reader agent-multislot
if [ "$RC" -ne 0 ] && has 'command: go test -run TestFirstSlot -count=1'; then
  pass "the earlier slot on the line was parsed and its command checked"
else
  fail "the first slot on the line was dropped — greedy last-bracket parse" \
    "rc=$RC out=$(cat "$OUTF")"
fi

# ----------------------------------------------------------------------
# 28. (d) fenced code blocks are not report claims
# ----------------------------------------------------------------------
run "slots QUOTED inside a \`\`\` fence neither satisfy F1 nor trip F2"
reader --json agent-fenced
njson=$(jq -s 'length' "$OUTF" 2>/dev/null)
if [ "$RC" -eq 0 ] && [ "$njson" = "0" ] && ! has 'TestScan'; then
  pass "the fenced example slots were ignored; the real slot outside carried the report"
else
  fail "fenced example text was read as the worker's own claims (n=$njson rc=$RC)" \
    "out=$(cat "$OUTF")"
fi

# ----------------------------------------------------------------------
# 29. (d) fences must not become an F1 loophole
# ----------------------------------------------------------------------
run "a report whose ONLY slots are quoted inside a fence is F1, not success"
reader agent-fenced-only
if [ "$RC" -ne 0 ] && has 'FAIL (F1)'; then
  pass "quoting the contract's examples does not evidence the report"
else
  fail "expected F1 — a fence-only report carries no claims of its own" \
    "rc=$RC out=$(cat "$OUTF")"
fi

# ----------------------------------------------------------------------
# 30. GUARD (c) — a heading is not a claim
# ----------------------------------------------------------------------
run "GUARD: a section HEADING naming the marker does not clear F1 on its own"
reader agent-heading-only
if [ "$RC" -ne 0 ] && has 'FAIL (F1)'; then
  pass "\`## \`[INFERRED]\` judgment calls\` alone is still zero evidence slots"
else
  fail "the gate widened — a heading now counts as a claim" \
    "rc=$RC out=$(cat "$OUTF")"
fi

# ----------------------------------------------------------------------
# 31. (f) the separator is the FIRST arrow, whichever glyph
# ----------------------------------------------------------------------
run "an ASCII-separated citation whose RESULT contains a Unicode arrow splits correctly"
reader agent-arrow-order
if [ "$RC" -eq 0 ]; then
  pass "split at the first arrow by POSITION, not by glyph precedence"
else
  fail "split_arrow preferred the later Unicode arrow and swallowed the result" \
    "rc=$RC out=$(cat "$OUTF")"
fi

# ----------------------------------------------------------------------
# 32. (f) an arrow inside a quoted pattern must not truncate the command
# ----------------------------------------------------------------------
run "a cited command containing a QUOTED arrow is reported in full, not truncated"
reader agent-arrow-quoted
if [ "$RC" -ne 0 ] && has "command: grep -c ' -> ' agents/never-touched.md"; then
  pass "the full cited command was checked and named — no short-prefix false match"
else
  fail "the command was truncated at the quoted arrow (a short prefix matches almost anything)" \
    "rc=$RC out=$(cat "$OUTF")"
fi

# ======================================================================
# REAL-TRANSCRIPT ACCEPTANCE (loom-agug)
#
# The gap that let this bug ship: the suite only ever ran against
# fixtures. Fixtures cannot falsify an assumption they were built from.
#
# What runs here instead is a COMMITTED CORPUS of real worker reports —
# lib/tests/fixtures/claim-provenance/, captured verbatim from the seven
# subagent transcripts of the session that built epic loom-myhi (the
# first seven contract-briefed dispatches that ever existed). Each file
# holds that worker's real Bash commands plus its verbatim final report.
# See that directory's PROVENANCE.md for the derivation and for the
# corpus's honest limitations — it is seven reports from one session,
# not a representative sample, and it grows only by hand.
#
# Real transcripts CANNOT be read live by the suite: they live outside
# the repo under ~/.claude/projects/, are machine-specific, and would
# make the check SKIP silently anywhere else — a false green, which is
# the failure mode this whole bead is about. Committing the corpus is
# the closest honest alternative: real bytes, deterministic, gateable.
#
# What is deliberately NOT pinned here: the overall verdict of
# agent-a349f9a781c9d7829, agent-a83c0cc2d34744050 and
# agent-a25b90f9a6cad014f. Each carries at least one citation that is
# genuinely unverifiable as written — an elided `…`, a `<placeholder>`,
# a paraphrased grep, or an annotation glued onto the command
# (`bash foo.test.sh (pre-implementation)`). Whether F2 should fire on
# those is a CONTRACT question about how a worker must write a citation,
# not a parser question — it belongs to the agent definitions and D2,
# and no parse rule should be tuned until it stops asking it.
# ======================================================================

REALDIR="$LOOM_ROOT/lib/tests/fixtures/claim-provenance"
REAL_IDS=(
  a83c0cc2d34744050
  a25b90f9a6cad014f
  a349f9a781c9d7829
  a2eae422e1a2bf8f4
  a53dacfbf75b8a671
  a698833afdad2798e
  ae5325d47938a9e73
)

# reader_real <args...>  — resolves agent-real-* names against the corpus
reader_real() {
  ncall=$((ncall + 1))
  OUTF="$TMP/out.$ncall.txt"
  LOOM_CLAIM_PROVENANCE_TRANSCRIPT_DIR="$REALDIR" "$SCRIPT" "$@" > "$OUTF" 2>&1
  RC=$?
}

# ----------------------------------------------------------------------
# 33. GUARD — the corpus exists, parses, and is documented
# ----------------------------------------------------------------------
# GUARD (green today). Per gate-don't-advise (loom-wj26.1) the corpus's
# presence is a correctness invariant, not something to remember: a
# deleted or undocumented corpus file must break the suite, never
# silently shrink the acceptance check.
run "GUARD: the real-transcript corpus is present, valid JSONL, and documented"
corpus_ok=1
for rid in "${REAL_IDS[@]}"; do
  f="$REALDIR/agent-real-$rid.jsonl"
  if [ ! -s "$f" ]; then
    corpus_ok=0; echo "    missing or empty: $f"
  elif ! jq -s '.' "$f" >/dev/null 2>&1; then
    corpus_ok=0; echo "    not valid JSONL: $f"
  elif ! grep -qF "agent-real-$rid.jsonl" "$REALDIR/PROVENANCE.md"; then
    corpus_ok=0; echo "    undocumented in PROVENANCE.md: agent-real-$rid.jsonl"
  fi
done
if [ "$corpus_ok" = "1" ]; then
  pass "7 real transcripts present, parseable, and listed in PROVENANCE.md"
else
  fail "the real-transcript corpus is incomplete — the acceptance check is weaker than it claims"
fi

# ----------------------------------------------------------------------
# 34. ACCEPTANCE — no real worker report is F1
# ----------------------------------------------------------------------
# This is the bead's RED invariant, measured against reality rather than
# against fixtures. All seven of these reports were written by workers
# briefed on the evidence-slot contract, and every one of them carries
# slots. 5 of the 7 came back F1 at capture time; none may.
run "ACCEPTANCE: NO real worker report is F1 — all seven carry evidence slots"
real_f1=()
for rid in "${REAL_IDS[@]}"; do
  reader_real "agent-real-$rid"
  if has 'FAIL (F1)'; then real_f1+=("$rid"); fi
done
if [ "${#real_f1[@]}" -eq 0 ]; then
  pass "0 of 7 real reports are F1"
else
  fail "${#real_f1[@]} of 7 real reports still read as carrying ZERO evidence slots" \
    "F1: ${real_f1[*]}"
fi

# ----------------------------------------------------------------------
# 35. ACCEPTANCE — F2 stays honest on a real report
# ----------------------------------------------------------------------
# agent-a2eae422e1a2bf8f4 must STILL fail. Its report cites
# `grep -n 'Claim-provenance return contract (loom-myhi.2' …` while the
# command it actually ran carried a second alternation branch, and it
# cites two more commands elided to `…` — genuinely unverifiable
# citations, exactly what F2 is for. But at capture time it reported SIX
# missing commands, five of which the worker HAD run, each printed with
# its markdown backticks still attached. So: still non-zero, and no F2
# line may name a backticked command.
run "ACCEPTANCE: a real F2 STAYS failing, but stops naming commands that WERE run"
reader_real agent-real-a2eae422e1a2bf8f4
if [ "$RC" -ne 0 ] && has 'FAIL (F2)' \
  && has "Claim-provenance return contract (loom-myhi.2" \
  && ! grep -qF -- 'command: `' "$OUTF"; then
  pass "genuine unverifiable citation still surfaced; no backticked command reported"
else
  fail "expected a still-failing F2 whose reported commands are bare, not backticked" \
    "rc=$RC out=$(cat "$OUTF")"
fi

# ----------------------------------------------------------------------
echo
echo "RESULTS: $passed passed, $failed failed"
[ "$failed" -eq 0 ] && exit 0 || exit 1
