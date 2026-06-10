#!/usr/bin/env bash
# Behavior + registration tests for scripts/loom-docs-catalogue (loom-wjuo).
#
# THE BUG: loom's docs/reference/<category>/index.md inventory TABLES are
# hand-maintained while the shipped primitives (skills/*/SKILL.md,
# commands/*.md, agents/*.md, hooks/*.sh) grow on disk. The verbatim
# `all-<category>.md` dump pages are mkdocs include-globs so they stay
# complete by construction — but the hand-authored index TABLES drift.
# At loom-wjuo filing, 9 shipped primitives were missing from their index
# table and 2 hook rows were duplicated. This is the SAME bug class
# loom-9z1.9 `/audit-project --check=docs` Check 4 ("inclusion-glob
# symmetric coverage") was built to detect — but that check is naive-grep,
# user-initiated only, and not a gate, so the drift recurred. This script
# is the mechanized, gateable engine for that check.
#
# THE CONTRACT (the RED: line on loom-wjuo):
#   INVARIANT: `scripts/loom-docs-catalogue --check` exits non-zero when a
#   shipped primitive is ABSENT FROM — or DUPLICATED IN — its
#   docs/reference/<category>/index.md inventory table; exits zero when
#   every shipped primitive appears exactly once across all four
#   categories.
#
# The four categories and their (shipped glob -> index table) mapping:
#   skills     skills/*/SKILL.md  -> docs/reference/skills/index.md
#   commands   commands/*.md      -> docs/reference/slash-commands/index.md
#   subagents  agents/*.md        -> docs/reference/subagents/index.md
#   hooks      hooks/*.sh         -> docs/reference/hooks/index.md
#
# The script roots itself at the repo (resolved from BASH_SOURCE) but
# honors LOOM_DOCS_ROOT to point at a fixture tree — the same override
# shape script/test uses with LOOM_TEST_DIR. Only the FIRST cell of each
# markdown table row counts as a "listed" name; the verbatim all-*.md
# dumps are NOT inspected (they auto-propagate via include-glob).
#
# Run:  bash lib/tests/loom-docs-catalogue.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$LOOM_ROOT/scripts/loom-docs-catalogue"
PREPUSH="$LOOM_ROOT/hooks/pre-push-mkdocs-strict.sh"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# ---------------------------------------------------------------------
# Fixture builder: a minimal but STRUCTURALLY FAITHFUL loom tree under
# $1, with all four categories. Each category ships two primitives and
# (by default) lists each exactly once in its index table — so a freshly
# built fixture is CLEAN. Individual tests then mutate one table to
# inject a specific drift and assert the script catches it.
#
# The index tables reproduce the real format quirks the extractor must
# survive: a leading "| Field | Value |" metadata table whose first
# column ("Source glob") must NOT be mistaken for a primitive, and the
# command table's `/name [args]` first-cell form.
# ---------------------------------------------------------------------
build_fixture() {
  local root="$1"
  mkdir -p "$root/skills/alpha-skill" "$root/skills/beta-skill" \
           "$root/commands" "$root/agents" "$root/hooks" \
           "$root/docs/reference/skills" \
           "$root/docs/reference/slash-commands" \
           "$root/docs/reference/subagents" \
           "$root/docs/reference/hooks"

  printf '# alpha-skill\n' >"$root/skills/alpha-skill/SKILL.md"
  printf '# beta-skill\n'  >"$root/skills/beta-skill/SKILL.md"
  printf '# gamma\n' >"$root/commands/gamma.md"
  printf '# delta\n' >"$root/commands/delta.md"
  printf '# epsilon-agent\n' >"$root/agents/epsilon-agent.md"
  printf '# zeta-agent\n'    >"$root/agents/zeta-agent.md"
  printf '#!/usr/bin/env bash\n' >"$root/hooks/eta-hook.sh"
  printf '#!/usr/bin/env bash\n' >"$root/hooks/theta-hook.sh"

  # skills index — metadata table THEN inventory table (real shape).
  cat >"$root/docs/reference/skills/index.md" <<'EOF'
# Skills

| Field | Value |
|---|---|
| Source glob | `skills/*/SKILL.md` |
| Catalogue page | [all-skills.md](all-skills.md) |

## Invocation

| Skill | Invocation |
|---|---|
| `alpha-skill` | `/alpha-skill` |
| `beta-skill` | `/beta-skill` |
EOF

  # commands index — first-cell carries leading slash + args.
  cat >"$root/docs/reference/slash-commands/index.md" <<'EOF'
# Slash commands

| Command | Trigger |
|---|---|
| `/gamma [id]` | User-typed |
| `/delta` | User-typed |
EOF

  cat >"$root/docs/reference/subagents/index.md" <<'EOF'
# Subagents

| Subagent | Dispatched by |
|---|---|
| `epsilon-agent` | hook |
| `zeta-agent` | hook |
EOF

  # hooks index — first-cell carries the `.sh` extension.
  cat >"$root/docs/reference/hooks/index.md" <<'EOF'
# Hooks

| Hook | Event |
|---|---|
| `eta-hook.sh` | PreToolUse |
| `theta-hook.sh` | PreToolUse |
EOF
}

