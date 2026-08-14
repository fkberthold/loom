#!/usr/bin/env bash
# lib/tests/bd-list-unbounded.test.sh
#
# THE GATE: every `bd list` / `bd ready` invocation in loom's shipped
# primitives whose output is CONSUMED AS A SET must pass an explicit
# limit that defeats bd's default window (loom-apcn).
#
# THE BUG. bd v1.0.2 truncates by default — `bd list` at 50, `bd ready`
# at 10 — and the truncation notice does NOT survive loom's normal pipe
# idioms. In text mode the notice goes to stdout, where a `| grep` eats
# it; in json mode it goes to stderr, where `2>/dev/null` or a `| jq`
# eats it. The truncation is NOT recency-ordered, so a "what closed
# since X" filter over a truncated set can miss exactly the rows it
# exists to report. Every set-consuming caller is therefore silently
# under-reporting, with no diagnostic anywhere.
#
# THE CONTRACT (the RED: line on loom-apcn):
#   INVARIANT: every `bd list` / `bd ready` invocation in loom's shipped
#   primitives whose output is CONSUMED AS A SET (parsed, grepped,
#   filtered, counted) passes an explicit limit that defeats bd's
#   default window; a suite gate scans agents/, commands/, skills/,
#   scripts/, hooks/, lib/ by GLOB (never a hardcoded list, per the
#   hook-source-ladder precedent) and FAILS naming any unbounded
#   set-consuming invocation. Invocations bounded by construction
#   (`--limit N`, `-n N`, `| head -1`) are exempt.
#
# Per gate-don't-advise (loom-wj26.1) this is a correctness invariant,
# so it GATES via script/test rather than nudging. Shape follows
# lib/tests/hook-source-ladder.test.sh — the direct precedent: a `scan`
# function driven BY GLOB (never a hardcoded list, so a newly added
# caller cannot ship unbounded), a planted-violation RED case proving
# the scanner has teeth, planted clean cases proving it does not
# false-positive, and a LIVE case over the real tree.
#
# ----------------------------------------------------------------------
# HOW THE SCANNER DISCRIMINATES (three mechanical rules)
#
# "Consumed as a set" is a semantic property; the scanner needs a
# decidable proxy. It uses three, all conservative:
#
#   1. EXECUTABLE CONTEXT. Markdown under agents/, commands/ and
#      skills/ IS executable instruction for an agent, so a real
#      invocation there counts. But prose that merely *mentions* the
#      command must not fire. An occurrence counts only when it is
#      either inline-backticked (`bd list --status=open`) or inside a
#      fenced block tagged bash/sh/shell. An UNTAGGED fence is a
#      transcript, not a script — that is what keeps the worked example
#      in skills/session-startup/SKILL.md ("You: [run bd stats, bd
#      ready, bd list --status=in_progress, ...]") from firing. In
#      shell files, comment lines are skipped — that is what keeps
#      hooks/cwd-drift-guard.sh's "Read-only ops (git status/log/diff/
#      branch, bd list/show/ready/etc.)" from firing.
#
#   2. COMMAND POSITION. The text immediately before the invocation,
#      trimmed of whitespace, must be empty or end in one of
#      ` ( | & ; { — i.e. the invocation is actually being RUN, not
#      quoted inside another command's argument. This is what keeps
#      commands/loom-upstream-gc.md's `echo "... (see bd list
#      --label=upstream:watch)."` from firing.
#
#   3. SET-CONSUMPTION PROXY: the invocation carries at least one
#      `--flag`. An invocation carrying --status= / --label= / --since=
#      / --json is being selected from and machine-read; a bare
#      `bd ready` in prose ("`bd ready` will never surface it") is a
#      display or a mention. This is the proxy for "parsed, grepped,
#      filtered, counted" — deliberately narrower than firing on every
#      occurrence, so the gate names offenders rather than noise.
#
# EXEMPTIONS (bounded by construction): an explicit `--limit N` or
# `-n N` flag on the same invocation, or a pipe into `head`.
# lib/tests/ is excluded wholesale — test fixtures deliberately contain
# unbounded stub invocations.
#
# ----------------------------------------------------------------------
# THE ESCAPE HATCH: `bd-unbounded-ok: <reason>`
#
# Rules 1-3 are heuristics, and a heuristic will always have residue —
# a sentence that carries a flagged command and is nonetheless a true
# statement ABOUT what that query does or does not return, with no
# invocation to bound. Three such sites exist in the live tree today
# (session-startup SKILL.md's two "`bd ready` / `bd list
# --status=in_progress` will never surface it" statements, and
# check-upstream-prs.md's "not in the `bd list --status=open` set on
# the next pass").
#
# The wrong fix is to reword the documentation. `--status=in_progress`
# in those sentences is LOAD-BEARING — it names precisely which query
# fails to surface an above-bead unit; dropping it buys a green gate
# with a vaguer sentence. That pressure recurs on every future mention,
# and the accumulated cost is documentation bent around a scanner.
#
# So the gate ships an explicit, greppable marker, trailing on the same
# LOGICAL line as the invocation:
#
#   markdown:  <!-- bd-unbounded-ok: <reason> -->
#   shell:     # bd-unbounded-ok: <reason>
#
# Matched ANCHORED — the token must appear inside its comment wrapper,
# parallel to loom's `Files:` / `RED:` / `AUTOFAN-EXCLUDE:` /
# `evidence:` convention — so a mid-prose mention of the string is not
# itself an exemption. `<reason>` is REQUIRED and free text: a marker
# with an EMPTY reason does NOT exempt, so the hatch costs a sentence
# to use.
#
# This is the same shape as loom's `LOOM_*_SKIP=1` hook bypasses: the
# escape hatch exists, it is visible in the diff, and it carries its
# justification inline. It does not weaken the invariant — it makes the
# exemptions explicit and countable instead of implicit in a scanner
# heuristic nobody can audit. Granularity is the whole logical line, so
# a marker mutes every invocation on that line; keep them one-per-line.
#
# LIVE EXPECTATION: 19 sites bound + 3 sites marked = 22 resolved. The
# marker count is deliberate and small — a growing tally of markers is
# itself the signal that a rule needs revisiting, not that more markers
# are needed.
#
# Run:  bash lib/tests/bd-list-unbounded.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export LOOM_TEST_LIB_DIR="$LOOM_ROOT/lib"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# ----------------------------------------------------------------------
# Detection
# ----------------------------------------------------------------------

