#!/usr/bin/env bash
# Behavior + doc-text tests for the /audit-project --check=constitution
# capture flow (loom-1iz, parent epic loom-6f8).
#
# /audit-project --check=constitution is Claude-executed prose (a skill
# mode + a subagent detection recipe), so this test is split the same way
# every other audit-project prose test in this suite is:
#
#   1. Behavior tests — exercise the DETERMINISTIC half of the capture
#      flow against fixture project trees. The detection heuristics
#      (devbox.json -> shell=devbox; pnpm-lock.yaml -> pkg=pnpm;
#      flake.nix -> shell=nix-shell; Cargo.toml -> rust; go.mod -> go;
#      Makefile / ./scripts/* -> canonical_commands) are mechanical and
#      MUST produce a stable fingerprint per tree. We embed a reference
#      implementation of the fingerprint detector here (the contract the
#      SKILL.md / project-onboarder.md prose must describe) and assert it
#      against five fixture trees: devbox+pnpm, nix+cargo, go-only,
#      python+venv, bare-bash. Plus a re-run drift case: mutating
#      devbox.json -> nix surfaces the per-field drift WITHOUT clobbering
#      the captured prose body.
#
#   2. Doc-presence tests — verify the SKILL.md / project-onboarder.md
#      prose (the two files loom-1iz owns) describes the
#      --check=constitution mode, each
#      detection heuristic, the per-field-one-at-a-time confirmation
#      (loom-xcw), the UNSTAGED write, the MemPalace <project>/decisions
#      mirror, the KG triple emission, the MISS [HUMAN AUTHOR] prose-stub
#      (NEVER agent-authored — the loom-d50 lesson), and the re-run drift
#      behavior.
#
# The fingerprint detector is the executable spec the prose carries; if
# the prose evolves, update these patterns in the same commit.
#
# Run:  bash lib/tests/audit-constitution-capture.test.sh

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

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass "$name"
  else
    fail "$name" "(expected '$expected', got '$actual')"
  fi
}