# =====================================================================
# Behavior clause 1 — a complete, dup-free tree exits 0
# =====================================================================
echo "==> clause 1: clean fixture (every primitive listed exactly once) -> exit 0"

if [ ! -x "$SCRIPT" ]; then
  fail "scripts/loom-docs-catalogue exists and is executable" \
    "(missing or non-executable: $SCRIPT — RED until the script is written)"
fi

TMP_CLEAN="$(mktemp -d)"
TMP_MISS="$(mktemp -d)"
TMP_DUP="$(mktemp -d)"
TMP_EXTRA="$(mktemp -d)"
trap 'rm -rf "$TMP_CLEAN" "$TMP_MISS" "$TMP_DUP" "$TMP_EXTRA"' EXIT

build_fixture "$TMP_CLEAN"
if LOOM_DOCS_ROOT="$TMP_CLEAN" "$SCRIPT" --check >/tmp/loom_cat_clean.out 2>&1; then
  pass "clean fixture -> exit 0"
else
  fail "clean fixture -> expected exit 0, got $?" "$(cat /tmp/loom_cat_clean.out)"
fi

# =====================================================================
# Behavior clause 2 — a primitive shipped but absent from its table
# =====================================================================
echo "==> clause 2: shipped-but-unlisted primitive -> exit 1 + names it"

build_fixture "$TMP_MISS"
# Ship a third skill on disk, but DON'T add it to the index table.
mkdir -p "$TMP_MISS/skills/omega-skill"
printf '# omega-skill\n' >"$TMP_MISS/skills/omega-skill/SKILL.md"

if LOOM_DOCS_ROOT="$TMP_MISS" "$SCRIPT" --check >/tmp/loom_cat_miss.out 2>&1; then
  fail "missing-from-table -> expected exit 1, got 0" "$(cat /tmp/loom_cat_miss.out)"
else
  pass "missing-from-table -> non-zero exit"
fi
if grep -q 'omega-skill' /tmp/loom_cat_miss.out; then
  pass "missing-from-table -> report names the missing primitive (omega-skill)"
else
  fail "missing-from-table -> report should name omega-skill" "$(cat /tmp/loom_cat_miss.out)"
fi
if grep -iq 'skill' /tmp/loom_cat_miss.out; then
  pass "missing-from-table -> report names the category (skills)"
else
  fail "missing-from-table -> report should name the skills category" "$(cat /tmp/loom_cat_miss.out)"
fi

# =====================================================================
# Behavior clause 3 — a primitive listed in TWO table rows (dup)
# =====================================================================
echo "==> clause 3: duplicated table row -> exit 1 + names it"

