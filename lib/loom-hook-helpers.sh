#!/usr/bin/env bash
# loom-hook-helpers.sh — shared boilerplate for loom's PreToolUse/
# SessionStart hooks. Sourceable; defines functions only (no top-level
# side effects), so it is safe to source from any hook.
#
# Harvested by loom-0ahj.2 (design-doc 14f08e6d D2 + exploration F6) as a
# behavior-preserving DRY refactor of three idioms that were copy-pasted
# across ~13 hooks:
#
#   1. json_get        — the jq -> grep-oP/sed JSON field-parse ladder.
#   2. json_get_py     — the jq -> python3 field-parse ladder (used where
#                        the hook needs python's JSON escape-decoding).
#   3. loom_env_enabled — the literal-"1" env-var bypass gate.
#
# A fourth idiom (mode_dispatch, full/light/off) lives in
# lib/workflow-state.sh because it composes with workflow_resolve_mode
# already there.
#
# ---------------------------------------------------------------------------
# json_get <jq_path> <flat_fallback_field> [input]
#
# Extract a string field from a hook's JSON payload, echoing it (no
# trailing newline beyond the one echo adds). Reproduces the historical
# inline ladder byte-for-byte:
#
#   if command -v jq >/dev/null 2>&1; then
#     V=$(echo "$INPUT" | jq -r '<jq_path> // ""')
#   else
#     V=$(echo "$INPUT" | grep -oP '"<field>"\s*:\s*"[^"]*"' | head -1 \
#           | sed -E 's/.*"([^"]*)"/\1/')
#   fi
#
# Args:
#   jq_path             jq path expression, e.g. '.tool_name' or
#                       '.tool_input.command'. `// ""` is appended here.
#   flat_fallback_field bare JSON key name used by the no-jq grep
#                       fallback, e.g. 'tool_name' or 'command'. The
#                       fallback is a FLAT first-match scan (matching the
#                       pre-refactor behavior — it does not descend into
#                       tool_input structurally; it grabs the first
#                       "<field>":"..." anywhere in the payload).
#   input               optional; the JSON payload. If omitted, read stdin.
json_get() {
  local jq_path="$1"
  local field="$2"
  local input
  if [ "$#" -ge 3 ]; then
    input="$3"
  else
    input=$(cat)
  fi

  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r "${jq_path} // \"\""
  else
    printf '%s' "$input" \
      | grep -oP "\"${field}\"\\s*:\\s*\"[^\"]*\"" \
      | head -1 \
      | sed -E 's/.*"([^"]*)"/\1/'
  fi
}

# ---------------------------------------------------------------------------
# json_get_py <jq_path> <python_expr> [input]
#
# Like json_get, but the no-jq fallback routes through python3 (which
# JSON-decodes escape sequences). Reproduces the historical ladder:
#
#   if command -v jq >/dev/null 2>&1; then
#     V=$(echo "$INPUT" | jq -r '<jq_path> // ""')
#   else
#     V=$(printf '%s' "$INPUT" | python3 -c \
#           'import json,sys; d=json.load(sys.stdin); print(<python_expr>)')
#   fi
#
# Args:
#   jq_path      jq path expression (e.g. '.tool_name'). `// ""` appended.
#   python_expr  python expression evaluated with `d` bound to the parsed
#                payload, e.g. 'd.get("tool_name","")' or
#                'd.get("tool_input",{}).get("command","")'.
#   input        optional; JSON payload. If omitted, read stdin.
json_get_py() {
  local jq_path="$1"
  local py_expr="$2"
  local input
  if [ "$#" -ge 3 ]; then
    input="$3"
  else
    input=$(cat)
  fi

  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r "${jq_path} // \"\""
  else
    printf '%s' "$input" \
      | python3 -c "import json,sys; d=json.load(sys.stdin); print(${py_expr})"
  fi
}

# ---------------------------------------------------------------------------
# loom_env_enabled <VAR>
#
# True (return 0) iff the named environment variable equals the literal
# string "1". Everything else — "0", "yes", "true", "10", empty, unset —
# returns 1. This is the loom-b1l literal-"1" bypass convention shared by
# every `LOOM_*_SKIP` / `BD_*` env gate.
#
# Usage (replaces `if [ "${LOOM_FOO_SKIP:-0}" = "1" ]; then`):
#   if loom_env_enabled LOOM_FOO_SKIP; then exit 0; fi
loom_env_enabled() {
  local name="$1"
  [ "${!name:-}" = "1" ]
}