# The scanner proper. Reads one or more files; prints one line per
# offending invocation:  <file>:<line>: <invocation>
read -r -d '' SCAN_AWK <<'AWK_EOF'
# ---- helpers ---------------------------------------------------------

# The invocation is bounded by construction.
function bounded(s) {
  if (s ~ /--limit[= \t]+[0-9]/)      return 1
  if (s ~ /(^|[ \t])-n[ \t]*[0-9]/)   return 1
  if (s ~ /\|[ \t]*head([ \t]|$)/)    return 1
  return 0
}

# The invocation carries at least one --flag (the set-consumption proxy).
function flagged(s) {
  return (s ~ /(^|[ \t])--[a-zA-Z]/)
}

# The invocation sits at command position, not inside another
# command's argument.
function cmdpos(pre,   c) {
  sub(/[ \t]+$/, "", pre)
  if (pre == "") return 1
  c = substr(pre, length(pre), 1)
  return (c == "`" || c == "(" || c == "|" || c == "&" || c == ";" || c == "{")
}

# The logical line carries an explicit `bd-unbounded-ok: <reason>`
# exemption marker, in either its markdown (<!-- ... -->) or its shell
# (# ...) comment form. Matched ANCHORED — the token must sit inside a
# comment wrapper, so a mid-prose mention of the string is not itself
# an exemption. A marker with an EMPTY reason does NOT exempt.
function marked(s,   r) {
  # markdown form: <!-- bd-unbounded-ok: <reason> -->
  if (match(s, /<!--[ \t]*bd-unbounded-ok:/)) {
    r = substr(s, RSTART + RLENGTH)
    if (r !~ /-->[ \t]*$/) return 0        # unterminated comment
    sub(/-->[ \t]*$/, "", r)
    sub(/^[ \t]+/, "", r)
    sub(/[ \t]+$/, "", r)
    return (r != "")
  }
  # shell form: # bd-unbounded-ok: <reason>   (runs to end of line)
  if (match(s, /#[ \t]*bd-unbounded-ok:/)) {
    r = substr(s, RSTART + RLENGTH)
    sub(/^[ \t]+/, "", r)
    sub(/[ \t]+$/, "", r)
    return (r != "")
  }
  return 0
}

# Index of the next `bd list` / `bd ready` at or after `from`, or 0.
function nextocc(s, from,   a, b) {
  a = index(substr(s, from), "bd list")
  b = index(substr(s, from), "bd ready")
  if (a == 0 && b == 0) return 0
  if (a == 0) return from + b - 1
  if (b == 0) return from + a - 1
  return (a < b) ? (from + a - 1) : (from + b - 1)
}

# Examine one LOGICAL line (backslash continuations already joined).
function process(txt, lno,   p, klen, after, prev, pre, args, cut, snip) {
  # The explicit escape hatch, checked before any rule. Line-level
  # granularity: a marker mutes every invocation on its logical line.
  if (marked(txt)) return

  p = 1
  while ((p = nextocc(txt, p)) > 0) {
    klen = (substr(txt, p, 8) == "bd ready") ? 8 : 7

    # `bd listing` / `bd ready-ish` are not invocations.
    after = substr(txt, p + klen, 1)
    if (after ~ /[A-Za-z0-9_-]/) { p += klen; continue }

    prev = (p > 1) ? substr(txt, p - 1, 1) : ""
    pre  = (p > 1) ? substr(txt, 1, p - 1) : ""

    # Rule 1 (markdown outside any fence): must be inline-backticked.
    if (ISMD && !INFENCE && prev != "`") { p += klen; continue }

    # Rule 2: command position.
    if (!cmdpos(pre)) { p += klen; continue }

    # Argument extent: to the closing backtick if inline, else to EOL.
    args = substr(txt, p + klen)
    cut = index(args, "`")
    if (cut > 0) args = substr(args, 1, cut - 1)

    # Rule 3 + exemption.
    if (flagged(args) && !bounded(args)) {
      snip = substr(txt, p, klen) args
      sub(/[ \t]+$/, "", snip)
      printf "%s:%d: %s\n", FILENAME, lno, snip
    }
    p += klen
  }
}

# ---- driver ----------------------------------------------------------

FNR == 1 {
  ISMD = (FILENAME ~ /\.md$/)
  INFENCE = 0; EXECF = 0; buf = ""; bufln = 0
}

{
  line = $0

  # Fenced-code tracking (markdown only). An UNTAGGED fence is a
  # transcript, not a script.
  if (ISMD && line ~ /^[ \t]*(```|~~~)/) {
    if (INFENCE) { INFENCE = 0; EXECF = 0 }
    else {
      info = line
      sub(/^[ \t]*(```|~~~)[ \t]*/, "", info)
      sub(/[ \t].*$/, "", info)
      info = tolower(info)
      INFENCE = 1
      EXECF = (info == "bash" || info == "sh" || info == "shell" || info == "console" || info == "zsh")
    }
    buf = ""; bufln = 0
    next
  }
  if (ISMD && INFENCE && !EXECF) { buf = ""; bufln = 0; next }

  # Comment lines are prose, not invocations.
  if (line ~ /^[ \t]*#/) { buf = ""; bufln = 0; next }

  # Join backslash continuations into one logical line, so a `| head`
  # on a later physical line still exempts the invocation.
  if (buf == "") { bufln = FNR; buf = line } else { buf = buf " " line }
  if (line ~ /\\$/) next

  process(buf, bufln)
  buf = ""; bufln = 0
}