build_fixture "$TMP_DUP"
# Duplicate the eta-hook row in the hooks index table.
printf '| `eta-hook.sh` | PreToolUse |\n' >>"$TMP_DUP/docs/reference/hooks/index.md"

if LOOM_DOCS_ROOT="$TMP_DUP" "$SCRIPT" --check >/tmp/loom_cat_dup.out 2>&1; then
  fail "duplicated-row -> expected exit 1, got 0" "$(cat /tmp/loom_cat_dup.out)"
else
  pass "duplicated-row -> non-zero exit"
fi
if grep -q 'eta-hook' /tmp/loom_cat_dup.out; then
  pass "duplicated-row -> report names the duplicated primitive (eta-hook)"
else
  fail "duplicated-row -> report should name eta-hook" "$(cat /tmp/loom_cat_dup.out)"
fi

# =====================================================================
# Behavior clause 4 — substring safety: a name that is a prefix of
# another shipped name must NOT satisfy the longer name's row, and
# vice-versa. (Real tree: loom-upstream-gc vs check-loom-upstream.)
# =====================================================================
echo "==> clause 4: substring-safe matching (no prefix cross-credit)"

TMP_SUB="$(mktemp -d)"
trap 'rm -rf "$TMP_CLEAN" "$TMP_MISS" "$TMP_DUP" "$TMP_EXTRA" "$TMP_SUB"' EXIT
build_fixture "$TMP_SUB"
# Ship two commands where one name is a substring of the other, but only
# list the SHORTER one. The longer one must be reported MISSING — i.e.
# the shorter row must not be mis-credited to the longer primitive.
printf '# foo\n'     >"$TMP_SUB/commands/foo.md"
printf '# foo-bar\n' >"$TMP_SUB/commands/foo-bar.md"
cat >"$TMP_SUB/docs/reference/slash-commands/index.md" <<'EOF'
# Slash commands

| Command | Trigger |
|---|---|
| `/gamma [id]` | User-typed |
| `/delta` | User-typed |
| `/foo` | User-typed |
EOF

if LOOM_DOCS_ROOT="$TMP_SUB" "$SCRIPT" --check >/tmp/loom_cat_sub.out 2>&1; then
  fail "substring-safe -> expected exit 1 (foo-bar unlisted), got 0" "$(cat /tmp/loom_cat_sub.out)"
else
  pass "substring-safe -> non-zero exit (foo-bar correctly unlisted)"
fi
if grep -q 'foo-bar' /tmp/loom_cat_sub.out; then
  pass "substring-safe -> foo-bar reported missing (not mis-credited to /foo row)"
else
  fail "substring-safe -> foo-bar should be reported missing" "$(cat /tmp/loom_cat_sub.out)"
fi

# =====================================================================
# LIVE clause — the REAL loom docs tables are complete + dup-free.
# RED until phase A (fix the 4 index tables) lands; GREEN after. This is
# the executable spec that drives the table-completeness fix.
# =====================================================================
echo "==> live: the real loom reference index tables are complete + dup-free"

if [ -x "$SCRIPT" ] && "$SCRIPT" --check >/tmp/loom_cat_live.out 2>&1; then
  pass "live tree: loom-docs-catalogue --check is clean"
else
  fail "live tree: loom-docs-catalogue --check found drift (expected RED until phase A)" \
    "$(cat /tmp/loom_cat_live.out 2>/dev/null)"
fi

# =====================================================================
# Registration — wired into the docs pre-push gate so drift can't ship.
# =====================================================================
echo "==> registration: --check wired into the docs pre-push gate"

if [ -f "$PREPUSH" ] && grep -q 'loom-docs-catalogue' "$PREPUSH"; then
  pass "pre-push-mkdocs-strict.sh invokes loom-docs-catalogue"
else
  fail "pre-push-mkdocs-strict.sh invokes loom-docs-catalogue" \
    "(no reference to loom-docs-catalogue in $PREPUSH)"
fi

# =====================================================================
# Summary
# =====================================================================
echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
