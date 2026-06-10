#!/usr/bin/env bash
# Fixture test for lib/loom-mine-history.sh — the SALIENCE-CALL STDIN bug
# family. Two intertwined invariants are pinned here:
#
#   (A) ARG_MAX overflow (loom-oekt, 2026-06-10):
#       The salience call originally passed the FULL prompt as a
#       command-line ARGUMENT:
#         reply=$(claude -p "$prompt" --model "$model" ... </dev/null)
#       A very large commit body/diff makes "$prompt" exceed the OS
#       per-argument limit (Linux MAX_ARG_STRLEN ~= 128KiB, independent of
#       the much larger total ARG_MAX), so exec fails with
#       `Argument list too long` (E2BIG) and that unit yields NO draft.
#       FIX: write $prompt to a temp file and feed it on stdin —
#         printf '%s' "$prompt" > "$pf"; reply=$(claude -p ... < "$pf")
#       The prompt never appears in argv, so no argument-size limit applies.
#
#   (B) survivors-stream stdin leak (rnxp, 2026-06-09 night):
#       The salience call runs INSIDE the `while read ... done < "$survivors"`
#       loop. Every command inside that loop inherits the loop's stdin —
#       the "$survivors" fd, positioned AFTER the current line. `claude -p`
#       in print mode READS that stdin: with a large survivors stream it
#       slurps the remaining units and folds them into its reply, derailing
#       the per-unit verdict AND corrupting the loop's read position
#       (observed: 0/787, 0/353, 4/4-abort on real large-repo mines).
#       The ORIGINAL fix was `</dev/null` (dedicate stdin to nothing).
#
#   The loom-oekt fix REPLACES `</dev/null` with `< "$promptfile"`. This
#   STILL satisfies (B): stdin becomes the dedicated prompt file, NOT the
#   loop's survivors fd, so the survivors stream still cannot leak in.
#   Both invariants hold simultaneously — that is exactly what this test
#   pins. We assert claude's stdin is the PROMPT (the salience instruction
#   text), and is NOT the survivors stream (no "filler"/survivor markers).
#
# Test strategy (mirrors loom-mine-history-claude-failure.test.sh):
#   - PATH-prepended `claude` + `gh` stubs.
#   - The `claude` stub here is a WITNESS that:
#       * SIMULATES the kernel E2BIG: if its prompt arrives as an argv
#         argument longer than _MAX_ARG (set below), it dies with
#         "Argument list too long" + a non-zero exit, EXACTLY as exec
#         would on a real oversized argv. (Pre-fix code passes the prompt
#         on argv → this fires → the oversized unit gets no draft.)
#       * records its received stdin to CLAUDE_STDIN_FILE so the test can
#         assert stdin carries the PROMPT, not the survivors stream.
#   - A REAL temp git repo whose decision commits include ONE with a body
#     far larger than _MAX_ARG, plus several normal ones, so the salience
#     pass runs over >= 2 survivors and the oversized unit is exercised.
#
# Run:  bash lib/tests/loom-mine-history-stdin-isolation.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$LOOM_ROOT/lib/loom-mine-history.sh"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Simulated per-argument limit. Far below a real kernel MAX_ARG_STRLEN
# (~128KiB) so the fixture's oversized body is small enough to build
# quickly while still overflowing the stub's argv check. The fixture's
# big commit body is sized comfortably above this.
SIM_MAX_ARG=8192

# --- Stub directory --------------------------------------------------
#
# `gh` degrades to git-only (auth fails). `claude` is a WITNESS:
#   - If the salience prompt arrives as an argv ARGUMENT (pre-fix), and
#     that argument exceeds SIM_MAX_ARG bytes, the stub dies with
#     "Argument list too long" (rc 1) — simulating the kernel E2BIG that
#     a real oversized argv would raise BEFORE claude even starts. This
#     makes the pre-fix oversized unit FAIL → no draft.
#   - Records the stdin it received to CLAUDE_STDIN_FILE (overwritten per
#     call; the test inspects the last call's stdin). With the fix the
#     prompt arrives on stdin → this file holds the salience prompt. With
#     the old </dev/null it would be empty; with the leak bug it would
#     hold survivors text.
#   - On the happy path, emits a valid SALIENT reply + exits 0.
mk_stubs_dir() {
  local d
  d=$(mktemp -d)

  cat > "$d/gh" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  auth) exit 1 ;;
  pr)   echo "[]" ;;
  api)  : ;;
  *)    exit 1 ;;
esac
EOF

  cat > "$d/claude" <<EOF
#!/usr/bin/env bash
# WITNESS stub for loom-mine-history salience calls.
SIM_MAX_ARG=$SIM_MAX_ARG
EOF
  cat >> "$d/claude" <<'EOF'