END { if (buf != "") process(buf, bufln) }
AWK_EOF

# scan <root> — prints one offender line per unbounded set-consuming
# invocation found under <root>'s six shipped-primitive directories.
# EMPTY output means clean.
#
# Driven entirely BY GLOB (find over the six directories) — never a
# hardcoded list of files, so a newly added caller is covered
# automatically. lib/tests/ is pruned: fixtures deliberately contain
# unbounded stub invocations.
scan() {
  local root="$1" d
  local -a files=()
  for d in agents commands skills scripts hooks lib; do
    [ -d "$root/$d" ] || continue
    while IFS= read -r f; do
      [ -n "$f" ] && files+=("$f")
    done < <(find "$root/$d" -path "$root/lib/tests" -prune -o -type f -print 2>/dev/null | sort)
  done
  [ "${#files[@]}" -gt 0 ] || return 0
  awk "$SCAN_AWK" "${files[@]}" 2>/dev/null | sed "s#^$root/##"
}

# scan_count <root> — number of files the glob actually reached.
scan_count() {
  local root="$1" d n=0
  for d in agents commands skills scripts hooks lib; do
    [ -d "$root/$d" ] || continue
    n=$((n + $(find "$root/$d" -path "$root/lib/tests" -prune -o -type f -print 2>/dev/null | wc -l)))
  done
  echo "$n"
}

