#!/usr/bin/env bash
# lib/tests/create-beads-skill.test.sh
#
# Contract test for skills/create-beads/SKILL.md (loom-0rxa step 2).
#
# create-beads was ported out of the beadpowers fork so loom owns the
# design-to-beads handoff outright and the dead `beadpowers@beadpowers-dev`
# plugin can be retired. The port is not a copy. Three things had to
# change on the way in, and this test pins all three so they cannot drift
# back:
#
#   (a) IDENTITY. Loom skills install to ~/.claude/skills/<name>/SKILL.md
#       and are invoked bare, so the skill is `create-beads` and never
#       `beadpowers:create-beads`. Front matter has to parse, because an
#       unparseable header ships a skill nothing can invoke.
#
#   (b) BOUNDED QUERIES. The source's closing block ran `bd ready` and
#       `bd list --parent <epic-id>` with no limit. Both truncate at bd's
#       default window, and the truncation notice does not survive loom's
#       pipe idioms, so a skill that tells an agent to read the result as
#       a set is telling it to read a partial one. loom-conventions.md
#       requires an explicit `--limit 0` on every set-consuming
#       invocation.
#
#   (c) LOOM'S BEAD-DESCRIPTION FORMAT. The source carried `Files:` and
#       nothing else. Loom mandates three structured lines a downstream
#       consumer reads: `Files:` (the fan-out detector's disjointness
#       input), `RED:` (the spec a bead inherits from a testable design
#       decision), and `AUTOFAN-EXCLUDE:` (the opt-out for work that must
#       not be auto-dispatched). The splitting heuristic that decides
#       sibling beads against one bead belongs with them.
#
# Per gate-don't-advise (loom-wj26.1) these are correctness invariants
# about a shipped primitive, so they gate via script/test.
#
# Clause (b) discriminates the way lib/tests/bd-list-unbounded.test.sh
# does: an occurrence inside a bash/sh/shell-tagged fence is an
# invocation, and an occurrence in prose is a mention. That keeps the
# gate from firing on a future sentence that names a command without
# running it.
#
# Run:  bash lib/tests/create-beads-skill.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL_FILE="$LOOM_ROOT/skills/create-beads/SKILL.md"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# assert_contains <name> <extended-regex>
# Passes when the skill prose carries the pattern.
assert_contains() {
  local name="$1" pattern="$2"
  if [ ! -f "$SKILL_FILE" ]; then
    fail "$name" "(file missing: $SKILL_FILE)"
    return
  fi
  if grep -qE "$pattern" "$SKILL_FILE"; then
    pass "$name"
  else
    fail "$name" "(pattern not found: $pattern)"
  fi
}

# assert_absent <name> <extended-regex>
# Passes when the skill prose does NOT carry the pattern.
assert_absent() {
  local name="$1" pattern="$2"
  if [ ! -f "$SKILL_FILE" ]; then
    fail "$name" "(file missing: $SKILL_FILE)"
    return
  fi
  if grep -qE "$pattern" "$SKILL_FILE"; then
    fail "$name" "$(grep -nE "$pattern" "$SKILL_FILE")"
  else
    pass "$name"
  fi
}

# ---------------------------------------------------------------------------
echo "==> Clause (a): the skill ships at its loom path with valid front matter"

if [ -f "$SKILL_FILE" ]; then
  pass "skills/create-beads/SKILL.md exists"
else
  fail "skills/create-beads/SKILL.md exists" "(expected at $SKILL_FILE)"
fi