# 1. Find the prompt if it was passed as an argv argument (the -p value).
#    Pre-fix code does:  claude -p "<prompt>" --model ... < ...
#    Post-fix code does: claude -p --model ... < promptfile   (no -p value;
#    or `-p` with the prompt only on stdin). We scan argv for the value
#    following a bare `-p`/`--print` that is NOT itself a flag.
argv_prompt=""
prev=""
for a in "$@"; do
  if [ "$prev" = "-p" ] || [ "$prev" = "--print" ]; then
    case "$a" in
      -*) : ;;            # next token is a flag → -p took no inline value
      *)  argv_prompt="$a" ;;
    esac
  fi
  prev="$a"
done

# 2. Simulate the kernel E2BIG: a too-long argv argument never execs.
if [ "${#argv_prompt}" -gt "$SIM_MAX_ARG" ]; then
  echo "claude: Argument list too long" >&2
  exit 1
fi

# 3. Record the stdin we actually received (the prompt, post-fix).
stdin_data=$(cat 2>/dev/null)
if [ -n "${CLAUDE_STDIN_FILE:-}" ]; then
  printf '%s' "$stdin_data" > "$CLAUDE_STDIN_FILE"
fi

# Always a valid, successful, SALIENT reply.
echo '{"salient":true,"verbatim":"v","synthesis":"s","decision":"d"}'
EOF

  chmod +x "$d/gh" "$d/claude"
  echo "$d"
}

# --- git fixture repo -------------------------------------------------
# Several substantial decision commits, INCLUDING one whose body is far
# larger than SIM_MAX_ARG (the ARG_MAX-overflow trigger). A unique marker
# string in the surrounding commits lets the leak check confirm claude's
# stdin is NOT the survivors stream.
SURVIVOR_MARKER="SURVIVORMARKER_filler_unit"
BIG_MARKER="OVERSIZEDBODYMARKER"
mk_fixture_repo_big() {
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

    # A few normal-sized decision commits (so >= 2 survivors and a
    # non-empty remaining stream after line 1). Each carries the unique
    # SURVIVOR_MARKER so a leaked survivors stream would be detectable.
    local i
    for i in 1 2 3; do
      cat > "schema_$i.sql" <<SQL
CREATE TABLE t$i (id INT PRIMARY KEY, body TEXT);
SQL
      git add -A
      git -c core.hooksPath=/dev/null commit -q -m "Add schema variant $i

We chose design variant $i over the alternative because query latency
on the hot read path dominates; the trade-off is heavier migrations but
faster reads. Decision recorded for downstream consumers.
$SURVIVOR_MARKER $i"
    done

    # ONE oversized-body decision commit: body far exceeds SIM_MAX_ARG so
    # the prompt (instruction + body) overflows a single argv argument.
    local big
    big=$(printf 'x%.0s' $(seq 1 20000))
    cat > "bigdecision.sql" <<SQL
CREATE TABLE big (id INT PRIMARY KEY);
SQL
    git add -A
    git -c core.hooksPath=/dev/null commit -q -m "Add big decision $BIG_MARKER

We chose the partitioned layout over a single flat table because the
read pattern is overwhelmingly by tenant; the rationale below is long
on purpose to overflow the OS per-argument size limit when the prompt
is passed on argv. $big"
  ) || { echo "FIXTURE_BUILD_FAILED" >&2; return 1; }
  echo "$repo"
}

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
# 1. ARG_MAX overflow — an oversized-prompt unit is still processed
#    (loom-oekt). The witness stub dies with "Argument list too long"
#    iff the prompt arrives on argv and exceeds SIM_MAX_ARG. With the
#    tempfile-stdin fix the prompt is NOT on argv → no E2BIG → the
#    oversized unit produces a draft like any other.
# =====================================================================
echo "==> 1. Oversized-prompt salience unit is processed (no 'Argument list too long')"

STUBS=$(mk_stubs_dir)
REPO=$(mk_fixture_repo_big)
OUT=$(mktemp -d)
STDIN_FILE=$(mktemp)
: > "$STDIN_FILE"

export GH_AUTH_OK=0
export CLAUDE_STDIN_FILE="$STDIN_FILE"

out=$(run_mine "$REPO" --out "$OUT" --yes --model fake); rc=$?

# 1a. No "Argument list too long" anywhere in the engine output.
if ! printf '%s' "$out" | grep -q "Argument list too long"; then
  pass "no 'Argument list too long' — prompt did not overflow argv"
else
  fail "salience call hit 'Argument list too long' (prompt passed on argv; ARG_MAX overflow)" "$out"
fi

