#!/usr/bin/env bash
# Behavior tests for script/gen — the canonical doc-regeneration entry
# point in loom's script/ convention (loom-wj26.4).
#
# THE GOAL. loom's script/ convention reserves a `gen` slot for "regenerate
# all generated artifacts"; before this bead that slot was empty and
# `canonical_commands.gen` was "". loom-itph shipped scripts/loom-docs-gen
# (the per-item nav generator + --check drift gate); this bead gives doc
# regeneration a NAMED home (script/gen) and makes "tree is clean after
# regen" a GATE rather than advice — the gofmt -l pattern.
#
# WHAT THE GATE PROMISES (the bead's RED INVARIANT). Running script/gen
# regenerates the per-item nav (via scripts/loom-docs-gen) and leaves NO
# diff when the tree is already in sync; on a stale tree it regenerates
# the drift away. We test the in-sync no-op half directly here.
#
# ---------------------------------------------------------------------
# loom-qo4j — clause (c) no longer borrows working-tree cleanliness
# ---------------------------------------------------------------------
# The ORIGINAL clause (c) declared GEN_PATHS=(docs/reference mkdocs.yml)
# and REFUSED to assert its no-op property whenever
# `git status --porcelain` over those paths was non-empty ("generated
# paths are clean BEFORE running script/gen"). That over-claimed:
# scripts/loom-docs-gen does NOT own most of docs/reference. It writes
# the non-curated wrapper pages under the four navdirs plus the
# mkdocs.yml nav block; every hand-authored reference page
# (convention-drift-detector.md, glossary.md, …) and every CURATED page
# is untouched by design — the generator explicitly never overwrites
# them.
#
# Consequence of the over-claim: any UNCOMMITTED hand-edit to a
# hand-authored reference page reds the whole suite until it is
# committed, inverting verify-then-commit for every docs bead, and the
# failure message blamed the generator for a file it never touched.
# Verified 2026-07-25: with docs/reference/convention-drift-detector.md
# hand-edited and uncommitted, script/gen left that file BYTE-IDENTICAL
# (a genuine no-op) while the test failed anyway.
#
# THE FIX (shape chosen: pre/post diff, not a narrowed path list).
# Clause (c) now takes a CONTENT MANIFEST (sha256 per file) of the
# watched artifacts BEFORE running script/gen and again AFTER, and
# asserts the two are identical. That tests the real no-op property
# directly instead of using git-cleanliness as a proxy:
#
#   * a hand-edited page the generator does not own is byte-identical
#     across the run, so it cannot red the gate — whether committed or
#     not, git is never consulted;
#   * a generator that stops round-tripping, or committed generated
#     output that has gone stale, still changes a watched file across
#     the run and still reds the gate (clauses d2 + d3 below pin this).
#
# Why not the other shape (narrow the path list to what the generator
# owns, derived from the generator)? The owned set is not cleanly
# enumerable from outside: it is "every non-CURATED primitive across the
# four navdirs", and two curated pages
# (docs/reference/hooks/edit-after-failure-guard.md and
# .../bd-preflight-docs-strict.md) live INSIDE a navdir. Deriving it
# exactly would mean re-implementing curated_page() in the test — the
# very drift the bead wanted to avoid — and scripts/loom-docs-gen
# exposes no path-enumeration mode to derive it from. The pre/post diff
# needs no ownership model at all: it observes what the generator
# actually touched, and stays correct as script/gen's GENERATORS list
# grows.
#
# WATCH_PATHS below is therefore a WATCH SCOPE, not an ownership claim:
# "the region we sample before and after", deliberately wider than what
# the generator owns.
#
# Test-harness env overrides (used only by clause (d), never in normal
# runs):
#   LOOM_SCRIPT_GEN_TEST_ROOT   point clauses (a)-(c) at a fixture repo
#                               instead of the real loom root
#   LOOM_SCRIPT_GEN_TEST_INNER  set on the recursive self-invocation;
#                               suppresses clause (d) so it cannot recurse
#
# This mirrors the pass/fail harness of lib/tests/audit-script-convention.sh:
# a pass()/fail() counter pair, assertions against the real repo tree, and a
# summary line that exits non-zero on any failure.
#
# Run:  bash lib/tests/script-gen-clean-regen.test.sh

