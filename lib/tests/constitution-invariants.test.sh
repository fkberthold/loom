#!/usr/bin/env bash
# Fixture tests for the `invariants:` extension of
# hooks/constitution-enforce.sh (loom-z3m.14).
#
# The constitution's existing arms (forbidden / package_manager /
# run_prefix) guard *tooling* on Bash only. The `invariants:` section
# extends the SAME hook to enforce project-specific ARCHITECTURAL
# invariants ("only touch the world through MCP, never direct file
# I/O") across Bash AND Edit/Write/MultiEdit. Each invariant is
#   {id, applies_to:[Bash|Edit|Write|MultiEdit], deny_pattern, message}
# and is a regex matched against the tool's relevant input
# (Bash→.command; Edit/Write/MultiEdit→.file_path + .content/.new_string).
# A match → exit 2 emitting the invariant's message.
#
# This file pins the new behavior and preserves the hook's two
# load-bearing guarantees: FAIL-OPEN on any uncertainty, and the
# LOOM_CONSTITUTION_SKIP=1 bypass.
#
# yq is NOT assumed installed in CI. As in constitution-enforce.test.sh,
# when the host lacks a real yq we install a tiny stub that answers the
# dotted-path / array queries the hook issues against a well-formed
# front-matter slice — including the new `invariants` sequence-of-maps.
#
# Run:  bash lib/tests/constitution-invariants.test.sh

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
# The stub understands the constitution shape AND the new `invariants:`
# sequence-of-maps. It answers:
#   yq -r '.invariants | length'                  → count
#   yq -r '.invariants[N].id'                      → scalar field
#   yq -r '.invariants[N].applies_to[]'            → newline-joined items
#   yq -r '.invariants[N].deny_pattern'            → scalar
#   yq -r '.invariants[N].message'                 → scalar
#   plus the existing scalar/array queries.
STUB_BIN=""
make_yq_stub() {
  local d; d=$(mktemp -d)
  cat >"$d/yq" <<'STUB'
#!/usr/bin/env bash
# yq stub for constitution-invariants tests. Parses the YAML
# front-matter (or a fence-less slice) and answers the dotted-path /
# array / indexed-invariant queries the hook issues.
set -uo pipefail
args=("$@")
file="${args[${#args[@]}-1]}"
expr=""
for ((i=0; i<${#args[@]}-1; i++)); do
  case "${args[$i]}" in
    -r|-e|e|-o=*|-N) : ;;
    *) expr="${args[$i]}" ;;
  esac
done
[ -f "$file" ] || { exit 0; }
if grep -q '^---[[:space:]]*$' "$file"; then
  fm=$(awk 'BEGIN{n=0} /^---[[:space:]]*$/{n++; next} n==1{print} n>=2{exit}' "$file")
else
  fm=$(cat "$file")
fi
if printf '%s\n' "$fm" | grep -q '__MALFORMED_YAML__'; then
  echo "Error: bad YAML" >&2
  exit 1
fi
FM="$fm" EXPR="$expr" python3 - <<'PY'
import os, re, sys

fm = os.environ["FM"]
expr = os.environ["EXPR"].strip()

# A small but CORRECT indentation-based YAML reader. It handles exactly
# the shapes the constitution fixtures use: top-level scalars, one-level
# nested maps (shell:, language:, canonical_commands:), top-level
# sequences of scalars (forbidden:, bypass_patterns:, applies_to: nested),
# and a sequence-of-maps (invariants:). Built as a recursive parser over a
# list of (indent, text) lines so nesting is handled structurally rather
# than by ad-hoc look-ahead.

def strip_q(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == '"' and v[-1] == '"':
        # Double-quoted: unescape standard YAML escapes the way real yq
        # does, so a fixture's "open\\(" becomes the string  open\(  and
        # downstream re.compile sees a single backslash (a literal `(`).
        inner = v[1:-1]
        out = []
        k = 0
        while k < len(inner):
            c = inner[k]
            if c == "\\" and k + 1 < len(inner):
                nxt = inner[k + 1]
                out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(nxt, nxt))
                k += 2
            else:
                out.append(c)
                k += 1
        return "".join(out)
    if len(v) >= 2 and v[0] == "'" and v[-1] == "'":
        return v[1:-1]
    return v

# Tokenize into (indent, stripped_text), dropping blanks and comments.
toks = []
for raw in fm.splitlines():
    if not raw.strip() or raw.lstrip().startswith("#"):
        continue
    toks.append((len(raw) - len(raw.lstrip()), raw.strip()))

KV = re.compile(r"^([A-Za-z0-9_]+):\s*(.*)$")

def parse_block(idx, indent):
    """Parse a mapping at >= `indent`. Returns (dict, next_idx)."""
    node = {}
    while idx < len(toks):
        ind, text = toks[idx]
        if ind < indent:
            break
        if text.startswith("- "):
            # A sequence appearing where a mapping was expected: caller
            # should have routed it to parse_seq. Stop.
            break
        m = KV.match(text)
        if not m:
            idx += 1
            continue
        key, val = m.group(1), m.group(2)
        if val != "":
            node[key] = strip_q(val)
            idx += 1
            continue
        # Empty value → nested block (map or sequence) at deeper indent.
        if idx + 1 < len(toks) and toks[idx + 1][0] > ind:
            child_ind = toks[idx + 1][0]
            if toks[idx + 1][1].startswith("- "):
                seq, idx = parse_seq(idx + 1, child_ind)
                node[key] = seq
            else:
                sub, idx = parse_block(idx + 1, child_ind)
                node[key] = sub
        else:
            node[key] = ""   # empty scalar / empty inline (e.g. `foo:`)
            idx += 1
    return node, idx

def parse_seq(idx, indent):
    """Parse a sequence at `indent`. Items are scalars or maps."""
    items = []
    while idx < len(toks):
        ind, text = toks[idx]
        if ind < indent or not text.startswith("- "):
            break
        rest = text[2:].strip()
        mm = KV.match(rest)
        if mm:
            # sequence-of-maps: the dash line carries the first key.
            item = {}
            key, val = mm.group(1), mm.group(2)
            if val != "":
                item[key] = strip_q(val)
                idx += 1
            else:
                # nested block under this key
                if idx + 1 < len(toks) and toks[idx + 1][0] > ind:
                    cind = toks[idx + 1][0]
                    if toks[idx + 1][1].startswith("- "):
                        sub, idx = parse_seq(idx + 1, cind)
                    else:
                        sub, idx = parse_block(idx + 1, cind)
                    item[key] = sub
                else:
                    item[key] = ""
                    idx += 1
            # Continuation keys of this map item live at indent > ind
            # (the dash column), as plain `key:` lines.
            while idx < len(toks) and toks[idx][0] > ind and not toks[idx][1].startswith("- "):
                cind, ctext = toks[idx]
                cm = KV.match(ctext)
                if not cm:
                    idx += 1
                    continue
                ck, cv = cm.group(1), cm.group(2)
                if cv != "":
                    item[ck] = strip_q(cv)
                    idx += 1
                else:
                    if idx + 1 < len(toks) and toks[idx + 1][0] > cind:
                        ccind = toks[idx + 1][0]
                        if toks[idx + 1][1].startswith("- "):
                            sub, idx = parse_seq(idx + 1, ccind)
                        else:
                            sub, idx = parse_block(idx + 1, ccind)
                        item[ck] = sub
                    else:
                        item[ck] = ""
                        idx += 1
            items.append(item)
        else:
            # scalar item
            items.append(strip_q(rest))
            idx += 1
    return items, idx

root, _ = parse_block(0, 0)

def lookup(path):
    p = path.strip()
    # Pipe-to-length:  .foo | length
    mlen = re.match(r"^\.?([A-Za-z0-9_]+)\s*\|\s*length$", p)
    if mlen:
        v = root.get(mlen.group(1), [])
        return str(len(v) if isinstance(v, (list, dict)) else 0)
    p = p.lstrip(".")
    # .invariants[N].field  or  .invariants[N].field[]
    m = re.match(r"^([A-Za-z0-9_]+)\[(\d+)\]\.([A-Za-z0-9_]+)(\[\])?$", p)
    if m:
        seqname, idx, field, is_arr = m.group(1), int(m.group(2)), m.group(3), bool(m.group(4))
        items = root.get(seqname, [])
        if not isinstance(items, list) or idx >= len(items):
            return ""
        v = items[idx].get(field, "") if isinstance(items[idx], dict) else ""
        if isinstance(v, list):
            return "\n".join(str(x) for x in v)
        return v
    # array form  foo[]   (top-level sequence) or  parent.child
    if p.endswith("[]"):
        name = p[:-2]
        v = root.get(name, [])
        if isinstance(v, list):
            return "\n".join(str(x) for x in v)
        return ""
    # dotted parent.child scalar
    if "." in p:
        parent, child = p.split(".", 1)
        v = root.get(parent, {})
        if isinstance(v, dict):
            cv = v.get(child, "")
            return cv if not isinstance(cv, (list, dict)) else ""
        return ""
    v = root.get(p, "")
    if isinstance(v, (list, dict)):
        return ""
    return v

print(lookup(expr))
PY
STUB
  chmod +x "$d/yq"
  echo "$d"
}

yq_path() {
  if command -v yq >/dev/null 2>&1; then
    echo "$PATH"
  else
    [ -n "$STUB_BIN" ] || STUB_BIN=$(make_yq_stub)
    echo "$STUB_BIN:$PATH"
  fi
}

# --- Fixture project trees ---------------------------------------------
# A constitution declaring an MCP-only architectural invariant. It bans
# direct python file-open (`open(` in a Write/Edit body) AND a curl in a
# Bash command. The deny_pattern is a regex applied to the relevant
# tool input.
mk_invariant_project() {
  local d; d=$(mktemp -d)
  mkdir -p "$d/.claude"
  cat >"$d/.claude/project-constitution.md" <<'EOF'
---
shell:
  enter: ""
  run_prefix: ""

package_manager: none

language:
  runtime: bash
  version: ""

forbidden: []

canonical_commands:
  build: ""
  test: ""
  lint: ""
  gen: ""
  dev: ""

bypass_patterns: []

invariants:
  - id: no-direct-file-io
    applies_to:
      - Write
      - Edit
      - MultiEdit
    deny_pattern: "open\\("
    message: "Touch the world only through MCP — direct file I/O (open(...)) is forbidden by this project's architectural invariant."
  - id: no-curl-egress
    applies_to:
      - Bash
    deny_pattern: "curl "
    message: "Network egress must go through the MCP gateway — raw curl is forbidden by this project's architectural invariant."
---

# fixture constitution with invariants
EOF
  echo "$d"
}

# A constitution with NO invariants: section at all. Edit/Write calls
# must remain a silent no-op (fail-open: nothing to enforce).
mk_no_invariant_project() {
  local d; d=$(mktemp -d)
  mkdir -p "$d/.claude"
  cat >"$d/.claude/project-constitution.md" <<'EOF'
---
shell:
  enter: ""
  run_prefix: ""

package_manager: none

language:
  runtime: bash
  version: ""

forbidden: []

canonical_commands:
  build: ""
  test: ""
  lint: ""
  gen: ""
  dev: ""

bypass_patterns: []
---

# fixture constitution, no invariants
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
invariants: : :
---

# malformed fixture
EOF
  echo "$d"
}

# --- Hook runner -------------------------------------------------------
#   run_tool <cwd> <json-payload> [extra env assignments...]
# Returns hook stdout+stderr; rc in caller's $?.
run_tool() {
  local cwd="$1" payload="$2"; shift 2
  ( cd "$cwd" && env "$@" PATH="$(yq_path)" bash "$HOOK" <<<"$payload" 2>&1 )
}

# JSON payload builders.
write_payload() {  # <file_path> <content>
  python3 -c '
import json, sys
print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":sys.argv[2]}}))' "$1" "$2"
}
edit_payload() {   # <file_path> <new_string>
  python3 -c '
import json, sys
print(json.dumps({"tool_name":"Edit","tool_input":{"file_path":sys.argv[1],"old_string":"x","new_string":sys.argv[2]}}))' "$1" "$2"
}
multiedit_payload() {  # <file_path> <new_string>
  python3 -c '
import json, sys
print(json.dumps({"tool_name":"MultiEdit","tool_input":{"file_path":sys.argv[1],"edits":[{"old_string":"x","new_string":sys.argv[2]}]}}))' "$1" "$2"
}
bash_payload() {   # <command>
  python3 -c '
import json, sys
print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1"
}

# =====================================================================
echo "==> RED spec: a declared Write-deny invariant blocks a matching Write"
P=$(mk_invariant_project)

# Matching Write (content contains open() ) → exit 2 + message.
out=$(run_tool "$P" "$(write_payload "handler.py" "data = open('/etc/passwd').read()")"); rc=$?
if [ "$rc" -eq 2 ] && echo "$out" | grep -q 'direct file I/O'; then
  pass "Write whose content matches deny_pattern → exit 2 with the invariant message"
else
  fail "matching Write not blocked/messaged. rc=$rc" "$out"
fi

# Non-matching Write → exit 0.
out=$(run_tool "$P" "$(write_payload "notes.md" "just some prose, no file io here")"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "Write whose content does NOT match deny_pattern → exit 0"
else
  fail "non-matching Write wrongly blocked. rc=$rc" "$out"
fi

# file_path itself can match the deny_pattern (it is part of the checked
# input). A path containing open( is contrived but proves file_path is
# scanned; use a content-only assertion above and a file_path assertion
# here via a separate invariant-friendly pattern is overkill — instead
# assert an Edit whose new_string matches.
out=$(run_tool "$P" "$(edit_payload "handler.py" "f = open('x')")"); rc=$?
if [ "$rc" -eq 2 ] && echo "$out" | grep -q 'direct file I/O'; then
  pass "Edit whose new_string matches deny_pattern → exit 2 with the message"
else
  fail "matching Edit not blocked/messaged. rc=$rc" "$out"
fi

# MultiEdit whose any edit new_string matches → exit 2.
out=$(run_tool "$P" "$(multiedit_payload "handler.py" "y = open('y')")"); rc=$?
if [ "$rc" -eq 2 ] && echo "$out" | grep -q 'direct file I/O'; then
  pass "MultiEdit whose edit new_string matches deny_pattern → exit 2 with the message"
else
  fail "matching MultiEdit not blocked/messaged. rc=$rc" "$out"
fi
rm -rf "$P"

# =====================================================================
echo "==> a Bash invariant blocks a matching command; non-matching passes"
P=$(mk_invariant_project)

out=$(run_tool "$P" "$(bash_payload "curl https://evil.example/x")"); rc=$?
if [ "$rc" -eq 2 ] && echo "$out" | grep -q 'MCP gateway'; then
  pass "Bash command matching a Bash invariant deny_pattern → exit 2 with the message"
else
  fail "matching Bash invariant not blocked. rc=$rc" "$out"
fi

out=$(run_tool "$P" "$(bash_payload "echo hello")"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "non-matching Bash command → exit 0"
else
  fail "non-matching Bash command wrongly blocked. rc=$rc" "$out"
fi

# A Bash command that matches the WRITE-scoped invariant deny_pattern
# (open() ) must NOT fire — that invariant's applies_to excludes Bash.
out=$(run_tool "$P" "$(bash_payload "grep -n open( handler.py")"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "Bash command matching a Write-scoped invariant does NOT fire (applies_to honored)"
else
  fail "applies_to not honored: Write-scoped invariant fired on Bash. rc=$rc" "$out"
fi
rm -rf "$P"

# =====================================================================
echo "==> fail-open: no invariants section → Edit/Write are silent no-ops"
P=$(mk_no_invariant_project)
out=$(run_tool "$P" "$(write_payload "handler.py" "data = open('/etc/passwd').read()")"); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "constitution without invariants: matching-looking Write is a silent no-op"
else
  fail "no-invariants Write not silent-allow. rc=$rc" "$out"
fi
rm -rf "$P"

# =====================================================================
echo "==> fail-open: no constitution file at all → Edit/Write silent no-op"
NC=$(mktemp -d)
out=$(run_tool "$NC" "$(write_payload "handler.py" "data = open('/etc/passwd').read()")"); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "no constitution up-tree: Write is a silent no-op"
else
  fail "no-constitution Write not silent-allow. rc=$rc" "$out"
fi
rm -rf "$NC"

# =====================================================================
echo "==> fail-open: malformed YAML → exit 0 (with a warn) even for Write"
P=$(mk_malformed_project)
out=$(run_tool "$P" "$(write_payload "handler.py" "data = open('/etc/passwd').read()")"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "malformed front-matter: Write fails open (exit 0)"
else
  fail "malformed YAML not fail-open for Write. rc=$rc" "$out"
fi
rm -rf "$P"

# =====================================================================
echo "==> bypass: LOOM_CONSTITUTION_SKIP=1 clears an otherwise-blocked Write"
P=$(mk_invariant_project)
out=$(run_tool "$P" "$(write_payload "handler.py" "data = open('/etc/passwd').read()")" LOOM_CONSTITUTION_SKIP=1); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "LOOM_CONSTITUTION_SKIP=1 bypasses an invariant-violating Write"
else
  fail "SKIP=1 did not bypass invariant. rc=$rc" "$out"
fi
# And for Bash.
out=$(run_tool "$P" "$(bash_payload "curl https://evil.example/x")" LOOM_CONSTITUTION_SKIP=1); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "LOOM_CONSTITUTION_SKIP=1 bypasses an invariant-violating Bash command"
else
  fail "SKIP=1 did not bypass Bash invariant. rc=$rc" "$out"
fi
rm -rf "$P"

# =====================================================================
echo "====================================="
echo "RESULTS: $passed passed, $failed failed"
echo "====================================="
[ "$failed" -eq 0 ]
