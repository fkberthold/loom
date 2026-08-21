#!/usr/bin/env bash
# Fixture tests for lib/loom-wing-resolve.sh (loom-pc3x, loom-kpke).
#
# loom-pc3x's RED invariant: every site that derives a project's
# MemPalace wing reads it from ONE declared source; no two sites can
# disagree for the same project. The implementation of "one source" is a
# SHARED resolver, not the same chain pasted at each call site — so this
# file tests the resolver, and then tests that both call sites go
# through it.
#
# THE CHAIN (decided by Frank 2026-08-21 and amended the same day, both
# recorded on loom-pc3x):
#
#   1. explicit --wing flag
#   2. <root>/mempalace.yaml              wing:
#   3. .claude/project-constitution.md    wing:
#   4. basename $root
#   5. bd id prefix
#
# Rung 2 outranks rung 3 because mempalace.yaml is MemPalace's own
# declaration and already carries wing plus rooms. Rung 3 exists so the
# repos that already carry a constitution resolve without anyone writing
# a new file.
#
# A per-rung test is not enough, and this file's own history is the
# reason. The part a per-rung test misses is the ORDER, so every
# adjacent pair below gets a fixture carrying BOTH sources with
# DIFFERENT values, and asserts the higher rung wins. When rungs 4 and 5
# swapped, the pair tests are what moved.
#
# Rung 4 takes `basename $root` and always answers, so the chain does
# not reach rung 5 while a root is in hand. Section 2 pins that
# non-firing. See the WHY THE BASENAME OUTRANKS THE BD PREFIX note in
# lib/loom-wing-resolve.sh for the measurement behind the order.
#
# Run:  bash lib/tests/loom-wing-resolve.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export LOOM_TEST_LIB_DIR="$LOOM_ROOT/lib"
LIB="$LOOM_ROOT/lib/loom-wing-resolve.sh"
AUDIT="$LOOM_ROOT/scripts/loom-audit-resolve"
MINE="$LOOM_ROOT/scripts/loom-mine-history"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# Read one key's value from a key=value stdout block.
val() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -1; }

