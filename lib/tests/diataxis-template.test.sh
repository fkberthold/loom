#!/usr/bin/env bash
# Acceptance test for templates/diataxis/ (loom-km8.1).
#
# Verifies the canonical Diataxis skeleton:
#   1. Substituting {{ project_name }}/{{ repo_url }}/{{ short_description }}
#      into a copy of templates/diataxis/ and renaming *.template -> *
#      produces a buildable MkDocs site.
#   2. `mkdocs build --strict` succeeds against that populated copy.
#   3. The four quadrant index.md files (tutorials/how-to/reference/explanation)
#      contain non-empty Diataxis-discipline orientation copy (>= 400 chars
#      each — guards against empty stubs per R1 F3).
#   4. No stray `{{ ... }}` placeholders survive the substitution.
#
# Run:  bash lib/tests/diataxis-template.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMPLATE_DIR="$LOOM_ROOT/templates/diataxis"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# --- prereqs -----------------------------------------------------------
echo "==> Prereqs"
if ! command -v mkdocs >/dev/null 2>&1; then
  fail "mkdocs available on PATH" "(install requirements first: pip install -r $TEMPLATE_DIR/requirements.txt)"
  echo
  echo "Tests: $passed passed, $failed failed"
  exit 1
fi
pass "mkdocs available"

if [ ! -d "$TEMPLATE_DIR" ]; then
  fail "templates/diataxis/ exists" "(directory missing — bead has not landed)"
  echo
  echo "Tests: $passed passed, $failed failed"
  exit 1
fi
pass "templates/diataxis/ exists"

# --- populate a tmp copy -----------------------------------------------
echo "==> Populate"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cp -r "$TEMPLATE_DIR/." "$TMP/"

PROJECT_NAME="acme-widgets"
REPO_URL="https://github.com/acme/widgets"
SHORT_DESCRIPTION="Widget orchestration for the Acme platform."

# substitute placeholders in every regular file
while IFS= read -r -d '' f; do
  sed -i \
    -e "s|{{ project_name }}|$PROJECT_NAME|g" \
    -e "s|{{ repo_url }}|$REPO_URL|g" \
    -e "s|{{ short_description }}|$SHORT_DESCRIPTION|g" \
    "$f"
done < <(find "$TMP" -type f -print0)

# rename *.template -> *
while IFS= read -r -d '' f; do
  mv "$f" "${f%.template}"
done < <(find "$TMP" -type f -name '*.template' -print0)

# Stub primitive dirs so include-markdown globs match. A real
# loom-managed project would have these populated; for the build
# test we just need at least one match per glob so --strict doesn't
# fail on "No files found including".
mkdir -p "$TMP/skills/example" "$TMP/commands" "$TMP/agents" "$TMP/hooks"
cat >"$TMP/skills/example/SKILL.md" <<'EOF'
---
name: example
description: Stub skill for the build test.
---

# example skill

Stub content used only by the diataxis-template build test.
EOF
cat >"$TMP/commands/example.md" <<'EOF'
# /example command

Stub command used only by the diataxis-template build test.
EOF
cat >"$TMP/agents/example.md" <<'EOF'
# example agent

Stub agent used only by the diataxis-template build test.
EOF
cat >"$TMP/hooks/example.sh" <<'EOF'
#!/usr/bin/env bash
# Stub hook used only by the diataxis-template build test.
exit 0
EOF

pass "substitution + rename + primitive-stubs completed"

# --- assertions --------------------------------------------------------
echo "==> Quadrant orientation copy"
for q in tutorials how-to reference explanation; do
  idx="$TMP/docs/$q/index.md"
  if [ ! -f "$idx" ]; then
    fail "$q/index.md exists"
    continue
  fi
  bytes=$(wc -c <"$idx")
  if [ "$bytes" -ge 400 ]; then
    pass "$q/index.md non-empty ($bytes bytes)"
  else
    fail "$q/index.md non-empty (only $bytes bytes; >= 400 required)"
  fi
done

echo "==> No surviving placeholders for the three known tokens"
# Only flag the three tokens substitution is responsible for. GHA's
# `${{ github.ref }}` syntax and any literal `{{ token }}` examples in
# the substitution-mechanism README are out of scope.
stray=$(grep -rEl '\{\{ (project_name|repo_url|short_description) \}\}' "$TMP" 2>/dev/null || true)
if [ -z "$stray" ]; then
  pass "no surviving project_name/repo_url/short_description placeholders"
else
  fail "no surviving project_name/repo_url/short_description placeholders" "$stray"
fi

echo "==> mkdocs build --strict"
build_log=$(cd "$TMP" && mkdocs build --strict --site-dir "$TMP/_build" 2>&1)
if [ $? -eq 0 ]; then
  pass "mkdocs build --strict succeeded"
else
  fail "mkdocs build --strict succeeded" "$build_log"
fi

echo
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
