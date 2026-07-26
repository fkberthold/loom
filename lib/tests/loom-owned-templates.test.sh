#!/usr/bin/env bash
# Fixture tests for scripts/loom-owned-templates — the OWNED-template
# registry that closes loom-pogc's channel (2) (loom-f59h).
#
# THE GAP THIS CLOSES. loom-pogc diagnosed two channels by which loom
# pushes conventions downstream: (1) globally symlinked skills/hooks,
# which always show a project loom's CURRENT copy; and (2) per-project
# PRIMING — the project's own CLAUDE.md and .claude/rules/ — which goes
# stale with nothing forcing a re-sync. loom-ig3p built the drift
# detector over a THIRD thing entirely (templates/-derived scaffolds),
# so channel (2) was never covered: liza_base's .claude/.loom-sync hash
# matched loom's manifest hash EXACTLY while its priming was 15 days
# stale and missing every current convention.
#
# INVARIANT UNDER TEST (the loom-f59h RED spec):
#   a loom-managed project whose loom-owned convention file is ABSENT,
#   or TRAILS loom's currently shipped convention set, is reported as
#   DRIFTED; a project whose copy is CURRENT is not.
#
# The OWNED-vs-SCAFFOLD distinction is what makes that checkable. A
# scaffold template (templates/diataxis/**, templates/design-doc/**, …)
# is instantiated into a project WITH per-file variable substitution and
# then hand-edited, so loom can never byte-diff it — hence --apply-drift
# stages those into a project-local MIRROR. An OWNED template carries no
# substitutions and is never hand-edited (loom owns it outright), so it
# CAN be byte-diffed against the project's live copy and applied at its
# LIVE path.
#
# All fixtures live under mktemp -d trees, with a synthetic <loom> root
# built per-case; the real repo is only ever READ (the last section), and
# no real project's .claude/.loom-sync is touched.
#
# Run:  bash lib/tests/loom-owned-templates.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="$LOOM_ROOT/scripts/loom-owned-templates"
MANIFEST_BIN="$LOOM_ROOT/scripts/loom-convention-manifest"
RESOLVE_BIN="$LOOM_ROOT/scripts/loom-drift-resolve"

# The one owned template this bead ships. Kept as literals here so the
# test pins the CONTRACT rather than re-reading the script's own array
# (a test that asks the implementation what it should be proves nothing).
OWNED_TEMPLATE="templates/rules/loom-conventions.md"
OWNED_TARGET=".claude/rules/loom-conventions.md"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

if [ ! -e "$BIN" ]; then
  fail "scripts/loom-owned-templates exists" "not found at $BIN"
  echo
  echo "Tests: $passed passed, $failed failed"
  exit 1
fi
if [ ! -x "$BIN" ]; then
  fail "scripts/loom-owned-templates is executable" "missing +x bit at $BIN"
fi

FIXTURE="$(mktemp -d)"
cleanup() { rm -rf "$FIXTURE"; }
trap cleanup EXIT

# --- synthetic <loom> root ---------------------------------------------
# Carries ONE owned template plus one scaffold template, so the
# owned-vs-scaffold split is observable rather than assumed.
FAKE_LOOM="$FIXTURE/loom"
mkdir -p "$FAKE_LOOM/templates/rules" "$FAKE_LOOM/templates/diataxis"
printf 'loom conventions — CURRENT shipped set\n' \
  > "$FAKE_LOOM/$OWNED_TEMPLATE"
printf 'mkdocs scaffold with {{ substitutions }}\n' \
  > "$FAKE_LOOM/templates/diataxis/mkdocs.yml.template"

# ======================================================================
echo "==> --list: the owned-set declaration"
# ======================================================================

list_out="$("$BIN" --list --loom "$FAKE_LOOM" 2>&1)"
list_rc=$?

if [ "$list_rc" -eq 0 ]; then
  pass "--list exits 0"
else
  fail "--list exits 0" "rc=$list_rc; out: $list_out"
fi

expected_line="$(printf '%s\t%s' "$OWNED_TEMPLATE" "$OWNED_TARGET")"
if printf '%s\n' "$list_out" | grep -qF "$expected_line"; then
  pass "--list declares $OWNED_TEMPLATE -> $OWNED_TARGET"
