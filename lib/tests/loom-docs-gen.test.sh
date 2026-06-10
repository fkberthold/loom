#!/usr/bin/env bash
# Behavior tests for scripts/loom-docs-gen (loom-itph).
#
# THE GOAL: uniform per-item browsable left-nav across all four primitive
# categories (skills/commands/subagents/hooks), GENERATED rather than
# hand-maintained — without adding Python plugins (loom's constitution
# forbids pip-install + pins runtime=bash), so this mirrors the
# loom-fanout-detect / loom-docs-catalogue deterministic-bash-script +
# drift-gate pattern.
#
# scripts/loom-docs-gen [--check]:
#   default → for each shipped primitive (skills/*/SKILL.md, commands/*.md,
#     agents/*.md, hooks/*.sh) ensure a nav page exists: a CURATED rich
#     page if one is registered (preserved verbatim, NEVER overwritten),
#     else GENERATE a thin include-wrapper page at
#     docs/reference/<navdir>/<name>.md. Then rewrite the
#     LOOM-DOCS-GEN:START/END sentinel nav block in mkdocs.yml listing
#     every primitive per category + the "All ___ (verbatim)" dump last.
#     IDEMPOTENT.
#   --check → recompute the expected pages + nav block and DIFF against
#     what is committed; exit 1 naming any staleness (missing/extra/stale
#     wrapper, or a stale nav block); exit 0 when in sync. The drift gate.
#
# Roots from BASH_SOURCE; LOOM_DOCS_ROOT overrides for fixtures (mirrors
# loom-docs-catalogue + script/test's LOOM_TEST_DIR).
#
# Run:  bash lib/tests/loom-docs-gen.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$LOOM_ROOT/scripts/loom-docs-gen"
PREPUSH="$LOOM_ROOT/hooks/pre-push-mkdocs-strict.sh"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# ---------------------------------------------------------------------
# Fixture: a structurally faithful mini-tree. Two skills (one curated,
# one not), two commands, two subagents (never curated), two hooks (one
# curated). The curated registry inside the script is keyed on real loom
# names, so the fixture reuses two of them (explore = curated skill;
# cwd-drift-guard = curated hook) to exercise the preserve-curated path.
# ---------------------------------------------------------------------
build_fixture() {
  local r="$1"
  mkdir -p "$r/skills/explore" "$r/skills/feature-a-bead" \
           "$r/commands" "$r/agents" "$r/hooks" \
           "$r/docs/reference/skills" "$r/docs/reference/slash-commands" \
           "$r/docs/reference/subagents" "$r/docs/reference/hooks"

  printf '# explore SKILL\n' >"$r/skills/explore/SKILL.md"
  printf '# feature-a-bead SKILL\n' >"$r/skills/feature-a-bead/SKILL.md"
  printf '# wrap-up command\n' >"$r/commands/wrap-up.md"
  printf '# working-a-bead command\n' >"$r/commands/working-a-bead.md"
  printf '# drawer-author agent\n' >"$r/agents/drawer-author.md"
  printf '# project-onboarder agent\n' >"$r/agents/project-onboarder.md"
  printf '#!/usr/bin/env bash\n# cwd-drift-guard\n' >"$r/hooks/cwd-drift-guard.sh"
  printf '#!/usr/bin/env bash\n# git-push-bd-sync\n' >"$r/hooks/git-push-bd-sync.sh"

  # Curated rich pages (must be preserved, never regenerated):
  printf '# explore — reference\n\nRich hand-authored prose.\n' >"$r/docs/reference/explore.md"
  printf '# cwd-drift-guard hook\n\nRich hand-authored prose.\n' >"$r/docs/reference/cwd-drift-guard.md"

  # Minimal index + dump pages per category (the generator lists these).
  for nav in skills slash-commands subagents hooks; do
    printf '# %s\n' "$nav" >"$r/docs/reference/$nav/index.md"
    printf '# %s dump\n' "$nav" >"$r/docs/reference/$nav/all-$nav.md"
  done
  # the *-all naming the generator expects: all-skills/all-slash-commands?
  # The dump file convention is all-<navdir>.md; fixtures match it.

  # mkdocs.yml with the sentinel block the generator rewrites.
  cat >"$r/mkdocs.yml" <<'EOF'
site_name: fixture
nav:
  - Home: index.md
  - Reference:
      - reference/index.md
      # LOOM-DOCS-GEN:START
      - Skills:
          - reference/skills/index.md
      # LOOM-DOCS-GEN:END
      - Glossary: reference/glossary.md
EOF
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# =====================================================================
# Clause 0 — script exists + executable (RED until written)
# =====================================================================
echo "==> clause 0: scripts/loom-docs-gen exists + executable"
if [ -x "$SCRIPT" ]; then pass "script present + executable"
else fail "script present + executable" "(missing/non-exec: $SCRIPT — RED until written)"; fi

# =====================================================================
# Clause 1 — generate creates wrapper pages for NON-curated primitives,
# leaves curated pages untouched.
# =====================================================================
echo "==> clause 1: generate writes wrappers for non-curated, preserves curated"
R1="$TMP/r1"; build_fixture "$R1"
curated_before="$(cat "$R1/docs/reference/explore.md")"
LOOM_DOCS_ROOT="$R1" "$SCRIPT" >/tmp/ldg1.out 2>&1
gen_rc=$?
[ "$gen_rc" = 0 ] && pass "generate exits 0" || fail "generate exits 0 (got $gen_rc)" "$(cat /tmp/ldg1.out)"

# non-curated skill feature-a-bead -> generated wrapper page exists
if [ -f "$R1/docs/reference/skills/feature-a-bead.md" ]; then
  pass "generated wrapper for non-curated skill (feature-a-bead)"
else
  fail "generated wrapper for non-curated skill (feature-a-bead)" "(page not written)"
fi
# the generated wrapper pulls in the source via include
if grep -qE 'include' "$R1/docs/reference/skills/feature-a-bead.md" 2>/dev/null \
   && grep -q 'skills/feature-a-bead/SKILL.md' "$R1/docs/reference/skills/feature-a-bead.md" 2>/dev/null; then
  pass "generated skill wrapper includes its source SKILL.md"
else
  fail "generated skill wrapper includes its source SKILL.md" "$(cat "$R1/docs/reference/skills/feature-a-bead.md" 2>/dev/null)"
fi
# generated wrapper carries a DO-NOT-EDIT / GENERATED marker
if grep -qiE 'GENERATED|do not edit' "$R1/docs/reference/skills/feature-a-bead.md" 2>/dev/null; then
  pass "generated wrapper carries a GENERATED / do-not-edit marker"
else
  fail "generated wrapper carries a GENERATED / do-not-edit marker"
fi
# subagent (never curated) -> generated wrapper
if [ -f "$R1/docs/reference/subagents/drawer-author.md" ]; then
  pass "generated wrapper for subagent (drawer-author)"
else
  fail "generated wrapper for subagent (drawer-author)"
fi
# hook wrapper: non-curated git-push-bd-sync -> generated; includes .sh in a code fence
if grep -q 'hooks/git-push-bd-sync.sh' "$R1/docs/reference/hooks/git-push-bd-sync.md" 2>/dev/null \
   && grep -q '```' "$R1/docs/reference/hooks/git-push-bd-sync.md" 2>/dev/null; then
  pass "generated hook wrapper code-fence-includes its .sh source"
else
  fail "generated hook wrapper code-fence-includes its .sh source" "$(cat "$R1/docs/reference/hooks/git-push-bd-sync.md" 2>/dev/null)"
fi
# CURATED preservation: explore (skill) + cwd-drift-guard (hook) NOT overwritten,
# and NO generated page created at the category path shadowing them.
if [ "$(cat "$R1/docs/reference/explore.md")" = "$curated_before" ]; then
  pass "curated page (explore.md) preserved verbatim"
else
  fail "curated page (explore.md) preserved verbatim" "(content changed)"
fi
if [ ! -f "$R1/docs/reference/skills/explore.md" ]; then
  pass "no generated wrapper shadows the curated explore page"
else
  fail "no generated wrapper shadows the curated explore page" "(duplicate page generated)"
fi

# =====================================================================
# Clause 2 — nav block: every primitive listed between the sentinels,
# curated entries point at the curated page, dump listed last.
# =====================================================================
echo "==> clause 2: sentinel nav block lists every primitive (curated->curated path)"
navblock="$(awk '/LOOM-DOCS-GEN:START/{f=1} f{print} /LOOM-DOCS-GEN:END/{f=0}' "$R1/mkdocs.yml")"
for needle in \
  'reference/explore.md' \
  'reference/skills/feature-a-bead.md' \
  'reference/slash-commands/wrap-up.md' \
  'reference/subagents/drawer-author.md' \
  'reference/cwd-drift-guard.md' \
  'reference/hooks/git-push-bd-sync.md' \
  'reference/skills/all-skills.md'; do
  if printf '%s' "$navblock" | grep -q "$needle"; then
    pass "nav block references $needle"
  else
    fail "nav block references $needle" "$navblock"
  fi
done
# sentinels preserved + the non-generated parts of mkdocs.yml survive
if grep -q 'LOOM-DOCS-GEN:END' "$R1/mkdocs.yml" && grep -q 'Glossary' "$R1/mkdocs.yml"; then
  pass "sentinels + surrounding hand-nav preserved"
else
  fail "sentinels + surrounding hand-nav preserved" "$(cat "$R1/mkdocs.yml")"
fi

# =====================================================================
# Clause 3 — idempotency: a second run changes nothing.
# =====================================================================
echo "==> clause 3: generate is idempotent"
snap="$(find "$R1/docs/reference" -type f -exec sha1sum {} \; | sort; sha1sum "$R1/mkdocs.yml")"
LOOM_DOCS_ROOT="$R1" "$SCRIPT" >/dev/null 2>&1
snap2="$(find "$R1/docs/reference" -type f -exec sha1sum {} \; | sort; sha1sum "$R1/mkdocs.yml")"
[ "$snap" = "$snap2" ] && pass "second generate is a no-op (idempotent)" \
  || fail "second generate is a no-op (idempotent)" "(files changed on rerun)"

# =====================================================================
# Clause 4 — --check: clean tree exits 0; drift exits 1 and names it.
# =====================================================================
echo "==> clause 4: --check 0 on clean, 1 on drift"
if LOOM_DOCS_ROOT="$R1" "$SCRIPT" --check >/tmp/ldg_chk.out 2>&1; then
  pass "--check on freshly-generated tree exits 0"
else
  fail "--check on freshly-generated tree exits 0" "$(cat /tmp/ldg_chk.out)"
fi
# drift A: delete a generated wrapper
rm -f "$R1/docs/reference/subagents/project-onboarder.md"
if LOOM_DOCS_ROOT="$R1" "$SCRIPT" --check >/tmp/ldg_chk2.out 2>&1; then
  fail "--check after deleting a wrapper exits 1 (got 0)" "$(cat /tmp/ldg_chk2.out)"
else
  pass "--check after deleting a wrapper exits non-zero"
fi
grep -q 'project-onboarder' /tmp/ldg_chk2.out \
  && pass "--check names the stale/missing primitive (project-onboarder)" \
  || fail "--check names the stale/missing primitive" "$(cat /tmp/ldg_chk2.out)"

# drift B: add a brand-new primitive on disk without regenerating
R2="$TMP/r2"; build_fixture "$R2"
LOOM_DOCS_ROOT="$R2" "$SCRIPT" >/dev/null 2>&1   # sync first
mkdir -p "$R2/agents"; printf '# newcomer agent\n' >"$R2/agents/newcomer.md"
if LOOM_DOCS_ROOT="$R2" "$SCRIPT" --check >/tmp/ldg_chk3.out 2>&1; then
  fail "--check after adding a new primitive exits 1 (got 0)" "$(cat /tmp/ldg_chk3.out)"
else
  pass "--check after adding a new primitive exits non-zero"
fi
grep -q 'newcomer' /tmp/ldg_chk3.out \
  && pass "--check names the new unlisted primitive (newcomer)" \
  || fail "--check names the new unlisted primitive" "$(cat /tmp/ldg_chk3.out)"

# =====================================================================
# Registration — wired into the docs pre-push gate.
# =====================================================================
echo "==> registration: --check wired into pre-push-mkdocs-strict.sh"
if [ -f "$PREPUSH" ] && grep -q 'loom-docs-gen' "$PREPUSH"; then
  pass "pre-push-mkdocs-strict.sh invokes loom-docs-gen --check"
else
  fail "pre-push-mkdocs-strict.sh invokes loom-docs-gen --check"
fi

# =====================================================================
# LIVE — the real loom tree is generated + in sync (RED until I run the
# generator on the repo + commit; GREEN after).
# =====================================================================
echo "==> live: real loom tree is in sync with the generator"
if [ -x "$SCRIPT" ] && "$SCRIPT" --check >/tmp/ldg_live.out 2>&1; then
  pass "live tree: loom-docs-gen --check is clean"
else
  fail "live tree: loom-docs-gen --check found drift (expected RED until I generate+commit)" \
    "$(head -20 /tmp/ldg_live.out 2>/dev/null)"
fi

echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