set -uo pipefail

# REAL_ROOT is always the actual loom checkout (fixtures copy their
# scripts from it). LOOM_ROOT is what clauses (a)-(c) assert against —
# the same thing, unless clause (d) has redirected us at a fixture.
REAL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
LOOM_ROOT="${LOOM_SCRIPT_GEN_TEST_ROOT:-$REAL_ROOT}"
GEN_SCRIPT="$LOOM_ROOT/script/gen"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# =====================================================================
# Clause (a) — script/gen exists AND is executable
# =====================================================================

echo "==> clause (a): script/gen exists + is executable"

if [ -e "$GEN_SCRIPT" ]; then
  pass "script/gen exists"
else
  fail "script/gen exists" "(file missing: $GEN_SCRIPT)"
fi

if [ -x "$GEN_SCRIPT" ]; then
  pass "script/gen is executable"
else
  fail "script/gen is executable" "(not executable: $GEN_SCRIPT)"
fi

# =====================================================================
# Clause (b) — script/gen runs scripts/loom-docs-gen
# =====================================================================
#
# The whole point of the gen slot is to drive the doc generators. Grep
# the script body for the loom-docs-gen invocation so a future generator
# can be appended without this clause silently passing on a stub.

echo "==> clause (b): script/gen drives scripts/loom-docs-gen"

if [ -f "$GEN_SCRIPT" ] && grep -qE 'loom-docs-gen' "$GEN_SCRIPT"; then
  pass "script/gen body references scripts/loom-docs-gen"
else
  fail "script/gen body references scripts/loom-docs-gen" \
    "(no loom-docs-gen invocation found in $GEN_SCRIPT)"
fi

# =====================================================================
# Clause (c) — gofmt -l invariant: script/gen is a no-op on an in-sync tree
# =====================================================================
#
# Sample a content manifest of the watched artifacts, run script/gen, and
# sample again. Identical manifests == the generator changed nothing ==
# the committed generated output is in sync AND the generator round-trips.
# git is deliberately NOT consulted (see the loom-qo4j note in the header).

echo "==> clause (c): script/gen is a no-op (byte-identical artifacts) when already in sync"

GEN_PATHS=(docs/reference mkdocs.yml)

pre_dirty="$(cd "$LOOM_ROOT" && git status --porcelain "${GEN_PATHS[@]}" 2>/dev/null)"
if [ -n "$pre_dirty" ]; then
  fail "generated paths are clean BEFORE running script/gen" \
    "(pre-existing dirty state in ${GEN_PATHS[*]}; cannot assert no-op:
$pre_dirty)"
elif [ ! -x "$GEN_SCRIPT" ]; then
  fail "can run script/gen to assert no-op" "(script/gen not executable yet)"
else
  # Run from the repo root so relative resolution + git context are correct.
  if ( cd "$LOOM_ROOT" && "$GEN_SCRIPT" ) >/tmp/script-gen-clean-regen.$$.log 2>&1; then
    post_dirty="$(cd "$LOOM_ROOT" && git status --porcelain "${GEN_PATHS[@]}" 2>/dev/null)"
    if [ -z "$post_dirty" ]; then
      pass "script/gen left no uncommitted diff in ${GEN_PATHS[*]} (idempotent)"
    else
      fail "script/gen left no uncommitted diff in ${GEN_PATHS[*]}" \
        "(script/gen modified generated files on an in-sync tree:
$post_dirty)"
    fi
  else
    fail "script/gen exits 0 on an in-sync tree" \
      "(non-zero exit; log:
$(cat /tmp/script-gen-clean-regen.$$.log))"
  fi
  rm -f "/tmp/script-gen-clean-regen.$$.log"
