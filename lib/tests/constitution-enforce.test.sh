#!/usr/bin/env bash
# Fixture tests for hooks/constitution-enforce.sh.
#
# Closes loom-8jz (feature): the narrow hard-enforcement hook. It is a
# PreToolUse hook on Bash only that walks up for
# .claude/project-constitution.md, parses its YAML front-matter via yq,
# matches the command against the forbidden / package_manager /
# run_prefix rules, and BLOCKS (exit 2) with a helpful suggestion.
#
# Distinct from the INFO/nudge hooks (constitution-surfacing,
# context-budget-sensor): this one HARD-BLOCKS. But it FAILS OPEN on
# every condition where it cannot prove a violation:
#   - absent constitution file   → exit 0 silent
#   - yq missing in PATH          → exit 0 with stderr warn
#   - malformed YAML              → exit 0 with stderr warn
#   - LOOM_CONSTITUTION_SKIP=1    → exit 0 (always bypass)
#
# Anchored-regex discipline (loom-9ng / loom-oq0s bug class): the hook
# matches command-SHAPE (argv tokens), not bare substrings. A substring
# like `tipping.py` must NOT trigger the bare-`python` rule.
#
# yq is NOT assumed installed in CI. The yq-present cases install a
# tiny stub `yq` on PATH (front-matter is well-formed; the stub does a
# real `yq`-style extraction of the keys the hook reads) so the parse
# path is exercised deterministically. The yq-missing case scrubs PATH.
#
# Run:  bash lib/tests/constitution-enforce.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$LOOM_ROOT/hooks/constitution-enforce.sh"

passed=0
failed=0
pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# The hook sources lib/loom-hook-helpers.sh; point it at the worktree's lib.
export LOOM_TEST_LIB_DIR="$LOOM_ROOT/lib"

