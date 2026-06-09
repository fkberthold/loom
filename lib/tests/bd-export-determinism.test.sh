#!/usr/bin/env bash
# Real-bd integration test for lib/bd-canonical-export.sh — the single
# chokepoint every loom bd-export call site routes through (post-rewrite,
# bd-merge-driver). Complements bd-canonical-export.test.sh (which uses a
# stub); this one exercises the ACTUALLY-INSTALLED bd binary.
#
# loom-hsm7: upgrading the controlled bd v1.0.2 -> v1.0.4 surfaced TWO
# behavior changes the canonicalizer must absorb:
#   1. determinism: v1.0.2's `bd export` reorders `_type:memory` rows
#      per-process (Go map iteration); v1.0.4 sorts memory keys natively
#      (beads #3474 / #4086).
#   2. memory inclusion: v1.0.4 EXCLUDES memories from `bd export` by
#      default ("may contain sensitive agent context") — they need
#      `--include-memories`. v1.0.2 has NO such flag and includes them
#      by default. loom commits memories INTO .beads/issues.jsonl, so a
#      canonicalizer that runs a bare `bd export` on v1.0.4 silently
#      STRIPS every memory row -> data loss on the next auto-export.
#
# INVARIANTS under test (version-agnostic — the canonicalizer adapts):
#   A. canonical export is byte-stable across repeated runs.
#   B. memory RETENTION: if .beads/issues.jsonl commits >=1 memory row,
#      the canonical export must also contain >=1 memory row (i.e. the
#      canonicalizer never silently drops memories on any supported bd).
#
# Run:  bash lib/tests/bd-export-determinism.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CANON="$LOOM_ROOT/lib/bd-canonical-export.sh"
BD_BIN="${BD_BIN:-bd}"
RUNS="${LOOM_BD_DETERMINISM_RUNS:-5}"
MEM_RE='"_type":"memory"'

passed=0; failed=0; skipped=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }
skip() { echo "  SKIP: $1"; skipped=$((skipped + 1)); }

cd "$LOOM_ROOT"

if ! command -v "$BD_BIN" >/dev/null 2>&1 || [ ! -x "$CANON" ]; then
  skip "bd not on PATH or canonicalizer missing — integration test not applicable"
  echo "determinism: 0/0 passed, ${skipped} skipped"; exit 0
fi

bd_ver="$("$BD_BIN" version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"

# --- A. byte-stability of the canonical export ------------------------------
first="$(BD_BIN="$BD_BIN" "$CANON" 2>/dev/null)"
stable=1; diffout=""
for _ in $(seq 2 "$RUNS"); do
  next="$(BD_BIN="$BD_BIN" "$CANON" 2>/dev/null)"
  if [ "$next" != "$first" ]; then
    stable=0; diffout="$(diff <(printf '%s' "$first") <(printf '%s' "$next") | head -8)"; break
  fi
done
if [ "$stable" = "1" ]; then
  pass "canonical export byte-stable across ${RUNS} runs (bd ${bd_ver:-unknown})"
else
  fail "canonical export NOT byte-stable across ${RUNS} runs (bd ${bd_ver:-unknown})" "$diffout"
fi

# --- B. memory retention ----------------------------------------------------
committed_mem="$(grep -c "$MEM_RE" "$LOOM_ROOT/.beads/issues.jsonl" 2>/dev/null || echo 0)"
canon_mem="$(printf '%s' "$first" | grep -c "$MEM_RE" || true)"
if [ "$committed_mem" -lt 1 ]; then
  skip "no memory rows committed in issues.jsonl — retention not exercisable here"
elif [ "$canon_mem" -ge 1 ]; then
  pass "canonical export retains memory rows (${canon_mem} present; ${committed_mem} committed) on bd ${bd_ver:-unknown}"
else
  fail "canonical export DROPPED all memory rows (${committed_mem} committed, 0 in canonical) on bd ${bd_ver:-unknown} — v1.0.4 excludes memories without --include-memories"
fi

echo "determinism: ${passed}/$((passed + failed)) passed, ${skipped} skipped"
[ "$failed" -eq 0 ]