# Front matter: line 1 opens the block, a later line closes it, and the
# two required keys sit between them. Parsed rather than grepped, so a
# `name:` further down the body cannot stand in for the header.
if [ -f "$SKILL_FILE" ]; then
  fm_ok=$(awk '
    NR == 1        { if ($0 == "---") { open = 1 } else { exit } ; next }
    open && $0 == "---" { closed = 1; exit }
    open && /^name:[ \t]*create-beads[ \t]*$/  { has_name = 1 }
    open && /^description:[ \t]*[^ \t]/        { has_desc = 1 }
    END { print (closed && has_name && has_desc) ? "ok" : "bad" }
  ' "$SKILL_FILE")
  if [ "$fm_ok" = "ok" ]; then
    pass "front matter opens, closes, and carries name: create-beads + a description"
  else
    fail "front matter opens, closes, and carries name: create-beads + a description" \
      "$(sed -n '1,6p' "$SKILL_FILE")"
  fi
fi

# The skill is invoked bare. A surviving plugin prefix would name a
# plugin loom is retiring, and nothing would answer to it.
assert_absent "no 'beadpowers:' plugin prefix survives the port" 'beadpowers:'

# ---------------------------------------------------------------------------
echo "==> Clause (b): every set-consuming bd list / bd ready is bounded"

# Offending invocations, one per line, as <line>: <text>. An occurrence
# counts only inside a bash/sh/shell/console/zsh-tagged fence. An
# UNTAGGED fence is a transcript and bare prose is a mention. Bounded by
# construction: --limit N, -n N, or a pipe into head.
read -r -d '' SCAN_AWK <<'AWK_EOF'
/^[ \t]*(```|~~~)/ {
  if (infence) { infence = 0; execf = 0 }
  else {
    info = $0
    sub(/^[ \t]*(```|~~~)[ \t]*/, "", info)
    sub(/[ \t].*$/, "", info)
    info = tolower(info)
    infence = 1
    execf = (info == "bash" || info == "sh" || info == "shell" || info == "console" || info == "zsh")
  }
  next
}
!(infence && execf)                 { next }
!/bd (list|ready)([ \t]|$)/         { next }
/--limit[= \t]+[0-9]/               { next }
/(^|[ \t])-n[ \t]*[0-9]/            { next }
/\|[ \t]*head([ \t]|$)/             { next }
{ printf "%d: %s\n", FNR, $0 }
AWK_EOF

scan() { awk "$SCAN_AWK" "$1" 2>/dev/null; }

# Teeth first. A scanner that printed nothing would sail through the live
# clause below exactly as a clean file does, so plant both an unbounded
# invocation and the forms that must NOT fire.
PROBE=$(mktemp)
cat > "$PROBE" <<'EOF'
Prose naming `bd ready` and `bd list --status=open` runs nothing.

```
You: [run bd ready, bd list --parent epic-1]
```

```bash
bd ready --limit 0
bd list --parent <epic-id> --limit 0
bd list --status=open | head -1
bd ready --json -n 20
```

```bash
bd ready
```
EOF
probe_out=$(scan "$PROBE")
if [ "$(echo "$probe_out" | wc -l)" = "1" ] && echo "$probe_out" | grep -q 'bd ready$'; then
  pass "scanner has teeth: flags the one unbounded fenced invocation, spares prose + transcript + bounded forms"
else
  fail "scanner has teeth: expected exactly the bare fenced 'bd ready'" "$probe_out"
fi
rm -f "$PROBE"

if [ -f "$SKILL_FILE" ]; then
  unbounded=$(scan "$SKILL_FILE")
  if [ -z "$unbounded" ]; then
    pass "no unbounded bd list / bd ready invocation in an executable fence"
  else
    n=$(echo "$unbounded" | wc -l)
    fail "$n unbounded bd list / bd ready invocation(s). Each truncates silently at bd's default window" \
      "$unbounded"
  fi
else
  fail "no unbounded bd list / bd ready invocation in an executable fence" \
    "(file missing: $SKILL_FILE)"
fi

# The two the port had to fix, pinned positively. A scanner that finds
# nothing passes a file that dropped the commands altogether.
assert_contains "the ready query passes --limit 0" \
  'bd ready([ \t]+[^ \t`]+)*[ \t]+--limit[ \t]+0'
assert_contains "the child-task listing passes --limit 0" \
  'bd list([ \t]+[^ \t`]+)*[ \t]+--limit[ \t]+0'

# ---------------------------------------------------------------------------
echo "==> Clause (c): the bead-description format names loom's three lines"

assert_contains "description format names Files:"            '(^|[^A-Za-z-])Files:'
assert_contains "description format names RED:"              '(^|[^A-Za-z-])RED:'
assert_contains "description format names AUTOFAN-EXCLUDE:"  'AUTOFAN-EXCLUDE:'

# Each line is worth nothing as a token nobody knows the purpose of, so
# the skill has to say what a downstream consumer does with it.
assert_contains "Files: is tied to the fan-out detector's disjointness test" \
  '[Ff]an-?out|disjoint'
assert_contains "RED: is tied to the spec a bead inherits" \
  '[Ii]nherit|executable spec|testable'
assert_contains "AUTOFAN-EXCLUDE: is tied to keeping work out of a wave" \
  '(wave|auto-dispatch)'

# ---------------------------------------------------------------------------
echo "==> Clause (d): the splitting heuristic decides siblings against one bead"

assert_contains "splitting heuristic names sibling beads under an umbrella" \
  'sibling'
assert_contains "splitting heuristic names the independence test" \
  '[Ii]ndependent'

# ---------------------------------------------------------------------------
echo ""
echo "Total: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