# ----------------------------------------------------------------------
# 1. RED case — planted violations. Proves the scanner has teeth: a
#    no-op scanner that always prints nothing would sail through the
#    LIVE case below exactly as a clean tree does.
# ----------------------------------------------------------------------
echo "==> 1. RED: unbounded set-consuming invocations are detected"

BAD=$(mktemp -d)
mkdir -p "$BAD/agents" "$BAD/commands" "$BAD/skills" "$BAD/scripts" "$BAD/hooks" "$BAD/lib"

# 1a. Shell: command-substitution capture piped into a parser.
cat > "$BAD/scripts/gather" <<'EOF'
#!/usr/bin/env bash
beads=$(bd list --label=upstream:watch --status=open --json 2>/dev/null) || beads='[]'
EOF

# 1b. Shell: continuation-line pipeline into jq (no bound anywhere).
cat > "$BAD/hooks/sweep.sh" <<'EOF'
#!/usr/bin/env bash
ids=$(bd list --status=closed --json 2>/dev/null \
  | jq -r '.[].id')
EOF

# 1c. Markdown: inline-backticked instruction in an agent definition.
cat > "$BAD/agents/onboarder.md" <<'EOF'
Enumerate the project's open beads via `bd list --status=open --json`
and test each description against the canonical regex.
EOF

# 1d. Markdown: a ```bash fence in a slash command.
cat > "$BAD/commands/check.md" <<'EOF'
Gather the labeled set:

```bash
bd list --label upstream:loom --status=open --json
```
EOF

# 1e. Markdown: `bd ready --json` consumed by a script, in a skill.
cat > "$BAD/skills/fanout.md" <<'EOF'
The script reads `bd ready --json`, finds sibling beads, and emits waves.
EOF

# 1f. Marker with an EMPTY reason does NOT exempt — markdown form.
#     This is what stops the escape hatch degrading into a blanket
#     mute: the hatch has to cost a sentence to use.
cat > "$BAD/skills/empty-reason.md" <<'EOF'
Enumerate the open set via `bd list --status=open --json`. <!-- bd-unbounded-ok: -->
EOF

# 1g. Marker with an EMPTY reason does NOT exempt — shell form.
cat > "$BAD/hooks/empty-reason.sh" <<'EOF'
#!/usr/bin/env bash
out=$(bd list --status=closed --json)   # bd-unbounded-ok:
EOF

# 1h. The token OUTSIDE a comment wrapper is not a marker. Anchored
#     matching, parallel to Files: / RED: / AUTOFAN-EXCLUDE: — a
#     mid-prose mention of the string must not mute the line.
cat > "$BAD/commands/mentions-token.md" <<'EOF'
The `bd-unbounded-ok:` marker exempts a mention; enumerate the rest
via `bd list --label=upstream:watch --json` as usual.
EOF

bad_out=$(scan "$BAD")

check_red() {
  if echo "$bad_out" | grep -q "^$1:"; then
    pass "RED $2"
  else
    fail "RED $2 — NOT detected" "$bad_out"
  fi
}

check_red 'scripts/gather'      '1a: shell command-substitution capture'
check_red 'hooks/sweep\.sh'     '1b: shell continuation-line pipeline'
check_red 'agents/onboarder\.md' '1c: inline-backticked agent instruction'
check_red 'commands/check\.md'  '1d: bash-fenced slash-command block'
check_red 'skills/fanout\.md'   '1e: `bd ready --json` in a skill'
check_red 'skills/empty-reason\.md' '1f: marker with EMPTY reason (markdown) still reported'
check_red 'hooks/empty-reason\.sh'  '1g: marker with EMPTY reason (shell) still reported'
check_red 'commands/mentions-token\.md' '1h: token outside a comment wrapper is not a marker'

# The failure output must NAME each site, not just count them.
if echo "$bad_out" | grep -qE '^[a-z]+/[A-Za-z0-9._-]+:[0-9]+: bd (list|ready) '; then
  pass "RED: offender lines carry file:line: <invocation>"
else
  fail "RED: offender lines are not in file:line: <invocation> form" "$bad_out"
fi

rm -rf "$BAD"

# ----------------------------------------------------------------------
# 2. GREEN case — bounded invocations and mere mentions are NOT flagged.
#    Proves the scanner does not simply flag every occurrence.
# ----------------------------------------------------------------------
echo "==> 2. GREEN: bounded invocations and prose mentions are not flagged"

GOOD=$(mktemp -d)
mkdir -p "$GOOD/agents" "$GOOD/commands" "$GOOD/skills" "$GOOD/scripts" "$GOOD/hooks" "$GOOD/lib/tests"

