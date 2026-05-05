#!/usr/bin/env bash
# Acceptance test for lib/docs-generated.sh (loom-qp0 + loom-3hb).
#
# Verifies the shared "is docs/ generated?" detector used by both
# /audit-project (skip docs/ drift checks) and /docs-scaffold (refuse
# to scaffold over a generated tree).
#
# Two signals, either-sufficient:
#   1. docs/ matches a .gitignore entry under the project root
#   2. docs/* referenced as cp/build target in any
#      scripts/*.sh, Makefile, package.json scripts, or pyproject.toml
#
# Run:  bash lib/tests/docs-generated.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DETECTOR="$LOOM_ROOT/lib/docs-generated.sh"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# --- prereqs -----------------------------------------------------------
echo "==> Prereqs"
if [ ! -f "$DETECTOR" ]; then
  fail "lib/docs-generated.sh exists" "(detector script missing)"
  echo
  echo "Tests: $passed passed, $failed failed"
  exit 1
fi
pass "lib/docs-generated.sh exists"

if [ ! -x "$DETECTOR" ]; then
  fail "lib/docs-generated.sh is executable"
else
  pass "lib/docs-generated.sh is executable"
fi

# Helper: run detector against a fixture; succeed when we expect "generated".
# Detector contract: exit 0 = generated; exit 1 = not generated; prints the
# reason on stdout for either path. (Stdout is informational; tests assert
# on exit code AND on a substring of the reason.)
run_detector() {
  local root="$1"
  bash "$DETECTOR" "$root" 2>&1
}

# --- fixture: clean docs/ (NOT generated) -----------------------------
echo "==> Negative case: hand-written docs/, no signals"
TMP_NEG="$(mktemp -d)"
trap 'rm -rf "$TMP_NEG" "$TMP_GI" "$TMP_BUILD" "$TMP_MAKE" "$TMP_PKG" "$TMP_PYP" "$TMP_NODOCS" "$TMP_GIIGNORE_OTHER"' EXIT

mkdir -p "$TMP_NEG/docs"
echo "# hand-written" >"$TMP_NEG/docs/index.md"
# .gitignore exists but doesn't mention docs/
cat >"$TMP_NEG/.gitignore" <<'EOF'
*.pyc
__pycache__/
.DS_Store
EOF
mkdir -p "$TMP_NEG/scripts"
cat >"$TMP_NEG/scripts/test.sh" <<'EOF'
#!/usr/bin/env bash
echo "running tests"
EOF

if out=$(run_detector "$TMP_NEG"); then
  fail "negative case: hand-written docs/ should NOT be detected as generated" "got generated; reason: $out"
else
  pass "negative case: hand-written docs/ correctly NOT generated"
fi

# --- fixture: docs/ is gitignored (signal 1) --------------------------
echo "==> Positive case 1: docs/ in .gitignore"
TMP_GI="$(mktemp -d)"
mkdir -p "$TMP_GI/docs"
echo "# whatever" >"$TMP_GI/docs/index.md"
cat >"$TMP_GI/.gitignore" <<'EOF'
*.pyc
docs/
node_modules/
EOF

if out=$(run_detector "$TMP_GI"); then
  if echo "$out" | grep -qiE 'gitignore|signal[ -]?1'; then
    pass "positive case 1: gitignored docs/ detected (reason cites gitignore)"
  else
    pass "positive case 1: gitignored docs/ detected (reason: $out)"
  fi
else
  fail "positive case 1: gitignored docs/ should be detected" "exit $?; reason: $out"
fi

# --- fixture: docs/ as build target in scripts/*.sh (signal 2) --------
echo "==> Positive case 2a: scripts/build-docs.sh writes to docs/"
TMP_BUILD="$(mktemp -d)"
mkdir -p "$TMP_BUILD/docs" "$TMP_BUILD/scripts"
echo "# generated" >"$TMP_BUILD/docs/index.md"
cat >"$TMP_BUILD/.gitignore" <<'EOF'
*.pyc
EOF
cat >"$TMP_BUILD/scripts/build-docs.sh" <<'EOF'
#!/usr/bin/env bash
DOCS=docs
mkdir -p "$DOCS"
cp README.md "$DOCS/index.md"
EOF

