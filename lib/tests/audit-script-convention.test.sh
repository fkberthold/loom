#!/usr/bin/env bash
# Behavior + doc-text tests for the /audit-project script/ convention
# check (loom-oxs.4).
#
# The loom "script/ convention" (GitHub "scripts to rule them all"
# lineage, locked in the loom-adm script/-convention decision drawer)
# is a fixed set of 8 normalized entry-point scripts every loom-managed
# repo carries (bootstrap setup update server test lint cibuild deploy).
# templates/scripts/ ships the canonical skeleton (loom-oxs.1). This
# check makes /audit-project + the project-onboarder agent:
#
#   1. RECOGNIZE the convention when a project has a script/ OR scripts/
#      directory (EITHER dir name is accepted — singular is the default,
#      plural is tolerated).
#   2. SURFACE the gap when canonical scripts are missing, as
#      per-script PASS / WARN / MISS verdicts, and OFFER to scaffold the
#      missing scripts from templates/scripts/.
#   3. OFFER to migrate a legacy `workflow.json .deploy` value into the
#      constitution's canonical_commands.deploy (loom-oxs.3 shipped the
#      schema field; script/deploy is the executable home for it).
#
# /audit-project is Claude-executed prose (a skill mode + a subagent
# detection recipe), so this test is split the same way every other
# audit-project prose test in this suite is:
#
#   1. Behavior tests — exercise the DETERMINISTIC half of the check
#      against fixture project trees. The directory recognizer (a
#      project "has the script/ convention" iff it has an executable
#      script/ OR scripts/ directory) and the per-script gap classifier
#      (present+executable -> PASS, present-but-non-executable / stub ->
#      WARN, absent -> MISS) are mechanical and MUST produce a stable
#      verdict per tree. We embed a reference implementation of each
#      (the contract the prose must describe) and assert it against
#      fixture trees.
#
#   2. Doc-presence tests — verify the SKILL.md / project-onboarder.md
#      prose (the two files loom-oxs.4 owns) describes the recognizer
#      (both dir names), the PASS/WARN/MISS gap surfacing, the
#      scaffold-from-templates/scripts/ offer, and the
#      workflow.json .deploy -> canonical_commands.deploy migration
#      offer.
#
# The detectors are the executable spec the prose carries; if the prose
# evolves, update these patterns in the same commit.
#
# Run:  bash lib/tests/audit-script-convention.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL_FILE="$LOOM_ROOT/skills/audit-project/SKILL.md"
AGENT_FILE="$LOOM_ROOT/agents/project-onboarder.md"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

assert_contains() {
  local name="$1" file="$2" pattern="$3"
  if [ ! -f "$file" ]; then
    fail "$name" "(file missing: $file)"
    return
  fi
  if grep -qE "$pattern" "$file"; then
    pass "$name"
  else
    fail "$name" "(pattern not found in $file: $pattern)"
  fi
}

# The 8 canonical scripts, in convention order.
CANONICAL=(bootstrap setup update server test lint cibuild deploy)

# =====================================================================
# RED clause 1 — recognize EITHER dir name (script/ OR scripts/)
# =====================================================================
#
# Reference recognizer: a project "has the script/ convention" iff it
# carries an executable file named in CANONICAL under script/ OR
# scripts/. Echoes the recognized directory name (script or scripts),
# or empty if neither is present.

recognize_script_dir() {
  local root="$1" d
  for d in script scripts; do
    if [ -d "$root/$d" ]; then
      echo "$d"
      return 0
    fi
  done
  echo ""
}

echo "==> RED clause 1: recognizer accepts BOTH script/ and scripts/"

TMP_REC="$(mktemp -d)"
TMP_GAP=""
trap 'rm -rf "$TMP_REC" "$TMP_GAP"' EXIT

# Case A: singular script/ -> recognized as "script"
mkdir -p "$TMP_REC/a/script"
got=$(recognize_script_dir "$TMP_REC/a")
if [ "$got" = "script" ]; then
  pass "case A: singular script/ recognized"
else
  fail "case A: singular script/ -> expected 'script', got '$got'"
fi

# Case B: plural scripts/ -> recognized as "scripts"
mkdir -p "$TMP_REC/b/scripts"
got=$(recognize_script_dir "$TMP_REC/b")
if [ "$got" = "scripts" ]; then
  pass "case B: plural scripts/ recognized"
else
  fail "case B: plural scripts/ -> expected 'scripts', got '$got'"
fi

# Case C: neither -> not recognized (empty)
mkdir -p "$TMP_REC/c"
got=$(recognize_script_dir "$TMP_REC/c")
if [ -z "$got" ]; then
  pass "case C: no script(s)/ dir -> convention not recognized"
else
  fail "case C: no script(s)/ dir -> expected empty, got '$got'"
fi

# Doc-presence: BOTH dir names must be named in the SKILL + onboarder.
assert_contains "SKILL recognizer accepts singular script/ dir" \
  "$SKILL_FILE" 'script/'
assert_contains "SKILL recognizer also accepts plural scripts/ dir" \
  "$SKILL_FILE" 'scripts/'
