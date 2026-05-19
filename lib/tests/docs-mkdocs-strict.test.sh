#!/usr/bin/env bash
# Regression test for the recurring "broken-link-in-docs" bug class.
#
# Symptom: a markdown link in docs/ points at a target outside the
# docs tree (or at a stale filename). mkdocs --strict promotes the
# warning to an error and Deploy docs CI goes red.
#
# Family lineage:
#   - loom-59w (2026-05-15): bd-remember-guest-guard.md → loom-guest.md
#     (stale filename, target file existed under different name)
#   - loom-tx7 (2026-05-19, this bead): edit-after-failure-guard.md
#     → ../../../skills/bead-lifecycle-shell/SKILL.md (target outside
#     docs/ tree, mkdocs can't resolve)
#
# This test runs `mkdocs build --strict` and asserts rc=0. Any future
# instance of the family fails this test before reaching CI.
#
# Run:  bash lib/tests/docs-mkdocs-strict.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

passed=0
failed=0

if ! command -v mkdocs >/dev/null 2>&1; then
  echo "SKIP: mkdocs not installed (install via 'pip install -r requirements.txt')"
  exit 0
fi

cd "$LOOM_ROOT"

build_output=$(mkdocs build --strict 2>&1)
rc=$?

if [ "$rc" -eq 0 ]; then
  echo "  PASS: mkdocs build --strict exits 0"
  passed=$((passed + 1))
else
  echo "  FAIL: mkdocs build --strict exited $rc"
  echo "$build_output" | grep -E 'WARNING|ERROR|Aborted' | sed 's/^/    /'
  failed=$((failed + 1))
fi

# Instance assertion for loom-tx7 specifically: the link in
# edit-after-failure-guard.md must NOT point at a path outside docs/.
target_file="docs/reference/hooks/edit-after-failure-guard.md"
if grep -q '\.\./\.\./\.\./skills/' "$target_file"; then
  echo "  FAIL: $target_file still contains \"../../../skills/\" link (out-of-docs target)"
  failed=$((failed + 1))
else
  echo "  PASS: $target_file has no out-of-docs \"../../../skills/\" link"
  passed=$((passed + 1))
fi

echo ""
echo "Results: $passed passed, $failed failed"

[ "$failed" -eq 0 ]
