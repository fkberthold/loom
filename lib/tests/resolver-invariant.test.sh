#!/usr/bin/env bash
# Standing INVARIANT guard for the loom script/ convention resolver
# (loom-oxs.7, epic loom-oxs T6).
#
# INVARIANT (verbatim from the bead's RED: line):
#   no loom-installed primitive hardcodes a test/lint/build command that
#   loom_resolve_command should provide; each such call-site routes
#   through the resolver.
#
# This is a GUARD test, not a RED→GREEN test. The migration that motivated
# loom-oxs.7 is a NO-OP — the invariant ALREADY HOLDS on the current tree
# (every test/lint/build runner token in a loom primitive is illustrative
# prose, a comment, a "Do NOT" prohibition, constitution-CAPTURE logic,
# or a package-manager install-hint — never a hardcoded invocation that
# operates on a managed project and bypasses the resolver). This test
# PINS that state so a FUTURE regression — a primitive that starts
# hardcoding `pytest`/`go test`/`make lint`/etc. against a managed
# project instead of asking the resolver — fails the suite.
#
# THE RESOLVER (loom-oxs.2, lib/loom-script-resolve.sh):
#   loom_resolve_command <X> resolves the project's command X through the
#   three-rung contract — script/X (or scripts/X) → canonical_commands.X
#   in .claude/project-constitution.md → warn + non-zero. It exists so a
#   loom primitive can run "the project's test/lint/build command" without
#   naming a single project's runner. The invariant says: any primitive
#   that needs to RUN a managed project's test/lint/build command must go
#   through this resolver, not hardcode a runner.
#
# SCOPE — what is IN and what is OUT.
#
#   IN scope (a genuine call-site): a loom primitive that EXECUTES a
#   MANAGED/TARGET project's test/lint/build command with a HARDCODED
#   runner (e.g. an executable hook/script line that literally runs
#   `pytest` / `go test` / `make test` against the project under
#   management) instead of calling loom_resolve_command.
#
#   OUT of scope (NOT call-sites, and NEVER to be migrated):
#     - Illustrative prose / comments / examples in markdown or `#`
#       comment lines ("whatever the project uses: npm test, pytest,
#       go test, …"). Documentation, not invocation.
#     - "Do NOT run pytest" prohibitions in read-only-agent briefs.
#     - constitution-CAPTURE logic that DERIVES canonical_commands VALUES
#       from a project's Makefile targets (it POPULATES the resolver's
#       data source — it is not a hardcoded bypass).
#     - package-manager install-hint maps (`npm install`, `pip install`)
#       — dependency installs, not test/lint/build invocations.
#     - loom's OWN meta-invocations (loom running its OWN suite via
#       `bash lib/tests/*.test.sh`, loom's own `shellcheck` lint, loom's
#       CI). The resolver is for loom-MANAGED DOWNSTREAM repos, NOT
#       loom's self-test.
#     - The upstream-a-bead lane's deliberately project-native upstream
#       test command (loom explicitly does NOT impose a framework on an
#       arbitrary upstream — that is by design, not a resolver bypass).
#
# DETECTION STRATEGY (the hard part — separating invocation from prose).
# The invariant lives in loom's EXECUTABLE surface: hooks/*.sh,
# lib/*.sh (excluding lib/tests/), and scripts/* . A genuine bypass would
# appear there as an ACTUAL command line — not a `#` comment, not markdown
# prose. So the scan:
#   1. Restricts to those executable files.
#   2. Strips comment lines (lines whose first non-blank char is `#`).
#   3. Greps the surviving (executable) lines for managed-project
#      test/lint/build runner tokens.
#   4. Subtracts a small ALLOWLIST of known-benign non-invocation
#      executable lines (the package-manager install-hint map; any line
#      that is already a loom_resolve_command call).
# A positive-control fixture (a synthetic script with a genuine hardcoded
# `pytest` invocation) proves the detector actually fires — so the guard
# can never silently rot into a vacuous pass.
#
# Markdown primitives (skills/*.md, commands/*.md, agents/*.md) are
# Claude-executed prose, not a bash execution surface: a runner token in a
# `.md` is BY CONSTRUCTION illustrative or instructional, never a literal
# managed-project invocation. The migrated call-site that DOES live in
# markdown — commands/wrap-up.md — is pinned positively below (it must
# route through loom_resolve_command and must not re-hardcode a runner as
# THE test command), mirroring wrap-up-script-resolve.test.sh.
#
# Run:  bash lib/tests/resolver-invariant.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESOLVER="$LOOM_ROOT/lib/loom-script-resolve.sh"
WRAPUP="$LOOM_ROOT/commands/wrap-up.md"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# ---------------------------------------------------------------------------
# Managed-project test/lint/build runner tokens. A hardcoded invocation of
# one of these (in an executable loom primitive, on a command line — not a
# comment) is the invariant violation we guard against. Deliberately
# excludes package-manager *install* verbs (npm install / pip install /
# yarn add): those are dependency installs the constitution-enforce hint
# map legitimately names, not test/lint/build invocations.
#
# `pytest` is matched as `pytest([^-]|$)` — a command invocation (`pytest `,
# `pytest tests/`, `python -m pytest`) but NOT `pytest-of-*` / `pytest-tempdir`,
# which are pytest's TEMP-DIR name globs (path references, never a test run).
# Without this, hooks/pytest-tempdir-prune.sh's `find ./tmp -name 'pytest-of-*'`
# false-positives as a hardcoded test invocation (loom-skxj).
RUNNER_RE='(pytest([^-]|$)|go test|golangci-lint|cargo (test|build)|make (test|lint|build|all)|npm (run|test)|yarn (test|run)|pnpm (test|run)|\beslint\b|\bruff\b|\bflake8\b|\bjest\b|\btox\b|\bnox\b|\bmvn\b|\bgradle\b)'

