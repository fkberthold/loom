#!/usr/bin/env bash
# Regression test for loom-ad1.
#
# Symptom (surfaced 2026-05-24 by mforth, a downstream loom-managed
# project): `/docs-scaffold` produces a Diataxis landing page that
# renders Material icon shortcodes (`:material-school:{ .lg .middle }`,
# `:octicons-arrow-right-24:`, ...) as literal text instead of SVG
# icons in the built site.
#
# ROOT CAUSE: templates/diataxis/mkdocs.yml.template's
# `markdown_extensions` block omitted `pymdownx.emoji`. Material's
# icon-shortcode resolver hangs off that extension + Material's
# twemoji index. Without it, the shortcodes pass through as text.
#
# This test pins two contracts at the template level (cheap, no
# mkdocs runtime needed):
#   1. mkdocs.yml.template declares `pymdownx.emoji` under
#      `markdown_extensions`.
#   2. The emoji block configures `emoji_index` + `emoji_generator`
#      pointed at mkdocs-material 9.x's
#      `material.extensions.emoji.twemoji` / `.to_svg`.
#
# The full build-time render is already covered by
# diataxis-template.test.sh (it runs `mkdocs build --strict`); this
# fixture is a faster, more diagnostic regression guard that names
# the exact missing extension if it gets dropped again.
#
# Run:  bash lib/tests/diataxis-template-pymdownx-emoji.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMPLATE="$LOOM_ROOT/templates/diataxis/mkdocs.yml.template"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

if [ ! -f "$TEMPLATE" ]; then
  fail "templates/diataxis/mkdocs.yml.template exists"
  echo
  echo "Tests: $passed passed, $failed failed"
  exit 1
fi
pass "template file present"

# 1. pymdownx.emoji is declared.
if grep -qE '^[[:space:]]*-[[:space:]]+pymdownx\.emoji:?[[:space:]]*$' "$TEMPLATE"; then
  pass "pymdownx.emoji listed in markdown_extensions"
else
  fail "pymdownx.emoji listed in markdown_extensions" \
    "(add it after pymdownx.details — see loom-ad1)"
fi

# 2. emoji_index uses mkdocs-material 9.x namespace.
if grep -q 'emoji_index: !!python/name:material\.extensions\.emoji\.twemoji' "$TEMPLATE"; then
  pass "emoji_index points at material.extensions.emoji.twemoji"
else
  fail "emoji_index points at material.extensions.emoji.twemoji" \
    "(pre-9 'materialx.emoji' is wrong for current mkdocs-material pin)"
fi

# 3. emoji_generator emits SVG.
if grep -q 'emoji_generator: !!python/name:material\.extensions\.emoji\.to_svg' "$TEMPLATE"; then
  pass "emoji_generator points at material.extensions.emoji.to_svg"
else
  fail "emoji_generator points at material.extensions.emoji.to_svg"
fi

echo
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
