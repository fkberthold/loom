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

# Regression guard (loom-tww, 2026-05-26): the four quadrant
# landing pages historically shipped a `## Discipline` h2 section
# that read awkwardly to end-users — it describes Diataxis
# discipline RULES for *contributors*, not content for site
# visitors. Downstream project mforth deleted them (commit 419554b);
# this fixture pins the contract upstream so the sections cannot
# silently return via template edits.
echo "==> No contributor-facing '## Discipline' sections in quadrant indexes (loom-tww)"
for q in tutorials how-to reference explanation; do
  idx="$TMP/docs/$q/index.md"
  if grep -q '^## Discipline' "$idx" 2>/dev/null; then
    fail "$q/index.md has no '## Discipline' h2"
  else
    pass "$q/index.md has no '## Discipline' h2"
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

# --- GH Pages source-of-truth alignment (loom-z3m.13) -------------------
# Regression guard: skills/docs-scaffold/SKILL.md tells the user how to
# configure GitHub Pages in the repo's web UI. That guidance MUST match
# the shape of the scaffolded workflow. The scaffolded workflow runs
# `mkdocs gh-deploy --force` (push to a gh-pages branch), so the
# SKILL.md next-steps text must point users at "Deploy from a branch:
# gh-pages" — NOT "Source = GitHub Actions" (which only works for the
# actions/deploy-pages flow and silently fails against gh-deploy).
#
# Surfaced 2026-05-10 (loom f5), fixed for SKILL.md in dbb068b
# (loom-no3); this fixture pins the contract so the two surfaces can't
# drift again. Pre-existing on disk; restored from git after this test
# is staged.
echo "==> GH Pages source guidance matches workflow shape (loom-z3m.13)"
SKILL_FILE="$LOOM_ROOT/skills/docs-scaffold/SKILL.md"
WORKFLOW_FILE="$TEMPLATE_DIR/.github/workflows/docs.yml"

if [ ! -f "$SKILL_FILE" ]; then
  fail "skills/docs-scaffold/SKILL.md exists"
elif [ ! -f "$WORKFLOW_FILE" ]; then
  fail "templates/diataxis/.github/workflows/docs.yml exists"
else
  pass "both surfaces present"

  # The scaffolded workflow uses `mkdocs gh-deploy` (push-to-branch
  # publish mode). If this premise ever flips (e.g. switch to
  # actions/deploy-pages), the regression-guard premise inverts too
  # and this fixture must be rewritten.
  if grep -q 'mkdocs gh-deploy' "$WORKFLOW_FILE"; then
    pass "workflow uses 'mkdocs gh-deploy' (push-to-gh-pages-branch)"

    # SKILL.md must reference the gh-pages branch publish source.
    if grep -q 'gh-pages' "$SKILL_FILE"; then
      pass "SKILL.md references 'gh-pages' branch"
    else
      fail "SKILL.md references 'gh-pages' branch" \
        "(workflow pushes to gh-pages but SKILL.md does not mention it)"
    fi

    # SKILL.md must NOT tell users to pick "Source = GitHub Actions" —
    # that's the wrong setting for the gh-deploy push-to-branch flow.
    if grep -qE 'Source[[:space:]]*=[[:space:]]*"?GitHub Actions"?' "$SKILL_FILE"; then
      fail "SKILL.md does not tell user 'Source = GitHub Actions'" \
        "(workflow uses gh-deploy → push to branch, not actions/deploy-pages)"
    else
      pass "SKILL.md does not tell user 'Source = GitHub Actions'"
    fi
  else
    # Premise inverted — workflow no longer uses gh-deploy. This guard
    # would need to be rewritten for the new publish mode.
    fail "workflow uses 'mkdocs gh-deploy'" \
      "(if the workflow switched publish modes, rewrite this fixture)"
  fi
fi

echo
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