# The SKILL must explicitly state BOTH dir names are recognized (not
# just mention them incidentally). Flatten line wraps before matching.
if tr '\n' ' ' <"$SKILL_FILE" | grep -qE '(script/.*(or|OR|AND|and).*scripts/|scripts/.*(or|OR|AND|and).*script/|both.*script.*scripts|script.*singular.*scripts.*plural|EITHER.*script)'; then
  pass "SKILL states BOTH script/ and scripts/ are recognized"
else
  fail "SKILL states BOTH script/ and scripts/ are recognized" \
    "(both-dir-name statement not found in flattened SKILL.md)"
fi
assert_contains "onboarder recognizer accepts singular script/ dir" \
  "$AGENT_FILE" 'script/'
assert_contains "onboarder recognizer also accepts plural scripts/ dir" \
  "$AGENT_FILE" 'scripts/'
if tr '\n' ' ' <"$AGENT_FILE" | grep -qE '(script/.*(or|OR|AND|and).*scripts/|scripts/.*(or|OR|AND|and).*script/|both.*script.*scripts|EITHER.*script|script.*singular.*scripts.*plural)'; then
  pass "onboarder states BOTH script/ and scripts/ are recognized"
else
  fail "onboarder states BOTH script/ and scripts/ are recognized" \
    "(both-dir-name statement not found in flattened project-onboarder.md)"
fi

# =====================================================================
# RED clause 2 — gap surfaced as PASS/WARN/MISS + scaffold offer
# =====================================================================
#
# Reference per-script classifier: for a canonical script <s> under the
# recognized dir <d>:
#   PASS = <d>/<s> exists AND is executable AND is wired (not the
#          unedited exit-2 stub).
#   WARN = <d>/<s> exists but is non-executable OR is still the unedited
#          exit-2 "not implemented" stub (present-but-not-ready).
#   MISS = <d>/<s> absent.

classify_script() {
  local dir="$1" s="$2"
  local path="$dir/$s"
  if [ ! -e "$path" ]; then
    echo "MISS"; return
  fi
  if [ ! -x "$path" ]; then
    echo "WARN"; return
  fi
  # Unedited stub: prints "not implemented" + exits 2. Detect by the
  # marker text the templates/scripts/ stubs ship with.
  if grep -q 'not implemented' "$path" 2>/dev/null; then
    echo "WARN"; return
  fi
  echo "PASS"
}

echo "==> RED clause 2: per-script gap classifier emits PASS/WARN/MISS"

TMP_GAP="$(mktemp -d)"
mkdir -p "$TMP_GAP/script"

# PASS fixture: an executable, wired script.
printf '#!/usr/bin/env bash\ngo test ./...\n' >"$TMP_GAP/script/test"
chmod +x "$TMP_GAP/script/test"
got=$(classify_script "$TMP_GAP/script" test)
if [ "$got" = "PASS" ]; then
  pass "gap: wired+executable script -> PASS"
else
  fail "gap: wired+executable script -> expected PASS, got '$got'"
fi

# WARN fixture: present but non-executable.
printf '#!/usr/bin/env bash\nmake lint\n' >"$TMP_GAP/script/lint"
chmod -x "$TMP_GAP/script/lint"
got=$(classify_script "$TMP_GAP/script" lint)
if [ "$got" = "WARN" ]; then
  pass "gap: present-but-non-executable script -> WARN"
else
  fail "gap: present-but-non-executable script -> expected WARN, got '$got'"
fi

# WARN fixture: present + executable but still the unedited exit-2 stub.
printf '#!/usr/bin/env bash\necho "setup: not implemented for this project" >&2\nexit 2\n' >"$TMP_GAP/script/setup"
chmod +x "$TMP_GAP/script/setup"
got=$(classify_script "$TMP_GAP/script" setup)
if [ "$got" = "WARN" ]; then
  pass "gap: unedited exit-2 stub -> WARN (not a vacuous PASS)"
else
  fail "gap: unedited exit-2 stub -> expected WARN, got '$got'"
fi

# MISS fixture: a canonical script that is absent.
got=$(classify_script "$TMP_GAP/script" deploy)
if [ "$got" = "MISS" ]; then
  pass "gap: absent canonical script -> MISS"
else
  fail "gap: absent canonical script -> expected MISS, got '$got'"
fi

# Doc-presence: the SKILL must surface the gap as PASS/WARN/MISS and
# offer to scaffold from templates/scripts/.
assert_contains "SKILL surfaces script gap as PASS verdict" \
  "$SKILL_FILE" 'PASS'
assert_contains "SKILL surfaces script gap as WARN verdict" \
  "$SKILL_FILE" 'WARN'
assert_contains "SKILL surfaces script gap as MISS verdict" \
  "$SKILL_FILE" 'MISS'
assert_contains "SKILL offers scaffold from templates/scripts/" \
  "$SKILL_FILE" 'templates/scripts/'
# The scaffold must be described as an OFFER (the bead's contract: it
# OFFERS scaffold, it does not silently auto-apply).
if tr '\n' ' ' <"$SKILL_FILE" | grep -qE '(offer.*scaffold|scaffold.*offer|offer to scaffold|scaffold.*templates/scripts)'; then
  pass "SKILL describes scaffold-from-templates/scripts/ as an OFFER"