# --- A real yq, if the host has one; else a stub on a temp PATH dir ----
# When the host has a real yq we just use it (most faithful). When it
# does not, we install a stub that satisfies the exact invocation shape
# the hook uses. The hook's contract is "use yq to read front-matter
# keys"; the stub honours that for our well-formed fixtures.
STUB_BIN=""
make_yq_stub() {
  # Creates a dir with a `yq` that reads the FRONT-MATTER (between the
  # first two `---` fences) of the file named in its last argument and
  # answers the dotted-path queries the hook issues. Returns the dir.
  local d; d=$(mktemp -d)
  cat >"$d/yq" <<'STUB'
#!/usr/bin/env bash
# Minimal yq stub for constitution-enforce tests. Supports:
#   yq -r '<.dotted.path>' <file>           → scalar
#   yq -r '<.array[]>' <file>               → newline-joined items
#   yq e '...' <file> / yq '...' <file>     → same
# Reads ONLY the YAML front-matter (first --- ... --- block) of <file>.
set -uo pipefail
args=("$@")
file="${args[${#args[@]}-1]}"
# Collect the expression: the last quoted-ish arg before the file.
expr=""
for ((i=0; i<${#args[@]}-1; i++)); do
  case "${args[$i]}" in
    -r|-e|e|-o=*|-N) : ;;
    *) expr="${args[$i]}" ;;
  esac
done
[ -f "$file" ] || { exit 0; }
# The hook slices the YAML front-matter out of the markdown file BEFORE
# calling yq, so by the time we're invoked $file is usually a bare,
# fence-less YAML document. But be robust to a fenced markdown file too:
# if a `---` fence is present, read only the block after the first one;
# otherwise treat the whole file as the YAML body.
if grep -q '^---[[:space:]]*$' "$file"; then
  fm=$(awk 'BEGIN{n=0} /^---[[:space:]]*$/{n++; next} n==1{print} n>=2{exit}' "$file")
else
  fm=$(cat "$file")
fi
# Malformed-marker: if the fixture deliberately broke YAML we emit the
# yq parse error to stderr and exit non-zero (mirrors real yq).
if printf '%s\n' "$fm" | grep -q '__MALFORMED_YAML__'; then
  echo "Error: bad YAML" >&2
  exit 1
fi
py() { python3 -c "$@"; }
FM="$fm" EXPR="$expr" python3 - <<'PY'
import os, sys, re
fm = os.environ["FM"]
expr = os.environ["EXPR"].strip()

# Hand-rolled tiny YAML reader good enough for the constitution shape:
# top-level scalars, nested one-level maps (shell:, language:,
# canonical_commands:), and top-level sequences (forbidden:,
# bypass_patterns:). Quotes stripped.
def strip_q(v):
    v = v.strip()
    if len(v) >= 2 and v[0] in "\"'" and v[-1] == v[0]:
        return v[1:-1]
    return v

scalars = {}      # "key" or "parent.key" -> value
seqs = {}         # "key" -> [items]
lines = fm.splitlines()
cur_parent = None
cur_seq = None
for raw in lines:
    if not raw.strip() or raw.lstrip().startswith("#"):
        continue
    indent = len(raw) - len(raw.lstrip())
    line = raw.strip()
    if line.startswith("- "):
        if cur_seq is not None:
            seqs.setdefault(cur_seq, []).append(strip_q(line[2:]))
        continue
    # key: value  OR  key:
    m = re.match(r"^([A-Za-z0-9_]+):\s*(.*)$", line)
    if not m:
        continue
    key, val = m.group(1), m.group(2)
    if indent == 0:
        cur_parent = None
        cur_seq = None
        if val == "":
            # could be a map parent or a sequence parent; remember name
            cur_parent = key
            cur_seq = key
            scalars.setdefault(key, "")
        else:
            scalars[key] = strip_q(val)
    else:
        # nested under cur_parent
        if cur_parent is not None:
            scalars[f"{cur_parent}.{key}"] = strip_q(val)

def lookup(path):
    p = path.lstrip(".")
    # array form  foo[]
    if p.endswith("[]"):
        name = p[:-2]
        return "\n".join(seqs.get(name, []))
    return scalars.get(p, "")

print(lookup(expr))
PY
STUB
  chmod +x "$d/yq"
  echo "$d"
}

# Resolve a PATH that has a working yq (real or stub) prepended.
yq_path() {
  if command -v yq >/dev/null 2>&1; then
    echo "$PATH"
  else
    [ -n "$STUB_BIN" ] || STUB_BIN=$(make_yq_stub)
    echo "$STUB_BIN:$PATH"
  fi
}

# --- Fixture project trees ---------------------------------------------
# A constitution.md with shell=devbox, pkg=pnpm. The hook should:
#   block bare `python`     → suggest `devbox run python`
#   allow `devbox run python`
#   allow `python --version`  (in bypass_patterns)
#   block `npm install`     → suggest `pnpm install`
#   allow `pnpm install`
#   NOT block `tipping.py`  (anchored-regex discipline)
mk_devbox_pnpm_project() {
  local d; d=$(mktemp -d)
  mkdir -p "$d/.claude"
  cat >"$d/.claude/project-constitution.md" <<'EOF'
---
shell:
  enter: "devbox shell"
  run_prefix: "devbox run"

package_manager: pnpm

language:
  runtime: python
  version: "3.13"

forbidden:
  - "npm install"
  - "yarn install"

canonical_commands:
  build: "devbox run build"
  test: "devbox run test"
  lint: ""
  gen: ""
  dev: ""

bypass_patterns:
  - "python --version"
---

# fixture constitution
EOF
  echo "$d"
}

mk_malformed_project() {
  local d; d=$(mktemp -d)
  mkdir -p "$d/.claude"
  cat >"$d/.claude/project-constitution.md" <<'EOF'
---
__MALFORMED_YAML__
shell: : : [ unbalanced
package_manager: pnpm
---

# malformed fixture
EOF
  echo "$d"
}

# --- Hook runner -------------------------------------------------------
#   run_hook <cwd> <command> [extra env assignments...]
# Returns hook's exit code in $rc; stdout+stderr captured in $out.
run_hook() {
  local cwd="$1" cmd="$2"; shift 2
  local payload
  payload=$(python3 -c '
import json, sys
print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))
' "$cmd")
  ( cd "$cwd" && env "$@" PATH="$(yq_path)" bash "$HOOK" <<<"$payload" 2>&1 )
}

# =====================================================================
echo "==> devbox/pnpm project: enforcement decisions"
P=$(mk_devbox_pnpm_project)

out=$(run_hook "$P" "python train.py"); rc=$?
if [ "$rc" -eq 2 ] && echo "$out" | grep -q 'devbox run python'; then
  pass "bare python blocked with 'devbox run python' suggestion"
else
  fail "bare python not blocked/suggested. rc=$rc" "$out"
fi

out=$(run_hook "$P" "devbox run python train.py"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "devbox run python allowed"
else
  fail "devbox run python blocked. rc=$rc" "$out"
fi

out=$(run_hook "$P" "python --version"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "python --version allowed via bypass_patterns"
else
  fail "python --version blocked despite bypass_patterns. rc=$rc" "$out"
fi

out=$(run_hook "$P" "npm install lodash"); rc=$?
if [ "$rc" -eq 2 ] && echo "$out" | grep -q 'pnpm install'; then
  pass "npm install blocked with 'pnpm install' suggestion"
else
  fail "npm install not blocked/suggested. rc=$rc" "$out"
fi

out=$(run_hook "$P" "pnpm install"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "pnpm install allowed"
else
  fail "pnpm install blocked. rc=$rc" "$out"
fi

# Anchored-regex discipline: a filename ending in .py must NOT match the
# bare-python rule (loom-9ng / loom-oq0s bug class).
out=$(run_hook "$P" "cat tipping.py"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "substring 'tipping.py' does NOT trigger python rule (anchored)"
else
  fail "false-positive: tipping.py triggered python rule. rc=$rc" "$out"
fi

# Anchored: a forbidden phrase appearing inside a quoted argument of a
# DIFFERENT command must not fire (sibling of the loom-oq0s class).
out=$(run_hook "$P" "git commit -m 'note: npm install is forbidden here'"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "'npm install' inside a quoted commit message does NOT fire"
else
  fail "false-positive: quoted 'npm install' blocked. rc=$rc" "$out"
fi
rm -rf "$P"

# =====================================================================
echo "==> bypass: LOOM_CONSTITUTION_SKIP=1 → exit 0"
P=$(mk_devbox_pnpm_project)
out=$(run_hook "$P" "npm install lodash" LOOM_CONSTITUTION_SKIP=1); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "LOOM_CONSTITUTION_SKIP=1 bypasses an otherwise-blocked command"
else
  fail "SKIP=1 did not bypass. rc=$rc" "$out"
fi
# Non-literal-1 does NOT bypass (loom-b1l literal-1 convention).
out=$(run_hook "$P" "npm install lodash" LOOM_CONSTITUTION_SKIP=yes); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "LOOM_CONSTITUTION_SKIP=yes does NOT bypass (literal-1 only)"
else
  fail "SKIP=yes wrongly bypassed. rc=$rc" "$out"
fi
rm -rf "$P"

# =====================================================================
echo "==> fail-open: no constitution file → exit 0 silent"
NC=$(mktemp -d)   # no .claude/project-constitution.md anywhere up-tree
out=$(run_hook "$NC" "npm install lodash"); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "no constitution → exit 0 AND silent"
else
  fail "no-constitution path not silent-allow. rc=$rc" "$out"
fi
rm -rf "$NC"

# =====================================================================
echo "==> fail-open: malformed YAML → exit 0 with stderr warn"
P=$(mk_malformed_project)
out=$(run_hook "$P" "npm install lodash"); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -qi 'constitution'; then
  pass "malformed YAML → exit 0 with a stderr warning"
else
  fail "malformed YAML not fail-open-with-warn. rc=$rc" "$out"
fi
rm -rf "$P"

# =====================================================================
echo "==> fail-open: yq missing in PATH → exit 0 with stderr warn"
P=$(mk_devbox_pnpm_project)
# Build a PATH that has NO yq: a scratch dir with only the coreutils the
# hook needs (sh, bash, python3, grep, sed, cat, awk, dirname, basename).
SCRUB=$(mktemp -d)
for b in bash sh python3 grep sed cat awk dirname basename env head tail cut sort tr realpath sha256sum mktemp; do
  src=$(command -v "$b" 2>/dev/null) && ln -sf "$src" "$SCRUB/$b"
done
payload=$(python3 -c '
import json
print(json.dumps({"tool_name":"Bash","tool_input":{"command":"npm install lodash"}}))')
out=$( cd "$P" && env -i HOME="$HOME" LOOM_TEST_LIB_DIR="$LOOM_TEST_LIB_DIR" PATH="$SCRUB" bash "$HOOK" <<<"$payload" 2>&1 ); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -qi 'yq'; then
  pass "yq missing → exit 0 with a stderr warning mentioning yq"
else
  fail "yq-missing not fail-open-with-warn. rc=$rc" "$out"
fi
rm -rf "$SCRUB" "$P"

# =====================================================================
echo "==> non-Bash tool → no-op"
P=$(mk_devbox_pnpm_project)
payload=$(python3 -c '
import json
print(json.dumps({"tool_name":"Edit","tool_input":{"file_path":"x.py"}}))')
out=$( cd "$P" && env PATH="$(yq_path)" bash "$HOOK" <<<"$payload" 2>&1 ); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "non-Bash tool: silent no-op"
else
  fail "non-Bash tool fired. rc=$rc" "$out"
fi
rm -rf "$P"

# =====================================================================
echo "==> cache survives an unchanged file (yq invoked at most once)"
# Wrap yq so each invocation appends a line to a counter file. Run the
# hook twice against the SAME unchanged constitution; the second run
# must NOT re-invoke yq (mtime-keyed cache hit).
P=$(mk_devbox_pnpm_project)
CACHE_DIR=$(mktemp -d)        # private XDG_RUNTIME_DIR for the cache
COUNT_DIR=$(mktemp -d)
COUNTER="$COUNT_DIR/yq.count"
: >"$COUNTER"
# A counting yq that delegates to the real/stub yq.
REAL_YQ_PATH=$(yq_path)
cat >"$COUNT_DIR/yq" <<EOF
#!/usr/bin/env bash
echo x >> "$COUNTER"
PATH="$REAL_YQ_PATH" exec yq "\$@"
EOF
chmod +x "$COUNT_DIR/yq"

payload=$(python3 -c '
import json
print(json.dumps({"tool_name":"Bash","tool_input":{"command":"pnpm run build"}}))')
# First run — should parse (≥1 yq call) and cache.
( cd "$P" && env XDG_RUNTIME_DIR="$CACHE_DIR" PATH="$COUNT_DIR:$REAL_YQ_PATH" bash "$HOOK" <<<"$payload" >/dev/null 2>&1 )
after_first=$(wc -l <"$COUNTER")
# Second run, file unchanged — should hit cache (no new yq calls).
( cd "$P" && env XDG_RUNTIME_DIR="$CACHE_DIR" PATH="$COUNT_DIR:$REAL_YQ_PATH" bash "$HOOK" <<<"$payload" >/dev/null 2>&1 )
after_second=$(wc -l <"$COUNTER")
if [ "$after_first" -ge 1 ] && [ "$after_second" -eq "$after_first" ]; then
  pass "cache hit on unchanged file: yq not re-invoked ($after_first → $after_second)"
else
  fail "cache did not prevent re-parse ($after_first → $after_second)"
fi

# Touching the file (mtime bump) must invalidate the cache → re-parse.
sleep 1; touch "$P/.claude/project-constitution.md"
( cd "$P" && env XDG_RUNTIME_DIR="$CACHE_DIR" PATH="$COUNT_DIR:$REAL_YQ_PATH" bash "$HOOK" <<<"$payload" >/dev/null 2>&1 )
after_touch=$(wc -l <"$COUNTER")
if [ "$after_touch" -gt "$after_second" ]; then
  pass "mtime bump invalidates cache → re-parse ($after_second → $after_touch)"
else
  fail "mtime bump did NOT invalidate cache ($after_second → $after_touch)"
fi
rm -rf "$P" "$CACHE_DIR" "$COUNT_DIR"

# =====================================================================
echo "==> settings.snippet.json wires the hook into the Bash chain (additive)"
SNIP="$LOOM_ROOT/settings.snippet.json"
# Assert: constitution-enforce.sh IS in the PreToolUse Bash chain AND a
# pre-existing sibling (context-budget-sensor.sh) is still present — so
# the wiring is additive, not a replacement. jq if present; python else.
chain_has() {
  local needle="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -e --arg n "$needle" '
      .hooks.PreToolUse[] | select(.matcher=="Bash") | .hooks[]
      | select(.command | test($n))' "$SNIP" >/dev/null 2>&1
  else
    SNIP="$SNIP" N="$needle" python3 -c '
import json, os, sys, re
s = json.load(open(os.environ["SNIP"]))
needle = os.environ["N"]
for m in s["hooks"]["PreToolUse"]:
    if m.get("matcher") == "Bash":
        for h in m["hooks"]:
            if re.search(needle, h.get("command", "")):
                sys.exit(0)
sys.exit(1)'
  fi
}
if chain_has "constitution-enforce.sh" && chain_has "context-budget-sensor.sh"; then
  pass "snippet registers constitution-enforce.sh AND keeps context-budget-sensor.sh (additive)"
else
  fail "settings.snippet.json missing constitution-enforce.sh in Bash chain (or dropped a sibling)"
fi

# =====================================================================
echo "==> reference doc exists and is registered in mkdocs nav"
DOC="$LOOM_ROOT/docs/reference/constitution-enforce-hook.md"
if [ -f "$DOC" ]; then
  pass "reference doc present: docs/reference/constitution-enforce-hook.md"
else
  fail "reference doc missing: $DOC"
fi
if grep -q 'reference/constitution-enforce-hook\.md' "$LOOM_ROOT/mkdocs.yml"; then
  pass "mkdocs.yml nav registers the reference doc"
else
  fail "mkdocs.yml nav does NOT register reference/constitution-enforce-hook.md"
fi

# =====================================================================
[ -n "$STUB_BIN" ] && rm -rf "$STUB_BIN"
echo ""
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ] || exit 1