# 1b. ALL survivors processed, including the oversized one. There are 4
#     decision survivors (3 normal + 1 big); a prompt-on-argv overflow
#     would drop the big one (and possibly trip the failure gate). With
#     the fix all 4 reach claude and check in as processed.
processed=0
[ -f "$OUT/.processed" ] && processed=$(grep -c . "$OUT/.processed" 2>/dev/null)
processed=${processed:-0}
if [ "$processed" -ge 4 ]; then
  pass "loop processed all survivors incl. oversized unit (.processed=$processed)"
else
  fail "loop processed only $processed unit(s) — oversized unit dropped / pass derailed" "$out"
fi

# 1c. Drafts emitted (the salience pass actually ran to completion).
if [ -s "$OUT/drafts.jsonl" ]; then
  pass "salience pass emitted drafts"
else
  fail "salience pass emitted no drafts" "$out"
fi

# =====================================================================
# 2. STDIN is the PROMPT, NOT the survivors stream (rnxp + loom-oekt).
#    The fix routes the prompt to claude on stdin via a temp file. This
#    simultaneously:
#      - feeds claude the prompt (so stdin is non-empty AND is the prompt),
#      - keeps the survivors fd OFF claude's stdin (the rnxp leak guard).
#    We assert the recorded stdin carries the salience INSTRUCTION text
#    and does NOT carry the survivors-stream marker.
# =====================================================================
echo "==> 2. claude stdin is the prompt file, not the survivors stream"

# 2a. stdin carries the salience prompt (the instruction header is the
#     stable, prompt-only signature; it is built in the engine and is NOT
#     part of any survivor's commit text).
if grep -q "mining a software project's history for DESIGN DECISIONS" "$STDIN_FILE" 2>/dev/null; then
  pass "claude stdin carries the salience prompt (fed via tempfile on stdin)"
else
  fail "claude stdin does NOT carry the salience prompt — prompt not routed to stdin" \
       "$(head -c 400 "$STDIN_FILE" 2>/dev/null)"
fi

# 2b. LEAK GUARD (rnxp): stdin must NOT be the survivors stream. If the
#     loop's $survivors fd had leaked in, claude's stdin would contain the
#     OTHER survivors' bodies — detectable by the unique SURVIVOR_MARKER
#     from a DIFFERENT unit than the one being asked about. The prompt for
#     a single unit only ever names that one unit; multiple distinct
#     survivor markers on stdin == a leak.
marker_hits=$(grep -o "$SURVIVOR_MARKER" "$STDIN_FILE" 2>/dev/null | wc -l | tr -d ' ')
if [ "${marker_hits:-0}" -le 1 ]; then
  pass "survivors stream did NOT leak into claude stdin (survivor markers on stdin: ${marker_hits:-0})"
else
  fail "survivors stream LEAKED into claude stdin (${marker_hits} survivor markers — loop fd inherited)" \
       "$(head -c 600 "$STDIN_FILE" 2>/dev/null)"
fi

# =====================================================================
# 3. STRUCTURAL pin — the salience claude call feeds the prompt on stdin
#    from a file (NOT `claude -p "$prompt"` on argv, and NOT </dev/null).
#    Defense-in-depth alongside the behavioral witness above: documents
#    the exact fix mechanism so a future refactor that reintroduces the
#    argv-prompt or drops the stdin redirect is caught at the source.
# =====================================================================
echo "==> 3. Salience claude call source feeds the prompt on stdin (< tempfile)"

# 3a. The salience call must redirect stdin from a variable file (the
#     prompt temp file), not from /dev/null and not by inheriting the loop.
if grep -E 'claude -p[^|]*<[[:space:]]*"\$[A-Za-z_][A-Za-z0-9_]*"' "$LIB" >/dev/null 2>&1; then
  pass "salience claude -p call redirects stdin from a prompt file (< \"\$var\")"
else
  fail "salience claude -p call does not feed stdin from a prompt file" \
       "$(grep -n 'claude -p' "$LIB")"
fi

# 3b. The prompt must NOT be passed as the inline -p argument any more
#     (that is the ARG_MAX-overflow path). Match only NON-comment lines so
#     the explanatory comment that quotes the retired anti-pattern (to
#     document why it was removed) is not mistaken for live code.
if grep -E '^[[:space:]]*[^#[:space:]].*claude -p "\$prompt"' "$LIB" >/dev/null 2>&1; then
  fail "salience claude call still passes the prompt as an argv argument (ARG_MAX risk)" \
       "$(grep -nE '^[[:space:]]*[^#[:space:]].*claude -p "\$prompt"' "$LIB")"
else
  pass "salience prompt is not passed as an inline argv argument (code, ignoring comments)"
fi

# =====================================================================
# Summary
# =====================================================================
echo
echo "loom-mine-history-stdin-isolation: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
exit 0