else
  fail "SKILL describes scaffold-from-templates/scripts/ as an OFFER" \
    "(offer-to-scaffold statement not found in flattened SKILL.md)"
fi
# The onboarder owns the read-only detection; it must enumerate the 8
# canonical scripts and the per-script PASS/WARN/MISS verdict.
assert_contains "onboarder names the canonical script set (bootstrap)" \
  "$AGENT_FILE" 'bootstrap'
assert_contains "onboarder names the canonical script set (cibuild)" \
  "$AGENT_FILE" 'cibuild'
assert_contains "onboarder emits per-script PASS/WARN/MISS" \
  "$AGENT_FILE" 'PASS.*WARN.*MISS|WARN.*MISS|PASS/WARN/MISS'
assert_contains "onboarder points the scaffold offer at templates/scripts/" \
  "$AGENT_FILE" 'templates/scripts/'

# =====================================================================
# RED clause 3 — workflow.json .deploy -> canonical_commands.deploy
# =====================================================================
#
# Reference detector: a project is a .deploy-migration candidate iff
# its workflow.json has a non-empty .deploy AND the constitution's
# canonical_commands.deploy is empty/unset. When so, the audit OFFERS
# to copy the .deploy value into canonical_commands.deploy.

deploy_migration_candidate() {
  local wf_deploy="$1" cc_deploy="$2"
  # candidate iff workflow.json .deploy is non-empty AND
  # canonical_commands.deploy is empty.
  if [ -n "$wf_deploy" ] && [ -z "$cc_deploy" ]; then
    echo "MIGRATE"; return
  fi
  echo "NOOP"
}

echo "==> RED clause 3: .deploy -> canonical_commands.deploy migration detector"

# Case A: workflow.json .deploy set, constitution canonical_commands.deploy empty -> MIGRATE
got=$(deploy_migration_candidate "./install.sh" "")
if [ "$got" = "MIGRATE" ]; then
  pass "migrate: .deploy set + canonical_commands.deploy empty -> MIGRATE"
else
  fail "migrate: expected MIGRATE, got '$got'"
fi

# Case B: both set -> no-op (already migrated)
got=$(deploy_migration_candidate "./install.sh" "./install.sh")
if [ "$got" = "NOOP" ]; then
  pass "migrate: both set -> NOOP (already migrated)"
else
  fail "migrate: both set -> expected NOOP, got '$got'"
fi

# Case C: .deploy empty -> nothing to migrate
got=$(deploy_migration_candidate "" "")
if [ "$got" = "NOOP" ]; then
  pass "migrate: .deploy empty -> NOOP (nothing to migrate)"
else
  fail "migrate: .deploy empty -> expected NOOP, got '$got'"
fi

# Doc-presence: the SKILL must describe the migration offer end-to-end.
assert_contains "SKILL describes workflow.json .deploy field as the migration source" \
  "$SKILL_FILE" 'workflow\.json.*\.deploy|\.deploy.*workflow\.json|workflow\.json. .deploy'
assert_contains "SKILL names canonical_commands.deploy as the migration target" \
  "$SKILL_FILE" 'canonical_commands\.deploy'
# The migration must be described as an OFFER (interactive), not silent.
if tr '\n' ' ' <"$SKILL_FILE" | grep -qE '(offer.*migrat|migrat.*offer|offer to migrate|migrate.*\.deploy.*canonical_commands|\.deploy.*->.*canonical_commands|\.deploy.*to.*canonical_commands\.deploy)'; then
  pass "SKILL describes the .deploy -> canonical_commands.deploy migration as an OFFER"
else
  fail "SKILL describes the .deploy -> canonical_commands.deploy migration as an OFFER" \
    "(offer-to-migrate statement not found in flattened SKILL.md)"
fi
# The onboarder reports the migration candidacy.
assert_contains "onboarder reports the .deploy migration candidacy" \
  "$AGENT_FILE" 'canonical_commands\.deploy'
assert_contains "onboarder names workflow.json .deploy as the migration source" \
  "$AGENT_FILE" '\.deploy'

# =====================================================================
# Registration — new check-name in the audit state-file roster + lineage
# =====================================================================
#
# Sibling interactive checks (items 13/14/15/21) each register a skip
# memo check-name in the SKILL's state-file roster. The script-convention
# check follows the same shape: a skip memo so a declined offer doesn't
# re-prompt.

echo "==> registration: script-convention check-name in the state-file roster"
assert_contains "SKILL registers the script-convention skip-memo check-name" \
  "$SKILL_FILE" 'script-convention'
assert_contains "onboarder registers the script-convention skip-memo check-name" \
  "$AGENT_FILE" 'script-convention'

echo "==> lineage: loom-oxs.4 cited on the new check"
assert_contains "SKILL cites loom-oxs lineage on the script-convention check" \
  "$SKILL_FILE" 'loom-oxs'
assert_contains "onboarder cites loom-oxs lineage on the script-convention check" \
  "$AGENT_FILE" 'loom-oxs'

# =====================================================================
# Summary
# =====================================================================
echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