else
  fail "--list declares $OWNED_TEMPLATE -> $OWNED_TARGET" "got: $list_out"
fi

# The scaffold template must NOT be in the owned set — converting the
# existing scaffold templates to live-apply would clobber every
# downstream project's customized files, and is explicitly out of scope.
if printf '%s\n' "$list_out" | grep -q 'diataxis'; then
  fail "--list excludes SCAFFOLD templates (diataxis stays mirror-applied)" \
    "got: $list_out"
else
  pass "--list excludes SCAFFOLD templates (diataxis stays mirror-applied)"
fi

# ======================================================================
echo "==> --check: absent copy is DRIFTED (the seeding case)"
# ======================================================================

PROJ_ABSENT="$FIXTURE/proj-absent"
mkdir -p "$PROJ_ABSENT/.claude"

out="$("$BIN" --check --root "$PROJ_ABSENT" --loom "$FAKE_LOOM" 2>&1)"
rc=$?

if [ "$rc" -eq 1 ]; then
  pass "--check exits 1 when the owned file is absent"
else
  fail "--check exits 1 when the owned file is absent" "rc=$rc; out: $out"
fi

if printf '%s\n' "$out" | grep -q '^\[DRIFT\]'; then
  pass "--check reports [DRIFT] for an absent owned file"
else
  fail "--check reports [DRIFT] for an absent owned file" "got: $out"
fi

if printf '%s\n' "$out" | grep -q "$OWNED_TARGET"; then
  pass "--check names the LIVE target path, not a mirror path"
else
  fail "--check names the LIVE target path, not a mirror path" "got: $out"
fi

if printf '%s\n' "$out" | grep -qi 'absent'; then
  pass "--check distinguishes the absent case in its reason text"
else
  fail "--check distinguishes the absent case in its reason text" "got: $out"
fi

# ======================================================================
echo "==> --check: stale copy is DRIFTED (the trailing case)"
# ======================================================================

PROJ_STALE="$FIXTURE/proj-stale"
mkdir -p "$PROJ_STALE/.claude/rules"
printf 'loom conventions — an OLD shipped set\n' \
  > "$PROJ_STALE/$OWNED_TARGET"

out="$("$BIN" --check --root "$PROJ_STALE" --loom "$FAKE_LOOM" 2>&1)"
rc=$?

if [ "$rc" -eq 1 ]; then
  pass "--check exits 1 when the owned file trails loom's current copy"
else
  fail "--check exits 1 when the owned file trails loom's current copy" \
    "rc=$rc; out: $out"
fi

if printf '%s\n' "$out" | grep -q '^\[DRIFT\]'; then
  pass "--check reports [DRIFT] for a stale owned file"
else
  fail "--check reports [DRIFT] for a stale owned file" "got: $out"
fi

if printf '%s\n' "$out" | grep -qi 'differ'; then
  pass "--check distinguishes the content-differs case in its reason text"
else
  fail "--check distinguishes the content-differs case in its reason text" \
    "got: $out"
fi

# ======================================================================
echo "==> --check: current copy is NOT drifted"
# ======================================================================

PROJ_CURRENT="$FIXTURE/proj-current"
mkdir -p "$PROJ_CURRENT/.claude/rules"
cp "$FAKE_LOOM/$OWNED_TEMPLATE" "$PROJ_CURRENT/$OWNED_TARGET"

out="$("$BIN" --check --root "$PROJ_CURRENT" --loom "$FAKE_LOOM" 2>&1)"
rc=$?

if [ "$rc" -eq 0 ]; then
  pass "--check exits 0 when the owned file matches loom's current copy"
else
  fail "--check exits 0 when the owned file matches loom's current copy" \
    "rc=$rc; out: $out"
fi

if printf '%s\n' "$out" | grep -q '^\[DRIFT\]'; then
  fail "--check reports NO [DRIFT] for a current owned file" "got: $out"
else
  pass "--check reports NO [DRIFT] for a current owned file"
fi

if printf '%s\n' "$out" | grep -q '^\[OK\]'; then
  pass "--check reports [OK] for a current owned file"