# ---------------------------------------------------------------------------
# SOURCE/TEST PATH CLASSIFICATION (loom-p5ee)
#
# Shared by hooks/dispatch-nudge.sh and hooks/main-checkout-edit-guard.sh
# (loom-vr6k). Answers "is this file_path a SOURCE file, a TEST file, or
# neither?" for an arbitrary project — NOT just loom's own bash layout.
#
# WHY THIS EXISTS. dispatch-nudge.sh used to hardcode loom's layout:
# `hooks/*.sh`, `scripts/*`, `lib/*.sh` for source; `*_test.*` and
# `*.test.*` (Go/JS SUFFIX conventions) for tests. Python's test
# convention is `test_*.py` — a PREFIX — so in a Python project NEITHER
# sources NOR tests matched and the hook was 100% dark. Verified against
# a real project: `palace/episodic_store.py` DARK,
# `tests/palace/test_episodic_store.py` DARK, only `scripts/test`
# eligible.
#
# HYBRID RESOLUTION (locked design, loom-p5ee):
#   1. If a `.claude/project-constitution.md` is found walking up from
#      the start dir AND yq can parse its YAML front-matter, the
#      `language.runtime` field selects the language-specific glob set.
#   2. Otherwise — constitution absent, unparseable, yq missing from
#      PATH, or an unrecognized runtime — fall back to a WIDENED
#      built-in glob list covering py/sh/go/js/ts/rb/rs.
#
#   The yq-missing branch is a REAL CODE PATH, not an error path. bd
#   memory `yq-required-for-constitution-enforce` records that
#   constitution-enforce.sh silently failed open (no enforcement, only a
#   stderr WARN) for weeks on a yq-less machine and it went undetected.
#   The fallback here must still CLASSIFY, so the consuming hook still
#   nudges. It does — and it is pinned by lib/tests/dispatch-nudge.test.sh
#   case 10d.
#
#   Rejected alternatives: pattern-list-only (goes dark on the next
#   unanticipated language) and constitution-only (fails open on every
#   unconstituted project — the exact silent-dark class this replaces).
#
# LAYERS. Three glob layers are consulted in a fixed order:
#   EXCLUDE   — always `other`, whatever the runtime (*.md, *.json,
#               anything under docs/).
#   TEST      — universal test shapes (tests/, test/, spec/,
#               __tests__/, *.test.sh, *_test.sh, *.bats) plus the
#               runtime's own test globs. Checked BEFORE source, so
#               `foo.test.sh` is a test, not a shell source file.
#   SOURCE    — universal source shapes (*.sh, *.bash, scripts/*) plus
#               the runtime's own source globs.
#
# Matching is on the path TAIL via shell globs, in which `*` spans `/`,
# so absolute, relative, and worktree-prefixed paths classify
# identically.
#
# Env:
#   LOOM_YQ_BIN  override the yq binary name/path (default `yq`). Used by
#                the test suite to exercise the yq-absent fallback branch
#                on a host that does have yq installed.

# ---------------------------------------------------------------------------
# __loom_glob_match <path> <glob>...
# True (return 0) iff <path> matches any of the given globs.
__loom_glob_match() {
  local p="$1"; shift
  local pat
  for pat in "$@"; do
    # shellcheck disable=SC2254  # $pat is intentionally a glob pattern
    case "$p" in $pat) return 0 ;; esac
  done
  return 1
}

# ---------------------------------------------------------------------------
# loom_project_runtime [start_dir]
#
# Echo the `language.runtime` value from the nearest
# .claude/project-constitution.md, walking up from start_dir (default
# $PWD). Echoes the EMPTY string — never fails the caller — when the
# constitution is absent, yq is unavailable, the front-matter is
# malformed, or the field is absent/null. Callers treat "" as "no
# pinned runtime, use the widened built-in list".
#
# Reuses the same front-matter reader path hooks/constitution-enforce.sh
# uses: awk-slice the block between the first two `---` fences, probe it
# with `yq -e '.'`, then read the scalar.
#
# Memoized per start_dir for the life of the shell (the walk + yq call
# is the expensive part and the constitution does not move mid-hook).
loom_project_runtime() {
  local start="${1:-$PWD}"
  local abs
  abs=$(cd "$start" 2>/dev/null && pwd) || { printf '\n'; return 0; }

  local memo_key="$abs::${LOOM_YQ_BIN:-yq}"
  if [ "${__LOOM_RUNTIME_MEMO_KEY:-}" = "$memo_key" ]; then
    printf '%s\n' "${__LOOM_RUNTIME_MEMO_VAL:-}"
    return 0
  fi

  local dir="$abs" const="" parent
  while :; do
    if [ -f "$dir/.claude/project-constitution.md" ]; then
      const="$dir/.claude/project-constitution.md"
      break
    fi
    [ "$dir" = "/" ] && break
    parent=$(dirname "$dir")
    [ "$parent" = "$dir" ] && break
    dir="$parent"
  done

  local rt=""
  local yq_bin="${LOOM_YQ_BIN:-yq}"
  if [ -n "$const" ] && command -v "$yq_bin" >/dev/null 2>&1; then
    local fm
    if fm=$(mktemp 2>/dev/null); then
      awk 'BEGIN{n=0}
           /^---[[:space:]]*$/{n++; if(n==1){next} if(n==2){exit}}
           n==1{print}' "$const" > "$fm" 2>/dev/null
      if [ -s "$fm" ] && "$yq_bin" -e '.' "$fm" >/dev/null 2>&1; then
        rt=$("$yq_bin" -r '.language.runtime' "$fm" 2>/dev/null)
        [ "$rt" = "null" ] && rt=""
      fi
      rm -f "$fm"
    fi
  fi

  __LOOM_RUNTIME_MEMO_KEY="$memo_key"
  __LOOM_RUNTIME_MEMO_VAL="$rt"
  printf '%s\n' "$rt"
}

