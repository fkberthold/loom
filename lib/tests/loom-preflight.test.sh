#!/usr/bin/env bash
# Fixture tests for scripts/loom-preflight (loom-ohjf, supersedes loom-2wms).
#
# WHY: `bd preflight` prints a HARDCODED Go-project PR checklist
# (go test -tags / golangci-lint / gofmt / vendorHash / version.go) for
# ANY project, regardless of runtime — wrong for bash/python/ts/etc.
# loom-preflight renders THAT project's real checklist from its
# .claude/project-constitution.md canonical_commands instead.
#
# Run:  bash lib/tests/loom-preflight.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PREFLIGHT="$LOOM_ROOT/scripts/loom-preflight"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# A fixture project carrying a constitution with the given runtime + cmds.
mk_constitution_project() { # <runtime> <test> <lint> [build] [gen]
  local runtime="$1" t="$2" l="$3" b="${4:-}" g="${5:-}" d
  d=$(mktemp -d)
  mkdir -p "$d/.claude"
  cat > "$d/.claude/project-constitution.md" <<EOF
---
package_manager: pip
language:
  runtime: $runtime
  version: ""
canonical_commands:
  build: "$b"
  test: "$t"
  lint: "$l"
  gen: "$g"
  deploy: ""
---

# prose body (ignored by the parser)
EOF
  echo "$d"
}

# =====================================================================
# 1. PER-RUNTIME — a Python project's checklist shows ITS commands, NOT
#    bd's Go template.
# =====================================================================
echo "==> 1. Python project → constitution commands, not the Go template"
PROJ=$(mk_constitution_project python "pytest -q" "ruff check .")
out=$(bash "$PREFLIGHT" --root "$PROJ" 2>&1); rc=$?

if [ "$rc" -eq 0 ]; then pass "exit 0"; else fail "non-zero exit (rc=$rc)" "$out"; fi

if printf '%s' "$out" | grep -qF 'pytest -q'; then
  pass "renders the constitution test command (pytest -q)"
else
  fail "missing constitution test command" "$out"
fi
if printf '%s' "$out" | grep -qF 'ruff check .'; then
  pass "renders the constitution lint command (ruff check .)"
else
  fail "missing constitution lint command" "$out"
fi
# Must NOT leak bd's hardcoded Go template.
if printf '%s' "$out" | grep -qiE 'golangci-lint|gofmt|go test|vendorHash|version\.go'; then
  fail "leaked bd's Go-project template into a Python project" "$out"
else
  pass "no bd Go-template leakage"
fi
# Header names the project runtime (so the checklist is self-describing).
if printf '%s' "$out" | grep -qiF 'python'; then
  pass "header names the project runtime (python)"
else
  fail "header does not name the runtime" "$out"
fi

# =====================================================================
# 2. EMPTY commands are omitted (build/gen empty for this project).
# =====================================================================
echo "==> 2. Empty canonical commands are omitted from the checklist"
if printf '%s' "$out" | grep -qiE '^\[ \] Build:|^\[ \] Generated'; then
  fail "rendered a checklist line for an empty command" "$out"
else
  pass "empty build/gen commands omitted"
fi
# A project WITH a build command renders it.
PROJ2=$(mk_constitution_project go "go test ./..." "golangci-lint run" "go build ./...")
out2=$(bash "$PREFLIGHT" --root "$PROJ2" 2>&1)
if printf '%s' "$out2" | grep -qF 'go build ./...'; then
  pass "non-empty build command IS rendered"
else
  fail "non-empty build command missing" "$out2"
fi

# =====================================================================
# 3. LOOM's own constitution → shell suite + shellcheck (the 2wms case).
# =====================================================================
echo "==> 3. loom's own project → script/test + shellcheck"
outl=$(bash "$PREFLIGHT" --root "$LOOM_ROOT" 2>&1)
if printf '%s' "$outl" | grep -qF 'script/test'; then
  pass "loom case renders script/test"
else
  fail "loom case missing script/test" "$outl"
fi
if printf '%s' "$outl" | grep -qF 'shellcheck'; then
  pass "loom case renders shellcheck lint"
else
  fail "loom case missing shellcheck" "$outl"
fi

# =====================================================================
# 4. NO constitution → graceful fallback (nudge + exit 0), no Go template.
# =====================================================================
echo "==> 4. No constitution → graceful /audit-project nudge, exit 0"
EMPTY=$(mktemp -d)
outn=$(bash "$PREFLIGHT" --root "$EMPTY" 2>&1); rcn=$?
if [ "$rcn" -eq 0 ]; then pass "no-constitution exits 0"; else fail "no-constitution non-zero (rc=$rcn)" "$outn"; fi
if printf '%s' "$outn" | grep -qiE 'audit-project|no .*constitution'; then
  pass "no-constitution nudges toward /audit-project"
else
  fail "no-constitution gave no nudge" "$outn"
fi
if printf '%s' "$outn" | grep -qiE 'golangci-lint|gofmt|go test'; then
  fail "no-constitution leaked Go template" "$outn"
else
  pass "no-constitution: no Go-template leakage"
fi

# =====================================================================
# 5. Universal line — beads pollution check is always present.
# =====================================================================
echo "==> 5. Universal beads-pollution line present"
if printf '%s' "$out" | grep -qiF 'beads'; then
  pass "beads-pollution checklist line present"
else
  fail "missing universal beads-pollution line" "$out"
fi

echo
echo "loom-preflight: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
exit 0