else
  fail "--check reports [OK] for a current owned file" "got: $out"
fi

# ======================================================================
echo "==> --items: builds a loom-drift-resolve queue at the LIVE path"
# ======================================================================

items_out="$("$BIN" --items --root "$PROJ_ABSENT" --loom "$FAKE_LOOM" 2>&1)"
rc=$?

if [ "$rc" -eq 0 ]; then
  pass "--items exits 0"
else
  fail "--items exits 0" "rc=$rc; out: $items_out"
fi

want_items="$(printf '%s\t%s' \
  "$PROJ_ABSENT/$OWNED_TARGET" "$FAKE_LOOM/$OWNED_TEMPLATE")"
if [ "$items_out" = "$want_items" ]; then
  pass "--items emits <live-target>\\t<loom-source> for the drifted item"
else
  fail "--items emits <live-target>\\t<loom-source> for the drifted item" \
    "want: $want_items"$'\n'"got:  $items_out"
fi

# The live target must NOT be the project-local mirror the scaffold
# templates use — that mirror exists because loom cannot own those
# files, and an owned file routed through it would never reach priming.
if printf '%s\n' "$items_out" | grep -q 'loom-templates'; then
  fail "--items targets the LIVE path, never the .claude/loom-templates mirror" \
    "got: $items_out"
else
  pass "--items targets the LIVE path, never the .claude/loom-templates mirror"
fi

items_current="$("$BIN" --items --root "$PROJ_CURRENT" --loom "$FAKE_LOOM" 2>&1)"
if [ -z "$items_current" ]; then
  pass "--items queues nothing when the owned file is already current"
else
  fail "--items queues nothing when the owned file is already current" \
    "got: $items_current"
fi

# ======================================================================
echo "==> end-to-end: --items | loom-drift-resolve seeds the live file"
# ======================================================================

PROJ_SEED="$FIXTURE/proj-seed"
mkdir -p "$PROJ_SEED/.claude"

"$BIN" --items --root "$PROJ_SEED" --loom "$FAKE_LOOM" \
  > "$FIXTURE/seed.items" 2>/dev/null

# (a) never-auto-apply survives the live-apply path: no decisions at all
#     must leave the project byte-identical.
bash "$RESOLVE_BIN" --items "$FIXTURE/seed.items" \
  --decisions /dev/null > "$FIXTURE/seed-noop.log" 2>&1
if [ -e "$PROJ_SEED/$OWNED_TARGET" ]; then
  fail "never-auto-apply holds for owned/live items (no decision -> no write)" \
    "file was created without an approval"
else
  pass "never-auto-apply holds for owned/live items (no decision -> no write)"
fi

# (b) an explicit approve seeds the file at its LIVE path, parent dirs
#     and all — this is the whole seeding story for a project that has
#     never carried the file.
printf '%s=approve\n' "$PROJ_SEED/$OWNED_TARGET" > "$FIXTURE/seed.decisions"
bash "$RESOLVE_BIN" --items "$FIXTURE/seed.items" \
  --decisions "$FIXTURE/seed.decisions" > "$FIXTURE/seed-apply.log" 2>&1
rc=$?

if [ "$rc" -eq 0 ]; then
  pass "loom-drift-resolve applies the owned item cleanly"
else
  fail "loom-drift-resolve applies the owned item cleanly" \
    "rc=$rc; $(cat "$FIXTURE/seed-apply.log")"
fi

if [ -f "$PROJ_SEED/$OWNED_TARGET" ]; then
  pass "seeding creates $OWNED_TARGET (parent dirs included)"
else
  fail "seeding creates $OWNED_TARGET (parent dirs included)" \
    "$(cat "$FIXTURE/seed-apply.log")"
fi

if cmp -s "$PROJ_SEED/$OWNED_TARGET" "$FAKE_LOOM/$OWNED_TEMPLATE"; then
  pass "seeded file is byte-identical to loom's current template"
else
  fail "seeded file is byte-identical to loom's current template"
fi