# ---------------------------------------------------------------------------
# loom_path_class <path> [start_dir]
#
# Echo exactly one of: `source`, `test`, `other`.
#
#   source  a file carrying implementation code
#   test    a file carrying tests (checked first — `foo.test.sh` is a
#           test, not a shell source file)
#   other   docs, markdown, config, or anything unrecognized
#
# start_dir (default $PWD) is where the constitution walk-up begins.
loom_path_class() {
  local p="$1"
  local start="${2:-$PWD}"

  # --- EXCLUDE layer: always `other`, whatever the runtime. ---
  case "$p" in
    *.md|*.json) printf 'other\n'; return 0 ;;
    */docs/*|docs/*) printf 'other\n'; return 0 ;;
  esac

  # --- Universal layers (runtime-independent). ---
  # ARRAYS, not space-separated strings: an unquoted string expansion
  # would be PATHNAME-expanded against the cwd, so `scripts/*` would
  # silently become the literal files in ./scripts and stop matching the
  # incoming path. Array elements expand verbatim.
  local uni_test=(
    '*/tests/*' 'tests/*' '*/test/*' 'test/*'
    '*/spec/*' 'spec/*' '*/__tests__/*' '__tests__/*'
    '*.test.sh' '*_test.sh' '*.bats'
  )
  local uni_src=( '*.sh' '*.bash' '*/scripts/*' 'scripts/*' )

  # --- Runtime-specific layers. ---
  local rt
  local rt_test=() rt_src=()
  rt=$(loom_project_runtime "$start")
  case "$rt" in
    python|python3|py)
      rt_test=( 'test_*.py' '*/test_*.py' '*_test.py' 'conftest.py' '*/conftest.py' )
      rt_src=( '*.py' )
      ;;
    bash|sh|shell|zsh)
      rt_src=( '*/hooks/*.sh' 'hooks/*.sh' '*/lib/*.sh' 'lib/*.sh' )
      ;;
    go|golang)
      rt_test=( '*_test.go' )
      rt_src=( '*.go' )
      ;;
    node|nodejs|javascript|js|typescript|ts|deno|bun)
      rt_test=( '*.test.*' '*.spec.*' )
      rt_src=( '*.js' '*.jsx' '*.mjs' '*.cjs' '*.ts' '*.tsx' )
      ;;
    ruby|rb)
      rt_test=( '*_test.rb' '*_spec.rb' )
      rt_src=( '*.rb' )
      ;;
    rust|rs)
      rt_test=( '*_test.rs' )
      rt_src=( '*.rs' )
      ;;
    *)
      # No constitution / unparseable / yq missing / unrecognized
      # runtime → the WIDENED built-in list. Covers py/sh/go/js/ts/rb/rs
      # so a hook is never fully dark on an unconstituted project.
      rt_test=(
        'test_*.py' '*/test_*.py' 'conftest.py' '*/conftest.py'
        '*_test.*' '*.test.*' '*_spec.*' '*.spec.*'
      )
      rt_src=(
        '*.py' '*.go' '*.js' '*.jsx' '*.mjs' '*.cjs' '*.ts' '*.tsx'
        '*.rb' '*.rs' '*/hooks/*.sh' 'hooks/*.sh' '*/lib/*.sh' 'lib/*.sh'
      )
      ;;
  esac

  # TEST before SOURCE — a test file is a test even when its extension
  # also matches a source glob.
  if __loom_glob_match "$p" "${uni_test[@]}" ${rt_test[@]+"${rt_test[@]}"}; then
    printf 'test\n'; return 0
  fi
  if __loom_glob_match "$p" "${uni_src[@]}" ${rt_src[@]+"${rt_src[@]}"}; then
    printf 'source\n'; return 0
  fi

  printf 'other\n'
}

# ---------------------------------------------------------------------------
# loom_is_source_or_test <path> [start_dir]
#
# Boolean face of loom_path_class: return 0 iff the path classifies as
# `source` or `test`. This is the predicate hooks gate on.
loom_is_source_or_test() {
  local c
  c=$(loom_path_class "$1" "${2:-$PWD}")
  [ "$c" = "source" ] || [ "$c" = "test" ]
}