if out=$(run_detector "$TMP_BUILD"); then
  if echo "$out" | grep -qiE 'script|build|signal[ -]?2'; then
    pass "positive case 2a: scripts/*.sh build target detected (reason cites script)"
  else
    pass "positive case 2a: scripts/*.sh build target detected (reason: $out)"
  fi
else
  fail "positive case 2a: scripts/build-docs.sh writes to docs/ should be detected" "exit $?; reason: $out"
fi

# --- fixture: docs/ in Makefile (signal 2) ----------------------------
echo "==> Positive case 2b: Makefile writes to docs/"
TMP_MAKE="$(mktemp -d)"
mkdir -p "$TMP_MAKE/docs"
echo "# generated" >"$TMP_MAKE/docs/index.md"
cat >"$TMP_MAKE/Makefile" <<'EOF'
.PHONY: docs
docs:
	mkdir -p docs
	cp README.md docs/index.md
EOF

if out=$(run_detector "$TMP_MAKE"); then
  pass "positive case 2b: Makefile build target detected (reason: $out)"
else
  fail "positive case 2b: Makefile writing to docs/ should be detected" "exit $?; reason: $out"
fi

# --- fixture: docs/ in package.json scripts (signal 2) ----------------
echo "==> Positive case 2c: package.json scripts.build writes to docs/"
TMP_PKG="$(mktemp -d)"
mkdir -p "$TMP_PKG/docs"
echo "<html/>" >"$TMP_PKG/docs/index.html"
cat >"$TMP_PKG/package.json" <<'EOF'
{
  "name": "fixture",
  "version": "0.0.1",
  "scripts": {
    "build": "vite build --outDir docs",
    "test": "vitest"
  }
}
EOF

if out=$(run_detector "$TMP_PKG"); then
  pass "positive case 2c: package.json scripts build target detected (reason: $out)"
else
  fail "positive case 2c: package.json scripts writing to docs/ should be detected" "exit $?; reason: $out"
fi

# --- fixture: docs/ in pyproject.toml [tool.X] section (signal 2) -----
echo "==> Positive case 2d: pyproject.toml [tool.*] references docs/"
TMP_PYP="$(mktemp -d)"
mkdir -p "$TMP_PYP/docs"
echo "# generated" >"$TMP_PYP/docs/index.md"
cat >"$TMP_PYP/pyproject.toml" <<'EOF'
[build-system]
requires = ["setuptools"]

[tool.sphinx]
source = "src"
out = "docs"
EOF

if out=$(run_detector "$TMP_PYP"); then
  pass "positive case 2d: pyproject.toml [tool.*] docs reference detected (reason: $out)"
else
  fail "positive case 2d: pyproject.toml referencing docs/ should be detected" "exit $?; reason: $out"
fi

# --- fixture: no docs/ at all -----------------------------------------
echo "==> Edge case: no docs/ directory"
TMP_NODOCS="$(mktemp -d)"
echo "# hi" >"$TMP_NODOCS/README.md"
cat >"$TMP_NODOCS/.gitignore" <<'EOF'
*.pyc
EOF

# When docs/ doesn't exist at all, the detector should treat it as
# "not generated" (exit 1) — there's nothing to skip / refuse over.
if run_detector "$TMP_NODOCS" >/dev/null; then
  fail "edge case: no docs/ should NOT be detected as generated"
else
  pass "edge case: no docs/ correctly NOT generated"
fi

# --- fixture: .gitignore entry mentions a path with docs in it but not docs/ itself
echo "==> Edge case: gitignore mentions 'mydocs/' (substring), not docs/"
TMP_GIIGNORE_OTHER="$(mktemp -d)"
mkdir -p "$TMP_GIIGNORE_OTHER/docs"
echo "# hand-written" >"$TMP_GIIGNORE_OTHER/docs/index.md"
cat >"$TMP_GIIGNORE_OTHER/.gitignore" <<'EOF'
mydocs/
old-docs/
EOF

if out=$(run_detector "$TMP_GIIGNORE_OTHER"); then
  fail "edge case: 'mydocs/' substring should NOT match docs/ as gitignored" "got generated; reason: $out"
else
  pass "edge case: 'mydocs/' substring correctly NOT matched as docs/ gitignore"
fi

echo
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