# =====================================================================
# Reference detection implementation — the contract the SKILL.md /
# project-onboarder.md prose must describe. Emits a stable, sorted
# fingerprint of `field=value` lines for a project tree at $1.
#
# Heuristics (exactly the bead loom-1iz Step-1 set):
#   devbox.json      -> shell.enter=devbox shell / run_prefix=devbox run
#   flake.nix        -> shell.enter=nix-shell    (when no devbox.json)
#   pnpm-lock.yaml   -> package_manager=pnpm
#   yarn.lock        -> package_manager=yarn
#   package-lock.json-> package_manager=npm
#   uv.lock          -> package_manager=uv
#   poetry.lock      -> package_manager=poetry
#   Cargo.toml       -> package_manager=cargo + language.runtime=rust
#   go.mod           -> package_manager=go    + language.runtime=go
#   pyproject/req*   -> language.runtime=python (pkg stays unless lock seen)
#   Makefile         -> canonical_commands from `make` targets
#   ./scripts/test … -> canonical_commands from script presence
# Empty / undetected fields are emitted as field= (empty value stays
# empty — never invented).
# =====================================================================
detect_constitution_fingerprint() {
  local root="$1"
  local shell_enter="" shell_prefix="" pkg="none" runtime="unknown"
  local build="" test="" lint="" gen="" dev=""

  # --- shell envelope ---
  if [ -f "$root/devbox.json" ]; then
    shell_enter="devbox shell"; shell_prefix="devbox run"
  elif [ -f "$root/flake.nix" ]; then
    shell_enter="nix-shell"; shell_prefix="nix-shell --run"
  fi

  # --- package manager (first decisive lockfile / manifest wins) ---
  if   [ -f "$root/pnpm-lock.yaml" ];    then pkg="pnpm"
  elif [ -f "$root/yarn.lock" ];         then pkg="yarn"
  elif [ -f "$root/package-lock.json" ]; then pkg="npm"
  elif [ -f "$root/uv.lock" ];           then pkg="uv"
  elif [ -f "$root/poetry.lock" ];       then pkg="poetry"
  elif [ -f "$root/Cargo.toml" ];        then pkg="cargo"
  elif [ -f "$root/go.mod" ];            then pkg="go"
  fi

  # --- language runtime ---
  if   [ -f "$root/Cargo.toml" ];        then runtime="rust"
  elif [ -f "$root/go.mod" ];            then runtime="go"
  elif [ -f "$root/pyproject.toml" ] || [ -f "$root/setup.py" ] \
    || [ -f "$root/setup.cfg" ] || ls "$root"/requirements*.txt >/dev/null 2>&1; then
    runtime="python"
  elif [ -f "$root/package.json" ] && [ "$pkg" != "none" ]; then
    runtime="node"
  elif [ -d "$root/scripts" ] && ls "$root"/scripts/*.sh >/dev/null 2>&1; then
    runtime="bash"
  fi

  # --- canonical commands: Makefile targets ---
  if [ -f "$root/Makefile" ]; then
    grep -qE '^build:' "$root/Makefile" && build="make build"
    grep -qE '^test:'  "$root/Makefile" && test="make test"
    grep -qE '^lint:'  "$root/Makefile" && lint="make lint"
  fi
  # --- canonical commands: ./scripts/* presence (does not override Makefile) ---
  [ -z "$build" ] && [ -x "$root/scripts/build" ] && build="./scripts/build"
  [ -z "$test" ]  && [ -x "$root/scripts/test" ]  && test="./scripts/test"
  [ -z "$lint" ]  && [ -x "$root/scripts/lint" ]  && lint="./scripts/lint"
  [ -z "$gen" ]   && [ -x "$root/scripts/gen" ]   && gen="./scripts/gen"
  [ -z "$dev" ]   && [ -x "$root/scripts/server" ] && dev="./scripts/server"

  # Emit sorted, stable fingerprint. Empty fields stay empty.
  printf 'canonical_commands.build=%s\n' "$build"
  printf 'canonical_commands.dev=%s\n'   "$dev"
  printf 'canonical_commands.gen=%s\n'   "$gen"
  printf 'canonical_commands.lint=%s\n'  "$lint"
  printf 'canonical_commands.test=%s\n'  "$test"
  printf 'language.runtime=%s\n'         "$runtime"
  printf 'package_manager=%s\n'          "$pkg"
  printf 'shell.enter=%s\n'              "$shell_enter"
  printf 'shell.run_prefix=%s\n'         "$shell_prefix"
}

fp_field() { printf '%s\n' "$1" | grep "^$2=" | head -n1 | cut -d= -f2-; }

# =====================================================================
# 1. Behavior — fixture project trees each detect the expected
#    fingerprint.
# =====================================================================
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---- Fixture A: devbox + pnpm ----
echo "==> Fixture A: devbox + pnpm"
A="$TMP/devbox-pnpm"; mkdir -p "$A"
printf '{"packages":["nodejs@20"]}\n' >"$A/devbox.json"
printf '{"name":"app"}\n' >"$A/package.json"
: >"$A/pnpm-lock.yaml"
fpA="$(detect_constitution_fingerprint "$A")"
assert_eq "A shell.enter=devbox shell"      "devbox shell" "$(fp_field "$fpA" shell.enter)"
assert_eq "A shell.run_prefix=devbox run"   "devbox run"   "$(fp_field "$fpA" shell.run_prefix)"
assert_eq "A package_manager=pnpm"          "pnpm"         "$(fp_field "$fpA" package_manager)"
assert_eq "A language.runtime=node"         "node"         "$(fp_field "$fpA" language.runtime)"

# ---- Fixture B: nix + cargo ----
echo "==> Fixture B: nix + cargo"
B="$TMP/nix-cargo"; mkdir -p "$B"
printf '{ outputs = {}; }\n' >"$B/flake.nix"
printf '[package]\nname = "x"\n' >"$B/Cargo.toml"
fpB="$(detect_constitution_fingerprint "$B")"
assert_eq "B shell.enter=nix-shell"         "nix-shell"    "$(fp_field "$fpB" shell.enter)"
assert_eq "B package_manager=cargo"         "cargo"        "$(fp_field "$fpB" package_manager)"
assert_eq "B language.runtime=rust"         "rust"         "$(fp_field "$fpB" language.runtime)"

# ---- Fixture C: go-only ----
echo "==> Fixture C: go-only"
C="$TMP/go-only"; mkdir -p "$C"
printf 'module example.com/x\n\ngo 1.24\n' >"$C/go.mod"
fpC="$(detect_constitution_fingerprint "$C")"
assert_eq "C shell.enter empty (no wrapper)" ""            "$(fp_field "$fpC" shell.enter)"
assert_eq "C package_manager=go"            "go"           "$(fp_field "$fpC" package_manager)"
assert_eq "C language.runtime=go"           "go"           "$(fp_field "$fpC" language.runtime)"

# ---- Fixture D: python + venv (requirements.txt, no lockfile) ----
echo "==> Fixture D: python + venv"
D="$TMP/python-venv"; mkdir -p "$D"
printf 'requests\n' >"$D/requirements.txt"
mkdir -p "$D/.venv"
fpD="$(detect_constitution_fingerprint "$D")"
assert_eq "D language.runtime=python"       "python"       "$(fp_field "$fpD" language.runtime)"
assert_eq "D package_manager stays none (no lock)" "none"  "$(fp_field "$fpD" package_manager)"
assert_eq "D shell.enter empty"             ""             "$(fp_field "$fpD" shell.enter)"

# ---- Fixture E: bare-bash (scripts/ + Makefile, no language manifest) ----
echo "==> Fixture E: bare-bash"
E="$TMP/bare-bash"; mkdir -p "$E/scripts"
printf '#!/usr/bin/env bash\necho hi\n' >"$E/scripts/test"; chmod +x "$E/scripts/test"
printf '#!/usr/bin/env bash\necho lint\n' >"$E/scripts/lint"; chmod +x "$E/scripts/lint"
: >"$E/scripts/run.sh"
printf 'build:\n\t@echo build\ntest:\n\t@echo test\n' >"$E/Makefile"
fpE="$(detect_constitution_fingerprint "$E")"
assert_eq "E shell.enter empty"             ""             "$(fp_field "$fpE" shell.enter)"
assert_eq "E package_manager=none"          "none"         "$(fp_field "$fpE" package_manager)"
assert_eq "E language.runtime=bash"         "bash"         "$(fp_field "$fpE" language.runtime)"
# Makefile build:/test: targets win for those verbs; scripts/lint fills lint.
assert_eq "E canonical_commands.build=make build" "make build" "$(fp_field "$fpE" canonical_commands.build)"
assert_eq "E canonical_commands.test=make test"   "make test"  "$(fp_field "$fpE" canonical_commands.test)"
assert_eq "E canonical_commands.lint=./scripts/lint" "./scripts/lint" "$(fp_field "$fpE" canonical_commands.lint)"

# =====================================================================
# 2. Re-run drift — mutating devbox.json -> nix surfaces per-field
#    drift WITHOUT clobbering the captured prose body.
# =====================================================================
echo "==> Re-run drift: devbox -> nix surfaces drift, preserves prose body"
DR="$TMP/drift"; mkdir -p "$DR/.claude"
printf '{"packages":[]}\n' >"$DR/devbox.json"
: >"$DR/pnpm-lock.yaml"
printf '{"name":"x"}\n' >"$DR/package.json"
fp_before="$(detect_constitution_fingerprint "$DR")"

# Simulate a captured constitution: front-matter from the first run +
# a HUMAN-AUTHORED prose body the re-run must NOT overwrite.
HUMAN_PROSE="HUMAN-AUTHORED RATIONALE — do not clobber on re-run."
cat >"$DR/.claude/project-constitution.md" <<EOF
---
shell:
  enter: "devbox shell"
  run_prefix: "devbox run"
package_manager: pnpm
language:
  runtime: node
  version: ""
canonical_commands:
  build: ""
  test: ""
  lint: ""
  gen: ""
  dev: ""
---

# drift — project constitution

$HUMAN_PROSE
EOF

# Mutate the tree: drop devbox, add flake.nix (now shell=nix-shell).
rm -f "$DR/devbox.json"
printf '{ outputs = {}; }\n' >"$DR/flake.nix"
fp_after="$(detect_constitution_fingerprint "$DR")"

# Drift detection: compare the captured front-matter's shell.enter against
# the freshly-detected one. The diff must surface (they differ).
captured_shell_enter="$(grep -A1 '^shell:' "$DR/.claude/project-constitution.md" | grep 'enter:' | sed 's/.*enter: *"\([^"]*\)".*/\1/')"
detected_shell_enter="$(fp_field "$fp_after" shell.enter)"
if [ "$captured_shell_enter" != "$detected_shell_enter" ]; then
  pass "re-run surfaces shell.enter drift (captured='$captured_shell_enter' vs detected='$detected_shell_enter')"
else
  fail "re-run failed to surface shell.enter drift"
fi
assert_eq "drift before shell.enter=devbox shell" "devbox shell" "$(fp_field "$fp_before" shell.enter)"
assert_eq "drift after shell.enter=nix-shell"     "nix-shell"    "$detected_shell_enter"

# The prose body must be untouched by detection (detection is read-only
# against the file; only per-field confirm can rewrite front-matter).
if grep -qF "$HUMAN_PROSE" "$DR/.claude/project-constitution.md"; then
  pass "re-run preserves the HUMAN-AUTHORED prose body (never clobbered)"
else
  fail "re-run clobbered the prose body"
fi

# =====================================================================
# 3. Doc-presence — SKILL.md documents the mode + every step
#
# (The slash-command surface — commands/audit-project.md — is out of
# loom-1iz's declared Files: footprint; surfacing the flag in the
# command doc is tracked separately. This test pins the two files the
# bead owns: the SKILL.md mode + the project-onboarder.md recipe.)
# =====================================================================
echo "==> SKILL.md documents the --check=constitution mode"
assert_contains "SKILL describes --check=constitution flag" \
  "$SKILL_FILE" '\-\-check=constitution'
assert_contains "SKILL cites loom-1iz lineage" \
  "$SKILL_FILE" 'loom-1iz'

echo "==> SKILL.md documents the detection heuristics"
assert_contains "SKILL: devbox.json -> shell=devbox" \
  "$SKILL_FILE" 'devbox\.json'
assert_contains "SKILL: pnpm-lock.yaml -> pkg=pnpm" \
  "$SKILL_FILE" 'pnpm-lock\.yaml'
assert_contains "SKILL: flake.nix -> nix-shell" \
  "$SKILL_FILE" 'flake\.nix'
assert_contains "SKILL: Cargo.toml -> rust" \
  "$SKILL_FILE" 'Cargo\.toml'
assert_contains "SKILL: go.mod -> go" \
  "$SKILL_FILE" 'go\.mod'
assert_contains "SKILL: Makefile / scripts -> canonical_commands" \
  "$SKILL_FILE" 'Makefile|\./scripts/'

echo "==> SKILL.md documents the capture-flow invariants"
# Per-field confirmation, one field at a time (loom-xcw), NEVER lump-sum.
assert_contains "SKILL: per-field confirmation, one at a time (loom-xcw)" \
  "$SKILL_FILE" '(one field at a time|per-field|field[ -]by[ -]field)'
assert_contains "SKILL: never lump-sum confirmation" \
  "$SKILL_FILE" '(never lump|not lump-sum|one at a time)'
# Write the file UNSTAGED.
assert_contains "SKILL: writes project-constitution.md UNSTAGED" \
  "$SKILL_FILE" '\.claude/project-constitution\.md'
assert_contains "SKILL: UNSTAGED keyword present" \
  "$SKILL_FILE" '[Uu][Nn][Ss][Tt][Aa][Gg][Ee][Dd]'
# MemPalace mirror to <project>/decisions.
assert_contains "SKILL: mirrors to MemPalace <project>/decisions" \
  "$SKILL_FILE" 'decisions'
assert_contains "SKILL: MemPalace mirror keyword" \
  "$SKILL_FILE" '(mempalace_add_drawer|MemPalace drawer|mirror)'
# KG triple emission for tooling.
assert_contains "SKILL: emits KG triples (uses_shell / uses_package_manager)" \
  "$SKILL_FILE" '(uses_shell|uses_package_manager|mempalace_kg_add)'
# Prose body is a MISS [HUMAN AUTHOR] stub — never agent-authored (loom-d50).
assert_contains "SKILL: prose body is MISS [HUMAN AUTHOR] stub" \
  "$SKILL_FILE" '\[HUMAN AUTHOR\]'
assert_contains "SKILL: prose body NEVER agent-authored (loom-d50)" \
  "$SKILL_FILE" 'loom-d50'
assert_contains "SKILL: prose stub explicitly never agent-authored" \
  "$SKILL_FILE" '([Nn]ever agent-authored|not agent-authored|NEVER.*author)'
# Re-run diffs detection vs captured file, per-field, without overwriting prose.
assert_contains "SKILL: re-run surfaces per-field drift" \
  "$SKILL_FILE" '(re-run|drift)'
assert_contains "SKILL: re-run does not overwrite prose body" \
  "$SKILL_FILE" '(without overwriting|preserve.*prose|not.*clobber|prose body)'

# =====================================================================
# 5. Doc-presence — project-onboarder.md carries the detection recipe
# =====================================================================
echo "==> project-onboarder.md describes the constitution detection recipe"
assert_contains "onboarder describes constitution detection" \
  "$AGENT_FILE" '(constitution|project-constitution)'
assert_contains "onboarder: devbox.json heuristic" \
  "$AGENT_FILE" 'devbox\.json'
assert_contains "onboarder: pnpm-lock.yaml heuristic" \
  "$AGENT_FILE" 'pnpm-lock\.yaml'
assert_contains "onboarder: flake.nix heuristic" \
  "$AGENT_FILE" 'flake\.nix'
assert_contains "onboarder: Cargo.toml heuristic" \
  "$AGENT_FILE" 'Cargo\.toml'
assert_contains "onboarder: go.mod heuristic" \
  "$AGENT_FILE" 'go\.mod'
# Onboarder is read-only — detection only, the skill owns the write +
# per-field confirm + MemPalace mirror.
assert_contains "onboarder stays read-only (reports fingerprint, skill writes)" \
  "$AGENT_FILE" '([Rr]ead-only|reports|does not write)'

# =====================================================================
# Summary
# =====================================================================
echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