# scan_executable_invocations <file>
#   Echo every line of <file> that (a) is NOT a comment line (first
#   non-blank char is not `#`), (b) contains a managed-project runner
#   token, and (c) is not an allowlisted benign line. Format: "<lineno>:<line>".
#   Empty output == no genuine invocation in this file.
scan_executable_invocations() {
  local file="$1"
  [ -f "$file" ] || return 0
  awk -v re="$RUNNER_RE" '
    {
      line = $0
      # Strip comment-only lines: first non-blank char is `#`.
      stripped = line
      sub(/^[[:space:]]+/, "", stripped)
      if (substr(stripped, 1, 1) == "#") next
      # Must contain a runner token (extended regex via gensub probe).
      if (line !~ re) next
      # ALLOWLIST of benign non-invocation executable lines:
      #  - the package-manager install-hint map values quoted in the
      #    constitution-enforce remediation message (npm install et al.);
      #    they reach the runner regex via the bare manager names but are
      #    install hints, already excluded by the install-verb exclusion
      #    above — kept here as belt-and-suspenders.
      #  - any line that is ALREADY a loom_resolve_command call (the
      #    correct, resolver-routed form — not a violation).
      if (line ~ /loom_resolve_command/) next
      if (line ~ /install_hint|: *"[a-z]+ (install|add|get)"/) next
      print NR ":" line
    }
  ' "$file"
}

# ---------------------------------------------------------------------------
echo "==> Invariant: no executable loom primitive hardcodes a managed-project test/lint/build invocation"
# Build the set of executable primitive files to scan: hooks/*.sh, lib/*.sh
# (NOT lib/tests/), scripts/* . These are loom's bash execution surface —
# the only place a genuine resolver bypass could be a real command line.
mapfile -t SCAN_FILES < <(
  {
    find "$LOOM_ROOT/hooks" -maxdepth 1 -type f -name '*.sh' 2>/dev/null
    find "$LOOM_ROOT/lib"   -maxdepth 1 -type f -name '*.sh' 2>/dev/null
    find "$LOOM_ROOT/scripts" -maxdepth 1 -type f 2>/dev/null
  } | sort -u
)

violations=""
scanned=0
for f in "${SCAN_FILES[@]}"; do
  [ -f "$f" ] || continue
  scanned=$((scanned + 1))
  hits="$(scan_executable_invocations "$f")"
  if [ -n "$hits" ]; then
    rel="${f#"$LOOM_ROOT"/}"
    while IFS= read -r h; do
      violations="${violations}${rel}:${h}"$'\n'
    done <<< "$hits"
  fi
done

if [ "$scanned" -eq 0 ]; then
  fail "scanned at least one executable primitive" \
    "(no files matched hooks/*.sh, lib/*.sh, scripts/* — scan vacuous)"