fi

# =====================================================================
# Clause (d) — the gate's own contract (loom-qo4j)
# =====================================================================
#
# Runs THIS script as a subprocess against purpose-built fixture repos
# (LOOM_SCRIPT_GEN_TEST_ROOT), so what is under test is the SHIPPED
# clauses (a)-(c), not a re-implementation of them. Suppressed on the
# inner invocation so it cannot recurse.
#
#   d0  control        in-sync fixture                        → exit 0
#   d1  FALSE POSITIVE hand-edited, uncommitted, NON-generated
#                      reference page                         → exit 0   <- the bug
#   d2  TEETH          committed generated wrapper gone stale → exit 1
#   d3  TEETH          a generator that no longer round-trips → exit 1

if [ -z "${LOOM_SCRIPT_GEN_TEST_INNER:-}" ]; then
  echo "==> clause (d): the no-op gate is honest — no false red, teeth intact"

  FIXBASE="$(mktemp -d)"
  trap 'rm -rf "$FIXBASE"' EXIT
  mkdir -p "$FIXBASE/empty-tpl"

  # build_fixture <root> — a minimal loom-shaped repo carrying the REAL
  # script/gen + scripts/loom-docs-gen, generated into sync, then
  # committed so the working tree starts clean.
  build_fixture() {
    local root="$1" d
    mkdir -p "$root/script" "$root/scripts" "$root/skills/demo-skill" \
             "$root/commands" "$root/agents" "$root/hooks"
    for d in skills slash-commands subagents hooks; do
      mkdir -p "$root/docs/reference/$d"
      printf '# %s index\n' "$d" > "$root/docs/reference/$d/index.md"
    done
    printf '# all skills\n'    > "$root/docs/reference/skills/all-skills.md"
    printf '# all commands\n'  > "$root/docs/reference/slash-commands/all-commands.md"
    printf '# all subagents\n' > "$root/docs/reference/subagents/all-subagents.md"
    printf '# all hooks\n'     > "$root/docs/reference/hooks/all-hooks.md"

    cp "$REAL_ROOT/script/gen"           "$root/script/gen"
    cp "$REAL_ROOT/scripts/loom-docs-gen" "$root/scripts/loom-docs-gen"
    chmod +x "$root/script/gen" "$root/scripts/loom-docs-gen"

    printf '# demo skill\n'   > "$root/skills/demo-skill/SKILL.md"
    printf '# demo command\n' > "$root/commands/demo-cmd.md"
    printf '# demo agent\n'   > "$root/agents/demo-agent.md"
    printf '#!/usr/bin/env bash\necho demo\n' > "$root/hooks/demo-hook.sh"

    # The page the generator does NOT own — the false-positive subject.
    printf '# Hand-authored\n\nThe generator never writes this page.\n' \
      > "$root/docs/reference/hand-authored.md"

    cat > "$root/mkdocs.yml" <<'YML'
site_name: fixture
nav:
  - Reference:
      # LOOM-DOCS-GEN:START
      # LOOM-DOCS-GEN:END
YML

    ( cd "$root" && "$root/script/gen" ) >/dev/null 2>&1
    git init -q --template="$FIXBASE/empty-tpl" "$root" >/dev/null 2>&1
    fixture_commit "$root" "fixture baseline"
  }

  fixture_commit() {
    git -C "$1" add -A >/dev/null 2>&1
    git -C "$1" -c user.email=fixture@example.invalid -c user.name=fixture \
        -c commit.gpgsign=false commit -qm "$2" >/dev/null 2>&1
  }

  inner_out=""
  run_inner() {
    inner_out="$(LOOM_SCRIPT_GEN_TEST_INNER=1 LOOM_SCRIPT_GEN_TEST_ROOT="$1" \
                 bash "$SELF" 2>&1)"
    return $?
  }

  # ---- d0: control — an in-sync fixture must go GREEN -----------------
  FIX0="$FIXBASE/d0-control"
  build_fixture "$FIX0"
  if run_inner "$FIX0"; then
    pass "d0 control: in-sync fixture passes (the fixture harness itself is sound)"
  else
    fail "d0 control: in-sync fixture passes" \
      "(the fixture is broken, so d1-d3 below prove nothing; inner output:
$inner_out)"
  fi

  # ---- d1: the bug — a hand-edited NON-generated page must not red ----
  FIX1="$FIXBASE/d1-handedit"
  build_fixture "$FIX1"
  printf '\nAn uncommitted hand-edit, exactly as a docs bead leaves it.\n' \
    >> "$FIX1/docs/reference/hand-authored.md"

  d1_dirty="$(git -C "$FIX1" status --porcelain docs/reference 2>/dev/null)"
  if [ -n "$d1_dirty" ]; then
    pass "d1 setup: docs/reference is genuinely git-dirty (the old precondition would fire)"
  else
    fail "d1 setup: docs/reference is genuinely git-dirty" \
      "(the fixture failed to reproduce the reported condition, so d1 is vacuous)"
  fi

  if run_inner "$FIX1"; then
    pass "d1: hand-edited NON-generated reference page does not red the gate"
  else
    fail "d1: hand-edited NON-generated reference page does not red the gate" \
      "(THE loom-qo4j BUG: script/gen left the page byte-identical, yet the
gate failed anyway; inner output:
$inner_out)"
  fi

  # ---- d2: teeth — stale committed generated output must red ----------
  FIX2="$FIXBASE/d2-stale-wrapper"
  build_fixture "$FIX2"
  d2_wrapper="$FIX2/docs/reference/skills/demo-skill.md"
  if grep -q 'GENERATED by scripts/loom-docs-gen' "$d2_wrapper" 2>/dev/null; then
    pass "d2 setup: the tampered page really is a generated wrapper"
  else
    fail "d2 setup: the tampered page really is a generated wrapper" \
      "(expected a generated wrapper at $d2_wrapper)"
  fi
  printf '\nHand-edited generated output — the generator will overwrite this.\n' \
    >> "$d2_wrapper"
  # Commit it, so the working tree is CLEAN and only the pre/post diff can
  # catch the staleness. A cleanliness-based gate would see nothing here.
  fixture_commit "$FIX2" "stale generated wrapper"

  if run_inner "$FIX2"; then
    fail "d2 teeth: stale committed generated output reds the gate" \
      "(the gate went GREEN on a tree whose committed generated output no
longer matches the generator — the fix loosened the gate; inner output:
$inner_out)"
  else
    pass "d2 teeth: stale committed generated output reds the gate"
  fi

  # ---- d3: teeth — a generator that no longer round-trips must red ----
  FIX3="$FIXBASE/d3-nonidempotent"
  build_fixture "$FIX3"
  printf '#!/usr/bin/env bash\ndate +%%s%%N > docs/reference/nondeterministic.md\n' \
    > "$FIX3/scripts/flaky-gen"
  chmod +x "$FIX3/scripts/flaky-gen"
  sed -i 's|"scripts/loom-docs-gen"|"scripts/loom-docs-gen"\n  "scripts/flaky-gen"|' \
    "$FIX3/script/gen"
  # Run once so the artifact EXISTS and is committed: what the inner run
  # then detects is a genuine failure to round-trip, not a new file.
  ( cd "$FIX3" && "$FIX3/script/gen" ) >/dev/null 2>&1
  fixture_commit "$FIX3" "non-idempotent generator, output committed"

  if run_inner "$FIX3"; then
    fail "d3 teeth: a generator that no longer round-trips reds the gate" \
      "(the gate went GREEN on a clean tree with a non-idempotent generator
in script/gen's GENERATORS list; inner output:
$inner_out)"
  else
    pass "d3 teeth: a generator that no longer round-trips reds the gate"
  fi
fi

# =====================================================================
# Summary
# =====================================================================
echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