# 2a. Bounded by `| head -1`.
cat > "$GOOD/hooks/nudge.sh" <<'EOF'
#!/usr/bin/env bash
IP_LINE=$(bd list --status=in_progress 2>/dev/null | head -1 || true)
EOF

# 2b. Bounded by an explicit --limit N.
cat > "$GOOD/lib/id-extract.sh" <<'EOF'
#!/usr/bin/env bash
first_id=$( (cd "$root" 2>/dev/null && bd list --limit 1 --json 2>/dev/null) \
  | jq -r '.[0].id')
EOF

# 2c. Bounded by an explicit -n N (deliberate display cap).
cat > "$GOOD/scripts/fanout" <<'EOF'
#!/usr/bin/env bash
ready_json="$(bd ready --json -n 100 2>/dev/null)"
EOF

# 2d. Shell COMMENT naming the commands — a mention, not an invocation.
cat > "$GOOD/hooks/drift-guard.sh" <<'EOF'
#!/usr/bin/env bash
# Read-only ops (git status/log/diff/branch, bd list/show/ready/etc.)
# are NOT in the allowlist -- they're safe from any cwd.
exit 0
EOF

# 2e. Markdown UNTAGGED fence — a transcript, not a script.
cat > "$GOOD/skills/startup.md" <<'EOF'
## Example

```
User: ok pick up where we left off

You: [run bd stats, bd ready, bd list --status=in_progress, mempalace_status,
      mempalace_search for "session close"]
```
EOF

# 2f. Bare backticked mention with no flags — prose, not set consumption.
cat > "$GOOD/skills/explore.md" <<'EOF'
An exploration has no single RED->GREEN of its own (so `bd ready` will
never surface it) and `bd list` is not where its state lives.
EOF

# 2g. Quoted inside another command's argument — not command position.
cat > "$GOOD/commands/gc.md" <<'EOF'
```bash
echo "  Close or reject the watch-bead first (see bd list --label=upstream:watch)."
```
EOF

# 2h. lib/tests/ fixtures are excluded wholesale.
cat > "$GOOD/lib/tests/fixture.test.sh" <<'EOF'
#!/usr/bin/env bash
out=$(bd list --status=open --json)
EOF

# 2i. EXPLICIT MARKER, markdown form — a true statement about what a
#     query does NOT return. There is no invocation to bound, and the
#     `--status=in_progress` in the sentence is load-bearing: it names
#     precisely which query fails to surface an above-bead unit.
cat > "$GOOD/skills/design-cycle.md" <<'EOF'
A design cycle is an above-bead unit: it is **not a bead**, so `bd ready`
/ `bd list --status=in_progress` will never surface it. <!-- bd-unbounded-ok: statement about what the query does not return; no invocation to bound -->
EOF

# 2j. EXPLICIT MARKER, shell form.
cat > "$GOOD/scripts/probe" <<'EOF'
#!/usr/bin/env bash
# A one-shot liveness probe; the caller only tests exit status.
bd list --status=open --json >/dev/null 2>&1   # bd-unbounded-ok: exit-status probe, output discarded
EOF

good_out=$(scan "$GOOD")

if [ -z "$good_out" ]; then
  pass "GREEN: bounded invocations + prose mentions produce no offenders"
else
  fail "GREEN: clean forms were flagged" "$good_out"
fi

rm -rf "$GOOD"

# ----------------------------------------------------------------------
# 3. LIVE case — the real shipped tree. This is the RED->GREEN driver
#    for script/test: a regression fails the suite the instant it lands.
# ----------------------------------------------------------------------
echo "==> 3. LIVE: every set-consuming bd list/ready invocation is bounded"

file_count=$(scan_count "$LOOM_ROOT")
if [ "$file_count" -gt 0 ]; then
  pass "scanned $file_count file(s) by glob across agents/ commands/ skills/ scripts/ hooks/ lib/ (not a hardcoded list)"
else
  fail "no files found under $LOOM_ROOT — the gate would vacuously pass"
fi

live_out=$(scan "$LOOM_ROOT")

if [ -z "$live_out" ]; then
  pass "no unbounded set-consuming invocations"
else
  n=$(echo "$live_out" | wc -l)
  fail "$n unbounded set-consuming bd list/ready invocation(s) — each silently truncates at bd's default window (list 50 / ready 10) with no surviving notice" "$live_out"
fi

# ----------------------------------------------------------------------
echo ""
echo "Total: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