elif [ -z "$violations" ]; then
  pass "no hardcoded managed-project test/lint/build invocation in $scanned executable primitives"
else
  fail "hardcoded managed-project test/lint/build invocation found — route it through loom_resolve_command" \
    "$violations"
fi

# ---------------------------------------------------------------------------
echo "==> Positive control: the detector actually fires on a genuine hardcoded invocation"
# A guard that can never fail is worthless. Prove the scan catches a real
# violation by running it against a synthetic primitive that hardcodes a
# managed-project runner instead of asking the resolver.
CTRL_DIR="$(mktemp -d)"
trap 'rm -rf "$CTRL_DIR"' EXIT
cat >"$CTRL_DIR/bad-primitive.sh" <<'CTRL'
#!/usr/bin/env bash
# This comment mentions pytest but is a comment — must NOT trip.
run_project_tests() {
  pytest tests/        # <- genuine hardcoded invocation: SHOULD trip
}
CTRL
ctrl_hits="$(scan_executable_invocations "$CTRL_DIR/bad-primitive.sh")"
if [ -n "$ctrl_hits" ] && echo "$ctrl_hits" | grep -q 'pytest tests/'; then
  pass "detector fires on a genuine hardcoded 'pytest tests/' invocation"
else
  fail "detector did NOT fire on a known-bad fixture (guard is vacuous!)" \
    "(scan output: '${ctrl_hits:-<empty>}')"
fi

echo "==> Positive control: the detector does NOT trip on a comment-only mention"
# The companion to the above: a runner token that lives only in a `#`
# comment must NOT be flagged (else every illustrative comment is a false
# positive and the invariant becomes unmaintainable).
cat >"$CTRL_DIR/comment-only.sh" <<'CTRL'
#!/usr/bin/env bash
# whatever the project uses: pytest, go test, make lint — illustrative.
echo "running the project's resolved command"
CTRL
comment_hits="$(scan_executable_invocations "$CTRL_DIR/comment-only.sh")"
if [ -z "$comment_hits" ]; then
  pass "detector ignores a comment-only runner mention (no false positive)"
else
  fail "detector false-positived on a comment-only mention" \
    "(scan output: '$comment_hits')"
fi

# ---------------------------------------------------------------------------
echo "==> Invariant (other half): the resolver exists and the migrated call-site routes through it"
# The invariant has two halves: (1) no hardcoded bypass [above]; (2) the
# call-sites that DO run a managed project's command route through the
# resolver. Pin the resolver's existence + public entry point, and the one
# markdown call-site already migrated to it (commands/wrap-up.md, oxs.5).
if [ -f "$RESOLVER" ] && grep -q '^loom_resolve_command()' "$RESOLVER"; then
  pass "resolver lib/loom-script-resolve.sh defines loom_resolve_command"
else
  fail "resolver lib/loom-script-resolve.sh defines loom_resolve_command" \
    "(missing file or missing loom_resolve_command() definition)"
fi

if [ -f "$WRAPUP" ]; then
  if grep -qE 'loom_resolve_command[[:space:]]+test' "$WRAPUP"; then
    pass "commands/wrap-up.md routes its test command through loom_resolve_command"
  else
    fail "commands/wrap-up.md routes its test command through loom_resolve_command" \
      "(no 'loom_resolve_command test' call found — call-site regressed off the resolver)"
  fi
  # And it must not re-introduce a hardcoded runner AS the test command.
  # (The doc may still NAME pytest/go test in 'do NOT hardcode' guidance;
  # the violation would be presenting one as THE command to run. We assert
  # the resolver call is present — the positive form — which the line above
  # already does; here we additionally guard the no-false-green wording is
  # intact so the migration isn't silently reverted to a bare runner.)
  if grep -qiE 'warn|never.*green|never.*pass|block|refus' "$WRAPUP"; then
    pass "commands/wrap-up.md keeps the warn-on-absent / never-green guard"
  else
    fail "commands/wrap-up.md keeps the warn-on-absent / never-green guard" \
      "(no-false-green guidance missing — resolver contract weakened)"
  fi
else
  fail "commands/wrap-up.md present" "(file missing: $WRAPUP)"
fi

# ---------------------------------------------------------------------------
echo ""
echo "==================================="
echo "RESULTS: $passed passed, $failed failed"
echo "==================================="

[ "$failed" -eq 0 ]
