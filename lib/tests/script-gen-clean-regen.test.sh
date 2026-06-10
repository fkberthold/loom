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
# uncommitted diff when the tree is already in sync; on a stale tree it
# regenerates the drift away. We test the in-sync no-op half directly here:
# the repo ships in-sync (loom-itph just regenerated it), so a CORRECT
# script/gen run must leave docs/reference + mkdocs.yml byte-identical.
#
# This mirrors the pass/fail harness of lib/tests/audit-script-convention.sh:
# a pass()/fail() counter pair, assertions against the real repo tree, and a
# summary line that exits non-zero on any failure.
#
# Run:  bash lib/tests/script-gen-clean-regen.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
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
# The repo ships in sync (loom-itph regenerated docs/reference + mkdocs.yml).
# A correct script/gen must therefore leave those paths with NO new/modified
# files: running it and then checking `git status --porcelain` over the
# generated paths must come back EMPTY. This is the gofmt -l shape — the
# generator is idempotent on an already-generated tree.
#
# Guard: if the tree is ALREADY dirty in the generated paths before we run
# (pre-existing uncommitted edits unrelated to this test), we cannot make a
# clean before/after claim — fail loud rather than false-green.

echo "==> clause (c): script/gen is a no-op (clean tree) when already in sync"

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
# Summary
# =====================================================================
echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
