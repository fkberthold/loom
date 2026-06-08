#!/usr/bin/env bash
# Locking-spec test for skills/session-startup/SKILL.md active-explorations scan
# (loom-ld1q.3).
#
# An exploration (opened via `/explore <idea>`) is a NEW above-bead, SUB-design
# primitive — NOT a bead, NOT a design cycle (no soundness gate). Its memory is
# ONE drawer in wing `loom` room `decisions`, tagged `exploration`, carrying a
# STATUS of `active` | `rested` | `promoted`. Like a `/design-a-cycle` (step 1d),
# an exploration is above-bead, so `bd ready` / `bd list --status=in_progress`
# will NEVER surface it — a cold-start needs a dedicated MemPalace scan or an
# active exploration sits forgotten across sessions.
#
# This step mirrors step 1d (ACTIVE DESIGN CYCLE) exactly: a parallel INFO-only
# MemPalace scan that surfaces resumable above-bead context at cold start.
#
# Contract:
#   - A dedicated substep scans MemPalace for drawers tagged `exploration` with
#     STATUS `active`, and prints an "ACTIVE EXPLORATION:" header — one line per
#     active exploration (topic + open-threads count + current-understanding
#     snippet), analogous to 1d's "ACTIVE DESIGN CYCLE:" line.
#   - It SKIPS rested/promoted explorations (terminal states) — these are not
#     resumable, surfacing them would be noise.
#   - It is INFO-only — surfaces context, never claims or advances an exploration.
#   - Negative case: when NO exploration is active, the header is skipped
#     entirely (no empty "ACTIVE EXPLORATION" block on every cold-start).
#   - Tolerance: degrades gracefully (skip line, never fail the skill) when
#     MemPalace is offline / the search errors.
#   - Light mode runs the scan (cheap MemPalace scan, high-signal); off mode
#     skips it along with the rest of the skill.
#   - Placed adjacent to the design-cycle scan (step 1d) and before "Pick a bead".
#
# Run:  bash lib/tests/session-startup-exploration-scan.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL_FILE="$LOOM_ROOT/skills/session-startup/SKILL.md"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

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

assert_before() {
  # Assert pattern A appears at a lower line number than pattern B.
  local name="$1" pattern_a="$2" pattern_b="$3"
  local line_a line_b
  line_a=$(grep -nE "$pattern_a" "$SKILL_FILE" | head -1 | cut -d: -f1)
  line_b=$(grep -nE "$pattern_b" "$SKILL_FILE" | head -1 | cut -d: -f1)
  if [ -z "$line_a" ]; then
    fail "$name" "(pattern A not found: $pattern_a)"
  elif [ -z "$line_b" ]; then
    fail "$name" "(pattern B not found: $pattern_b)"
  elif [ "$line_a" -lt "$line_b" ]; then
    pass "$name"
  else
    fail "$name" "(line $line_a >= line $line_b)"
  fi
}

echo "==> Exploration scan exists with ACTIVE EXPLORATION header"
assert_contains "ACTIVE EXPLORATION header label appears in skill" \
  'ACTIVE EXPLORATION'

echo "==> Scan targets MemPalace drawers tagged 'exploration'"
assert_contains "scan references the 'exploration' tag" \
  'tag[^a-z]*exploration|exploration[^a-z]*tag|tagged .exploration.|`exploration`'
assert_contains "scan uses MemPalace search/list" \
  'mempalace_search|mempalace_list_drawers'

echo "==> Scan filters on status=active and skips terminal states"
assert_contains "active status named" \
  'status[ =]+active|status=active|`active`'
assert_contains "rested/promoted terminal states skipped" \
  '(skip|terminal|not.*surface|exclude)[^.]*(rested|promoted)|(rested|promoted)[^.]*(skip|terminal|not.*surface|exclude)'

echo "==> Header line surfaces topic + open-threads + understanding snippet"
assert_contains "open-threads count surfaced" \
  'open[- ]?threads?'
assert_contains "current-understanding snippet surfaced" \
  '(current[- ]?)?understanding'

echo "==> INFO-only — never claims or advances an exploration"
assert_contains "INFO-only language present" \
  'INFO-only|never claims or advances|surfaces context'

echo "==> Empty-case: skip header when no active exploration"
# Negative case discipline — without this, the agent might emit an empty
# ACTIVE EXPLORATION header on every cold-start even when nothing is active.
assert_contains "skip-when-empty clause" \
  'no active exploration|when none|Skip the header|no exploration.*active'

echo "==> Tolerance: degrade gracefully if MemPalace offline / search errors"
assert_contains "tolerance language present" \
  '(MemPalace|mempalace).*(offline|error)|degrade|skip.*line'

echo "==> Tolerance contract — explicit 'never fail' clause"
# Without this, future edits could weaken tolerance and re-introduce a
# cold-start that crashes when MemPalace is unreachable.
assert_contains "step asserts 'never fail the skill'" \
  '[Nn]ever fail the skill'

echo "==> Light mode runs the scan; off mode skips the whole skill"
assert_contains "scan stays in light mode" \
  'light.*(exploration|explorations? scan)|(exploration|explorations? scan).*light'
assert_contains "off-mode bullet still says skip the skill entirely" \
  'off.*skip the skill entirely|skip the skill entirely'

echo "==> Scan placed adjacent to design-cycle scan and before 'Pick a bead'"
assert_before "exploration scan precedes 'Pick a bead'" \
  'ACTIVE EXPLORATION' '^[0-9]+[a-z]?\.[[:space:]]+\*\*Pick a bead'
assert_before "design-cycle scan precedes exploration scan (adjacency)" \
  'ACTIVE DESIGN CYCLE' 'ACTIVE EXPLORATION'

echo ""
echo "==================================="
echo "RESULTS: $passed passed, $failed failed"
echo "==================================="

[ "$failed" -eq 0 ]