# --- fixture builder -------------------------------------------------
#
#   mk_root <basename> <mempalace_wing|-> <constitution_wing|-> <bd_first_id|->
#
# Any argument given as `-` omits that source. Echoes the project root.
mk_root() {
  local base="$1" mp="$2" con="$3" bdid="$4"
  local work proj
  work=$(mktemp -d) || { echo "FATAL: mktemp failed" >&2; return 1; }
  case "$work" in /tmp/*) : ;; *) echo "FATAL: mktemp gave unsafe dir '$work'" >&2; return 1 ;; esac
  proj="$work/$base"
  mkdir -p "$proj"

  if [ "$mp" != "-" ]; then
    {
      printf 'wing: %s\n' "$mp"
      printf 'rooms:\n'
      printf '  - name: decisions\n'
      printf '    description: Decision drawers\n'
      printf '    keywords:\n'
      printf '      - decision\n'
    } > "$proj/mempalace.yaml"
  fi

  if [ "$con" != "-" ]; then
    mkdir -p "$proj/.claude"
    {
      printf -- '---\n'
      printf 'shell:\n  enter: ""\n  run_prefix: ""\n'
      printf 'package_manager: none\n'
      printf 'language:\n  runtime: bash\n  version: ""\n'
      printf 'wing: %s\n' "$con"
      printf 'canonical_commands:\n  build: ""\n  test: ""\n  lint: ""\n  gen: ""\n  dev: ""\n'
      printf -- '---\n'
      printf '\n# %s — project constitution\n' "$base"
    } > "$proj/.claude/project-constitution.md"
  fi

  if [ "$bdid" != "-" ]; then
    mkdir -p "$proj/.beads"
    printf '{"id":"%s","title":"seed","status":"open"}\n' "$bdid" > "$proj/.beads/issues.jsonl"
  fi

  echo "$proj"
}

# Safe cleanup: remove the mktemp dir holding $proj (exactly one level
# up), refusing anything not under /tmp.
cleanup_root() {
  local proj="$1" work
  [ -n "$proj" ] || return 0
  work=$(dirname "$proj")
  case "$work" in
    /tmp/*) rm -rf "$work" ;;
    *) echo "REFUSE: cleanup target '$work' not under /tmp" >&2 ;;
  esac
}

# Resolve through the CLI; echo the two key=value lines.
res() { bash "$LIB" "$@" 2>&1; }

# =====================================================================
# 0. Shape: the lib exists, is sourceable, and defines the contract.
# =====================================================================
echo "==> 0. resolver shape"
if [ -f "$LIB" ]; then pass "lib/loom-wing-resolve.sh exists"; else fail "lib/loom-wing-resolve.sh missing"; fi

# shellcheck disable=SC1090  # $LIB is the file under test, resolved at runtime
if [ -f "$LIB" ] && ( . "$LIB" >/dev/null 2>&1 ); then
  pass "lib sources cleanly (no side effects on source)"
else
  fail "lib does not source cleanly"
fi

for fn in loom_wing_resolve loom_wing_resolve_kv loom_wing_from_mempalace_yaml \
          loom_wing_from_constitution loom_wing_from_bd_prefix; do
  # shellcheck disable=SC1090  # $LIB is the file under test, resolved at runtime
  if [ -f "$LIB" ] && ( . "$LIB" >/dev/null 2>&1; declare -F "$fn" >/dev/null 2>&1 ); then
    pass "sourcing defines $fn"
  else
    fail "sourcing does not define $fn"
  fi
done

# =====================================================================
# 1. RUNG 4 — basename VERBATIM (no _<->- substitution, no case-fold).
#    This is the pre-existing behavior of both call sites and must be
#    preserved for every project that declares nothing.
# =====================================================================
echo "==> 1. rung 4 — basename verbatim"

PROJ=$(mk_root golden-path - - -)
out=$(res --root "$PROJ")
if [ "$(val "$out" wing)" = "golden-path" ]; then
  pass "dash basename preserved verbatim (golden-path)"
else
  fail "dash basename not verbatim" "got '$(val "$out" wing)' want 'golden-path'"
fi
if [ "$(val "$out" wing_source)" = "basename" ]; then
  pass "wing_source=basename when nothing is declared"
else
  fail "wing_source wrong for rung 4" "got '$(val "$out" wing_source)'"
fi
cleanup_root "$PROJ"

PROJ=$(mk_root liza_base - - -)
out=$(res --root "$PROJ")
if [ "$(val "$out" wing)" = "liza_base" ]; then
  pass "underscore basename preserved verbatim (liza_base)"
else
  fail "underscore basename not verbatim" "got '$(val "$out" wing)'"
fi
cleanup_root "$PROJ"

PROJ=$(mk_root MyProj_Repo - - -)
out=$(res --root "$PROJ")
if [ "$(val "$out" wing)" = "MyProj_Repo" ]; then
  pass "basename not case-folded (MyProj_Repo)"
else
  fail "basename case-folded" "got '$(val "$out" wing)'"
fi
cleanup_root "$PROJ"

# =====================================================================
# 2. RUNG 5 — bd id prefix.
#
#    The 2026-08-21 amendment put the basename above this rung, so with
#    a root in hand the chain answers at rung 4 and never gets here.
#    That is the point of the demotion, so the tests below pin the
#    NON-firing: every call shape a caller can use still resolves to the
#    directory name. The detection machinery is exercised directly
#    through loom_wing_from_bd_prefix, which stays exported for the
#    caller that builds its own candidate list (loom-qw9i).
# =====================================================================
echo "==> 2. rung 5 — bd id prefix"

PROJ=$(mk_root dreamer-engine - - dream-boc)

# The fixture carries BOTH a bd tracker and a plain directory name.
# This is the case the amendment turns on: prefix `dream` names an
# empty wing, `dreamer-engine` names the live one.
for shape in "--bd-prefix dream" "--bd-prefix auto" ""; do
  # shellcheck disable=SC2086  # $shape is a deliberate word-split call shape
  out=$(res --root "$PROJ" $shape)
  label="${shape:-no flag}"
  if [ "$(val "$out" wing)" = "dreamer-engine" ]; then
    pass "bd prefix does not beat the basename ($label)"
  else
    fail "bd prefix beat the basename ($label)" "got '$(val "$out" wing)' want 'dreamer-engine'"
  fi
  if [ "$(val "$out" wing_source)" = "basename" ]; then
    pass "wing_source=basename ($label)"
  else
    fail "wing_source wrong ($label)" "got '$(val "$out" wing_source)'"
  fi
done

# --bd-prefix stays a valid flag. A caller that hands one in must not
# get an argument error for it (hooks/bd-close-capture.sh, loom-qw9i).
out=$(res --root "$PROJ" --bd-prefix dream 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "--bd-prefix is still accepted (exit 0)"
else
  fail "--bd-prefix rejected" "rc=$rc: $out"
fi

# Rung 5's own detection, called directly. This is how a caller reaches
# the prefix now that the chain ranks it last.
# shellcheck disable=SC1090  # $LIB is the file under test, resolved at runtime
detected=$( . "$LIB" >/dev/null 2>&1; loom_wing_from_bd_prefix "$PROJ" 2>/dev/null )
if [ "$detected" = "dream" ]; then
  pass "loom_wing_from_bd_prefix reads the prefix from .beads/issues.jsonl"
else
  fail "loom_wing_from_bd_prefix did not detect the prefix" "got '$detected' want 'dream'"
fi
cleanup_root "$PROJ"

# No tracker: the detection returns rc 1 rather than an empty wing, and
# the chain still answers from the basename.
PROJ=$(mk_root plainrepo - - -)
# shellcheck disable=SC1090  # $LIB is the file under test, resolved at runtime
( . "$LIB" >/dev/null 2>&1; loom_wing_from_bd_prefix "$PROJ" >/dev/null 2>&1 ); rc=$?
if [ "$rc" -ne 0 ]; then
  pass "loom_wing_from_bd_prefix returns rc 1 with no .beads present"
else
  fail "loom_wing_from_bd_prefix returned rc 0 with no .beads present"
fi
out=$(res --root "$PROJ" --bd-prefix auto)
if [ "$(val "$out" wing)" = "plainrepo" ]; then
  pass "--bd-prefix auto with no .beads still resolves to the basename"
else
  fail "--bd-prefix auto did not resolve to the basename" "got '$(val "$out" wing)'"
fi
cleanup_root "$PROJ"

# =====================================================================
# 3. RUNG 3 — .claude/project-constitution.md front-matter wing:.
# =====================================================================
echo "==> 3. rung 3 — constitution wing:"

PROJ=$(mk_root somerepo - declared_wing -)
out=$(res --root "$PROJ")
if [ "$(val "$out" wing)" = "declared_wing" ]; then
  pass "constitution wing: beats the basename"
else
  fail "constitution wing: ignored" "got '$(val "$out" wing)' want 'declared_wing'"
fi
if [ "$(val "$out" wing_source)" = "constitution" ]; then
  pass "wing_source=constitution for rung 3"
else
  fail "wing_source wrong for rung 3" "got '$(val "$out" wing_source)'"
fi
cleanup_root "$PROJ"

# A constitution with NO wing: key falls through — the seven repos that
# carry one today declare no wing, and must keep resolving as before.
PROJ=$(mk_root somerepo - - -)
mkdir -p "$PROJ/.claude"
printf -- '---\npackage_manager: none\n---\n\nbody\n' > "$PROJ/.claude/project-constitution.md"
out=$(res --root "$PROJ")
if [ "$(val "$out" wing)" = "somerepo" ]; then
  pass "constitution without a wing: key falls through to basename"
else
  fail "wingless constitution did not fall through" "got '$(val "$out" wing)'"
fi
cleanup_root "$PROJ"

# A `wing:` in the PROSE BODY is not front-matter and must not win.
PROJ=$(mk_root somerepo - - -)
mkdir -p "$PROJ/.claude"
printf -- '---\npackage_manager: none\n---\n\n## Notes\n\nwing: bogus_body_wing\n' \
  > "$PROJ/.claude/project-constitution.md"
out=$(res --root "$PROJ")
if [ "$(val "$out" wing)" = "somerepo" ]; then
  pass "wing: in the prose body is ignored (front-matter only)"
else
  fail "prose-body wing: was read as front-matter" "got '$(val "$out" wing)'"
fi
cleanup_root "$PROJ"

# =====================================================================
# 4. RUNG 2 — <root>/mempalace.yaml wing:.
#    This is loom-kpke's defect: both call sites ignored this file.
#
#    Rung 2 trusts the descriptor, so a wrong descriptor now decides.
#    Measured 2026-08-20 over the 2 repos that carry a mempalace.yaml,
#    it flips one answer each way:
#
#      tla-puzzles           declares tla_puzzles         → 932 drawers
#      malleus-protocollum   declares malleus_protocollum → 0 drawers
#
#    malleus-protocollum's 978 drawers sit under the hyphen spelling,
#    which is what the basename rung was already giving. Its descriptor
#    is wrong, and the one-line fix belongs in that repo rather than in
#    a special case here. /audit-project Step 1b's wing-variant WARN is
#    the live backstop, and it still fires because no --wing is passed.
# =====================================================================
echo "==> 4. rung 2 — mempalace.yaml wing:"

PROJ=$(mk_root tla-puzzles tla_puzzles - -)
out=$(res --root "$PROJ")
if [ "$(val "$out" wing)" = "tla_puzzles" ]; then
  pass "mempalace.yaml wing: beats the basename (loom-kpke's case)"
else
  fail "mempalace.yaml ignored" "got '$(val "$out" wing)' want 'tla_puzzles'"
fi
if [ "$(val "$out" wing_source)" = "mempalace_yaml" ]; then
  pass "wing_source=mempalace_yaml for rung 2"
else
  fail "wing_source wrong for rung 2" "got '$(val "$out" wing_source)'"
fi
cleanup_root "$PROJ"

# Parser robustness: quoted value, trailing comment, and a NESTED
# `wing:` (indented, under rooms:) which must not be mistaken for the
# top-level key.
PROJ=$(mk_root somerepo - - -)
printf 'rooms:\n  - name: decisions\n    wing: nested_should_lose\nwing: "quoted_wing"   # the live wing\n' \
  > "$PROJ/mempalace.yaml"
out=$(res --root "$PROJ")
if [ "$(val "$out" wing)" = "quoted_wing" ]; then
  pass "quotes stripped, trailing comment stripped, nested wing: ignored"
else
  fail "mempalace.yaml parse wrong" "got '$(val "$out" wing)' want 'quoted_wing'"
fi
cleanup_root "$PROJ"

# An EMPTY wing: value must fall through, not resolve to the empty wing.
PROJ=$(mk_root somerepo - - -)
printf 'wing:\nrooms: []\n' > "$PROJ/mempalace.yaml"
out=$(res --root "$PROJ")
if [ "$(val "$out" wing)" = "somerepo" ]; then
  pass "empty mempalace.yaml wing: falls through to basename"
else
  fail "empty wing: did not fall through" "got '$(val "$out" wing)'"
fi
cleanup_root "$PROJ"

# =====================================================================
# 5. RUNG 1 — explicit --wing beats everything below it.
# =====================================================================
echo "==> 5. rung 1 — explicit --wing"

PROJ=$(mk_root somerepo yaml_wing con_wing pre-abc)
out=$(res --root "$PROJ" --wing flag_wing --bd-prefix auto)
if [ "$(val "$out" wing)" = "flag_wing" ]; then
  pass "--wing beats mempalace.yaml + constitution + bd prefix"
else
  fail "--wing did not win" "got '$(val "$out" wing)' want 'flag_wing'"
fi
if [ "$(val "$out" wing_source)" = "flag" ]; then
  pass "wing_source=flag for rung 1"
else
  fail "wing_source wrong for rung 1" "got '$(val "$out" wing_source)'"
fi
cleanup_root "$PROJ"

# =====================================================================
# 6. PRECEDENCE between adjacent rungs — the part a per-rung test
#    misses. Each fixture carries BOTH sources with DIFFERENT values.
# =====================================================================
echo "==> 6. precedence between rungs"

# 2 over 3 — THE DECIDING PAIR. mempalace.yaml is MemPalace's own
# declaration, so it outranks the constitution.
PROJ=$(mk_root somerepo yaml_wing con_wing -)
out=$(res --root "$PROJ")
if [ "$(val "$out" wing)" = "yaml_wing" ]; then
  pass "rung 2 > rung 3: mempalace.yaml beats the constitution"
else
  fail "rung 2 did NOT beat rung 3" "got '$(val "$out" wing)' want 'yaml_wing'"
fi
cleanup_root "$PROJ"

# 3 over 4 — a declared constitution wing beats the basename. The
# fixture also carries a bd tracker, so this pins 3 over 5 at once.
PROJ=$(mk_root somerepo - con_wing pre-abc)
out=$(res --root "$PROJ" --bd-prefix auto)
if [ "$(val "$out" wing)" = "con_wing" ]; then
  pass "rung 3 > rung 4: constitution beats the basename"
else
  fail "rung 3 did NOT beat rung 4" "got '$(val "$out" wing)' want 'con_wing'"
fi
cleanup_root "$PROJ"

# 4 over 5 — the basename beats the bd prefix. THE AMENDED PAIR, and
# the one an ordering flip breaks first. Both call shapes, because a
# caller can hand the prefix in or ask for detection.
PROJ=$(mk_root dreamer-engine - - dream-boc)
for shape in "--bd-prefix dream" "--bd-prefix auto"; do
  # shellcheck disable=SC2086  # $shape is a deliberate word-split call shape
  out=$(res --root "$PROJ" $shape)
  if [ "$(val "$out" wing)" = "dreamer-engine" ]; then
    pass "rung 4 > rung 5: basename beats the bd prefix ($shape)"
  else
    fail "rung 4 did NOT beat rung 5 ($shape)" "got '$(val "$out" wing)' want 'dreamer-engine'"
  fi
done
cleanup_root "$PROJ"

# 2 over 5 — non-adjacent, and the shape loom-kpke actually hit:
# tla-puzzles carries mempalace.yaml AND a `tla-` bd prefix.
PROJ=$(mk_root tla-puzzles tla_puzzles - tla-033u)
out=$(res --root "$PROJ" --bd-prefix auto)
if [ "$(val "$out" wing)" = "tla_puzzles" ]; then
  pass "rung 2 > rung 5: mempalace.yaml beats the bd prefix (tla-puzzles shape)"
else
  fail "rung 2 did NOT beat rung 5" "got '$(val "$out" wing)' want 'tla_puzzles'"
fi
cleanup_root "$PROJ"

# All five present at once: the top rung wins, and the chain does not
# accidentally concatenate or fall through.
PROJ=$(mk_root basename_wing yaml_wing con_wing pre-abc)
out=$(res --root "$PROJ" --bd-prefix auto)
if [ "$(val "$out" wing)" = "yaml_wing" ]; then
  pass "all four lower sources present → rung 2 wins"
else
  fail "full-chain resolution wrong" "got '$(val "$out" wing)' want 'yaml_wing'"
fi
cleanup_root "$PROJ"

# =====================================================================
# 7. Root resolution + error shape (parity with loom-audit-resolve).
# =====================================================================
echo "==> 7. root resolution + errors"

out=$(res --root /no/such/dir/xyzzy 2>&1); rc=$?
if [ "$rc" -eq 2 ]; then pass "nonexistent --root → exit 2"; else fail "nonexistent --root rc=$rc (want 2)" "$out"; fi

out=$(res --bogus-flag 2>&1); rc=$?
if [ "$rc" -eq 2 ]; then pass "unrecognized flag → exit 2"; else fail "bad flag rc=$rc (want 2)" "$out"; fi

# =====================================================================
# 8. CALL SITE — scripts/loom-audit-resolve goes through the resolver.
# =====================================================================
echo "==> 8. call site: scripts/loom-audit-resolve"

PROJ=$(mk_root tla-puzzles tla_puzzles - -)
out=$("$AUDIT" --root "$PROJ" 2>&1)
if [ "$(val "$out" wing)" = "tla_puzzles" ]; then
  pass "loom-audit-resolve reads mempalace.yaml (was: basename verbatim)"
else
  fail "loom-audit-resolve still ignores mempalace.yaml" "got '$(val "$out" wing)' want 'tla_puzzles'"
fi
cleanup_root "$PROJ"

PROJ=$(mk_root somerepo yaml_wing con_wing -)
out=$("$AUDIT" --root "$PROJ" 2>&1)
if [ "$(val "$out" wing)" = "yaml_wing" ]; then
  pass "loom-audit-resolve honors rung 2 > rung 3"
else
  fail "loom-audit-resolve precedence wrong" "got '$(val "$out" wing)'"
fi
out=$("$AUDIT" --root "$PROJ" --wing override_wing 2>&1)
if [ "$(val "$out" wing)" = "override_wing" ]; then
  pass "loom-audit-resolve --wing still wins (rung 1)"
else
  fail "loom-audit-resolve --wing override broken" "got '$(val "$out" wing)'"
fi
cleanup_root "$PROJ"

# Regression guard: a project declaring nothing still resolves to the
# basename, verbatim.
PROJ=$(mk_root golden-path - - -)
out=$("$AUDIT" --root "$PROJ" 2>&1)
if [ "$(val "$out" wing)" = "golden-path" ]; then
  pass "loom-audit-resolve unchanged for undeclared projects"
else
  fail "loom-audit-resolve regressed the basename default" "got '$(val "$out" wing)'"
fi
cleanup_root "$PROJ"

# =====================================================================
# 9. CALL SITE — scripts/loom-mine-history goes through the resolver.
# =====================================================================
echo "==> 9. call site: scripts/loom-mine-history"

mk_git_root() {
  local base="$1" mp="$2"
  local proj
  proj=$(mk_root "$base" "$mp" - -) || return 1
  (
    cd "$proj" || exit 1
    git init -q -b main
    git config user.email wing@test
    git config user.name "Wing Test"
    echo base > README.md
    git add -A
    git -c core.hooksPath=/dev/null commit -q -m "initial"
  ) >/dev/null 2>&1 || return 1
  echo "$proj"
}

STUBS=$(mktemp -d)
cat > "$STUBS/gh" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  auth) exit 1 ;;
  pr)   echo "[]" ;;
  *)    exit 1 ;;
esac
EOF
cat > "$STUBS/claude" <<'EOF'
#!/usr/bin/env bash
echo '{"salient":false}'
EOF
chmod +x "$STUBS/gh" "$STUBS/claude"

PROJ=$(mk_git_root tla-puzzles tla_puzzles)
out=$(PATH="$STUBS:$PATH" bash "$MINE" --root "$PROJ" --dry-run 2>&1)
if printf '%s' "$out" | grep -q "(wing for filing: tla_puzzles)"; then
  pass "loom-mine-history reads mempalace.yaml (was: basename verbatim)"
else
  fail "loom-mine-history still ignores mempalace.yaml" "$out"
fi

out=$(PATH="$STUBS:$PATH" bash "$MINE" --root "$PROJ" --wing override_wing --dry-run 2>&1)
if printf '%s' "$out" | grep -q "(wing for filing: override_wing)"; then
  pass "loom-mine-history --wing still wins (rung 1)"
else
  fail "loom-mine-history --wing override broken" "$out"
fi
cleanup_root "$PROJ"

PROJ=$(mk_git_root e2e-api-tests -)
out=$(PATH="$STUBS:$PATH" bash "$MINE" --root "$PROJ" --dry-run 2>&1)
if printf '%s' "$out" | grep -q "(wing for filing: e2e-api-tests)"; then
  pass "loom-mine-history unchanged for undeclared projects (dash verbatim)"
else
  fail "loom-mine-history regressed the basename default" "$out"
fi
cleanup_root "$PROJ"

# =====================================================================
# 10. loom-kpke second defect — the `mined_from` KG object must be the
#     resolved WING, not a machine-local absolute path.
#
#     skills/loom-mine-history/SKILL.md step 4d says the repo entity IS
#     the resolved wing; the engine was emitting `$repo`. One mine wrote
#     two different entities for the same repo, and the path one breaks
#     when the checkout moves.
# =====================================================================
echo "==> 10. mined_from object is the wing, not a path"

SALIENT=$(mktemp)
printf '%s' '{"salient":true,"verbatim":"v","synthesis":"s","decision":"single-table schema"}' > "$SALIENT"
cat > "$STUBS/claude" <<'EOF'
#!/usr/bin/env bash
if [ -n "${CLAUDE_REPLY_FILE:-}" ] && [ -f "$CLAUDE_REPLY_FILE" ]; then
  cat "$CLAUDE_REPLY_FILE"
else
  echo '{"salient":false}'
fi
EOF
chmod +x "$STUBS/claude"

mk_minable_root() {
  local base="$1" mp="$2"
  local proj
  proj=$(mk_root "$base" "$mp" - -) || return 1
  (
    cd "$proj" || exit 1
    git init -q -b main
    git config user.email wing@test
    git config user.name "Wing Test"
    echo base > README.md
    git add -A
    git -c core.hooksPath=/dev/null commit -q -m "initial"
    cat > schema.sql <<'SQL'
CREATE TABLE decisions (id INT PRIMARY KEY, body TEXT);
SQL
    git add -A
    git -c core.hooksPath=/dev/null commit -q -m "Add decisions schema

We chose a single-table design over the EAV pattern because query
latency on the decision timeline dominates; normalized EAV would
require N joins per timeline render. Trade-off accepted."
  ) >/dev/null 2>&1 || return 1
  echo "$proj"
}

PROJ=$(mk_minable_root tla-puzzles tla_puzzles)
OUT=$(mktemp -d)
out=$(PATH="$STUBS:$PATH" GH_AUTH_OK=0 CLAUDE_REPLY_FILE="$SALIENT" \
      bash "$MINE" --root "$PROJ" --out "$OUT" --model fake 2>&1)
triples="$OUT/kg-triples.jsonl"

if [ -s "$triples" ]; then
  pass "real pass emitted kg-triples.jsonl"
else
  fail "no kg triples emitted" "$out"
fi

mf_obj=$(grep '"predicate":"mined_from"' "$triples" 2>/dev/null | head -1 \
  | sed -n 's/.*"object":"\([^"]*\)".*/\1/p')
if [ "$mf_obj" = "tla_puzzles" ]; then
  pass "mined_from object is the resolved wing (tla_puzzles)"
else
  fail "mined_from object is not the resolved wing" "got '$mf_obj' want 'tla_puzzles'"
fi

case "$mf_obj" in
  /*) fail "mined_from object is a machine-local absolute path" "$mf_obj" ;;
  *)  pass "mined_from object is not an absolute path" ;;
esac

# The wing the wrapper writes to <out>/wing and the wing the triples
# carry must be the SAME string — that identity is what closes the
# step-0 / step-4d watermark round-trip in the skill.
wing_file=$(cat "$OUT/wing" 2>/dev/null)
if [ -n "$wing_file" ] && [ "$wing_file" = "$mf_obj" ]; then
  pass "<out>/wing and the mined_from object agree"
else
  fail "<out>/wing and mined_from disagree" "wing=$wing_file mined_from=$mf_obj"
fi
rm -rf "$OUT"
cleanup_root "$PROJ"

# Undeclared project: mined_from falls back to the basename wing, still
# not a path.
PROJ=$(mk_minable_root e2e-api-tests -)
OUT=$(mktemp -d)
out=$(PATH="$STUBS:$PATH" GH_AUTH_OK=0 CLAUDE_REPLY_FILE="$SALIENT" \
      bash "$MINE" --root "$PROJ" --out "$OUT" --model fake 2>&1)
mf_obj=$(grep '"predicate":"mined_from"' "$OUT/kg-triples.jsonl" 2>/dev/null | head -1 \
  | sed -n 's/.*"object":"\([^"]*\)".*/\1/p')
if [ "$mf_obj" = "e2e-api-tests" ]; then
  pass "mined_from falls back to the basename wing for undeclared projects"
else
  fail "mined_from fallback wrong" "got '$mf_obj' want 'e2e-api-tests'"
fi
rm -rf "$OUT"
cleanup_root "$PROJ"
rm -f "$SALIENT"
rm -rf "$STUBS"

# =====================================================================
# 11. The constitution schema + field reference document `wing`.
# =====================================================================
echo "==> 11. schema + docs carry the wing field"

SCHEMA="$LOOM_ROOT/references/project-constitution.schema.json"
DOC="$LOOM_ROOT/docs/reference/project-constitution.md"

if grep -q '"wing"' "$SCHEMA" 2>/dev/null; then
  pass "schema declares a wing property"
else
  fail "schema has no wing property (additionalProperties:false rejects it)"
fi

if grep -q '^### `wing`' "$DOC" 2>/dev/null; then
  pass "field reference documents wing"
else
  fail "docs/reference/project-constitution.md does not document wing"
fi

# `wing` must be OPTIONAL — the seven repos carrying a constitution
# today declare none, and none of them has to move.
if python3 - "$SCHEMA" <<'PY' >/dev/null 2>&1
import json, sys
s = json.load(open(sys.argv[1]))
assert "wing" in s["properties"], "no wing property"
assert "wing" not in s.get("required", []), "wing is required"
PY
then
  pass "schema wing is optional (not in required)"
else
  fail "schema wing is missing or wrongly required"
fi

# =====================================================================
# 12. END-TO-END against the real ~/repos/tla-puzzles checkout.
#     This is loom-kpke's literal acceptance criterion. It is the ONE
#     check in this file that depends on the real ~/repos layout, and
#     it SKIPS (rather than fails) when that checkout is absent.
# =====================================================================
echo "==> 12. end-to-end (real ~/repos/tla-puzzles — skipped if absent)"

REAL="$HOME/repos/tla-puzzles"
if [ -f "$REAL/mempalace.yaml" ]; then
  out=$("$AUDIT" --root "$REAL" 2>&1)
  if [ "$(val "$out" wing)" = "tla_puzzles" ]; then
    pass "E2E: loom-audit-resolve --root ~/repos/tla-puzzles → tla_puzzles"
  else
    fail "E2E: loom-audit-resolve wrong wing" "got '$(val "$out" wing)'"
  fi

  w=$(bash "$LIB" --root "$REAL" 2>&1 | sed -n 's/^wing=//p' | head -1)
  if [ "$w" = "tla_puzzles" ]; then
    pass "E2E: resolver --root ~/repos/tla-puzzles → tla_puzzles"
  else
    fail "E2E: resolver wrong wing" "got '$w'"
  fi
else
  echo "  SKIP: $REAL/mempalace.yaml not present on this machine"
fi

# =====================================================================
# Summary
# =====================================================================
echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