# And the round trip closes: a freshly seeded project is no longer drifted.
out="$("$BIN" --check --root "$PROJ_SEED" --loom "$FAKE_LOOM" 2>&1)"
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "a freshly seeded project reports NO drift (round trip closes)"
else
  fail "a freshly seeded project reports NO drift (round trip closes)" \
    "rc=$rc; out: $out"
fi

# ======================================================================
echo "==> usage errors"
# ======================================================================

out="$("$BIN" --check --root "$FIXTURE/does-not-exist" --loom "$FAKE_LOOM" 2>&1)"
rc=$?
if [ "$rc" -eq 2 ]; then
  pass "--check on a nonexistent --root is a usage error (exit 2)"
else
  fail "--check on a nonexistent --root is a usage error (exit 2)" \
    "rc=$rc; out: $out"
fi

out="$("$BIN" --check --loom "$FAKE_LOOM" 2>&1)"
rc=$?
if [ "$rc" -eq 2 ]; then
  pass "--check without --root is a usage error (exit 2)"
else
  fail "--check without --root is a usage error (exit 2)" "rc=$rc; out: $out"
fi

out="$("$BIN" --bogus 2>&1)"
rc=$?
if [ "$rc" -eq 2 ]; then
  pass "an unrecognized flag is a usage error (exit 2)"
else
  fail "an unrecognized flag is a usage error (exit 2)" "rc=$rc; out: $out"
fi

# ======================================================================
echo "==> real repo: the owned template ships, and the manifest covers it"
# ======================================================================

if [ -f "$LOOM_ROOT/$OWNED_TEMPLATE" ]; then
  pass "$OWNED_TEMPLATE ships in the loom repo"
else
  fail "$OWNED_TEMPLATE ships in the loom repo" "missing"
fi

# The manifest already globs the whole templates/ tree, so the owned
# template joins the convention hash for free — no widening needed. This
# asserts that rather than assuming it: if CONVENTION_PATHS is ever
# narrowed, the owned file would silently drop out of the drift hash.
if bash "$MANIFEST_BIN" --list 2>/dev/null | grep -qxF "$OWNED_TEMPLATE"; then
  pass "loom-convention-manifest --list covers $OWNED_TEMPLATE"
else
  fail "loom-convention-manifest --list covers $OWNED_TEMPLATE" \
    "not in the manifest file list"
fi

# ======================================================================
echo "==> the owned template is PROJECT-AGNOSTIC (adoptable verbatim)"
# ======================================================================

# A downstream project must be able to adopt this file byte-for-byte, so
# loom-specific material must never leak into it. These are the tokens
# that would make it un-adoptable; each names a loom-only fact.
if [ -f "$LOOM_ROOT/$OWNED_TEMPLATE" ]; then
  leaked=""
  for tok in 'loom/decisions' 'hundred_acre_woods' '~/repos/loom' \
             'lib/tests/' 'shellcheck' 'frank/' 'install.sh'; do
    if grep -qF "$tok" "$LOOM_ROOT/$OWNED_TEMPLATE"; then
      leaked="$leaked $tok"
    fi
  done
  if [ -z "$leaked" ]; then
    pass "owned template carries no loom-specific tokens"
  else
    fail "owned template carries no loom-specific tokens" \
      "leaked:$leaked"
  fi

  # …and it DOES carry the project-agnostic convention set it exists for.
  missing=""
  for tok in 'Files:' 'RED:' 'AUTOFAN-EXCLUDE:' \
             'Background dispatch' 'Worker-dispatch' \
             'Gate, don' 'explore' 'Splitting heuristic'; do
    if ! grep -qF "$tok" "$LOOM_ROOT/$OWNED_TEMPLATE"; then
      missing="$missing '$tok'"
    fi
  done
  if [ -z "$missing" ]; then
    pass "owned template carries the shipped convention set"
  else
    fail "owned template carries the shipped convention set" \
      "missing:$missing"
  fi

  # The do-not-edit contract has to be stated IN the file — it is the
  # only thing standing between loom's live-apply and a human's edits.
  if grep -qi 'do not edit' "$LOOM_ROOT/$OWNED_TEMPLATE"; then
    pass "owned template states its do-not-edit contract"
  else
    fail "owned template states its do-not-edit contract"
  fi
fi

echo
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
