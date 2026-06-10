#!/usr/bin/env bash
# constitution-enforce.sh — PreToolUse hook (Bash matcher). The narrow
# HARD-ENFORCEMENT arm of the project-constitution epic (loom-6f8).
#
# Closes loom-8jz. Distinct from the INFO/nudge arms of the epic
# (constitution-surfacing at session-startup + the dispatched-agent
# smoke-battery step 0): those READ the constitution into context and
# never block. THIS hook BLOCKS (exit 2) a Bash command that violates
# the project's pinned tooling profile, with a helpful suggestion.
#
# WHAT IT DOES
#   On each PreToolUse(Bash):
#     1. LOOM_CONSTITUTION_SKIP=1 → exit 0 (always bypass).
#     2. Walk up from $PWD for .claude/project-constitution.md.
#        Absent → exit 0 SILENT (most projects have no constitution).
#     3. yq missing in PATH → exit 0 with a one-line stderr WARN.
#     4. Parse the YAML front-matter via yq (mtime-keyed cache). A YAML
#        parse error → exit 0 with a stderr WARN.
#     5. Match the command's argv tokens against:
#          - bypass_patterns  (allow-list; checked FIRST)
#          - forbidden        (explicit deny phrases)
#          - package_manager  (a competing manager's `<mgr> <verb>` is
#                              blocked; suggest the canonical manager)
#          - shell.run_prefix (a bare language runtime invoked WITHOUT
#                              the run_prefix is blocked; suggest the
#                              prefixed form)
#        A match → exit 2 with a suggestion. No match → exit 0.
#
# FAILS OPEN by construction. Every path where the hook cannot PROVE a
# violation returns exit 0. It only ever blocks on a positive,
# argv-anchored match against an explicit rule.
#
# ANCHORED-REGEX DISCIPLINE (loom-9ng / loom-oq0s bug class)
#   Matching is on the command's argv TOKENS (parsed with python shlex),
#   never bare substrings of the raw command string. So:
#     - `cat tipping.py` does NOT match the bare-`python` runtime rule
#       (no argv token IS `python`; `tipping.py` is a single token).
#     - `git commit -m "npm install is forbidden"` does NOT match the
#       `npm install` forbidden phrase (shlex keeps the quoted message a
#       single token, so the adjacent `npm`/`install` argv pair the rule
#       needs never appears).
#   Multi-word rules (`npm install`, forbidden phrases) match only when
#   their words appear as ADJACENT argv tokens. Single-word runtime
#   rules match only a token that IS the runtime (optionally a
#   path-suffixed form like /usr/bin/python), never a token that merely
#   ends in `.py` / contains the word.
#
# CACHE
#   The parsed profile is memoized in
#   $XDG_RUNTIME_DIR/loom-constitution-<sha256-of-path>.json keyed on the
#   constitution file's mtime. Re-parse (re-invoke yq) only when the
#   file changes. Cache-write failures are non-fatal (we just re-parse).
#
# Bypass:
#   LOOM_CONSTITUTION_SKIP=1   (literal-"1" only, per loom-b1l)

set -uo pipefail

# --- Source shared helpers (json_get_py, loom_env_enabled) -------------
# Precedence: explicit LOOM_TEST_LIB_DIR (worktree-shadow discipline) >
# installed copy > repo-relative copy.
# shellcheck source=../lib/loom-hook-helpers.sh
if [ -n "${LOOM_TEST_LIB_DIR:-}" ] && [ -f "$LOOM_TEST_LIB_DIR/loom-hook-helpers.sh" ]; then
  . "$LOOM_TEST_LIB_DIR/loom-hook-helpers.sh"
elif [ -f "$HOME/.claude/lib/loom-hook-helpers.sh" ]; then
  . "$HOME/.claude/lib/loom-hook-helpers.sh"
else
  . "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/loom-hook-helpers.sh"
fi

# 1. Always-bypass.
if loom_env_enabled LOOM_CONSTITUTION_SKIP; then
  exit 0
fi

INPUT=$(cat)

TOOL=$(json_get_py '.tool_name' 'd.get("tool_name","")' "$INPUT")
CMD=$(json_get_py '.tool_input.command' 'd.get("tool_input",{}).get("command","")' "$INPUT")

# This hook fires on Bash AND the write-class tools (Edit/Write/MultiEdit).
#   - Bash             → the tooling rules (forbidden / package_manager /
#                        run_prefix) AND any Bash-scoped invariant.
#   - Edit/Write/      → ONLY the invariants: section (loom-z3m.14). The
#     MultiEdit          tooling rules are argv-shaped and meaningless for a
#                        file write; invariants are regex-shaped and apply
#                        to the write's file_path + body.
# Any other tool → nothing to enforce.
case "$TOOL" in
  Bash|Edit|Write|MultiEdit) : ;;
  *) exit 0 ;;
esac

# INVARIANT_TEXT is the newline-joined blob of tool input that invariant
# deny_patterns are matched against. For Bash it is the command; for the
# write-class tools it is the file_path plus the written/edited body.
# Built in python so MultiEdit's edits[] array is flattened correctly and
# absent keys degrade to empty rather than erroring.
INVARIANT_TEXT=$(
  INPUT="$INPUT" python3 - <<'PY'
import json, os, sys
try:
    d = json.loads(os.environ.get("INPUT", ""))
except Exception:
    print("")
    sys.exit(0)
ti = d.get("tool_input", {}) or {}
parts = []
tool = d.get("tool_name", "")
if tool == "Bash":
    parts.append(ti.get("command", "") or "")
else:
    parts.append(ti.get("file_path", "") or "")
    # Write: .content ; Edit: .new_string ; MultiEdit: .edits[].new_string
    parts.append(ti.get("content", "") or "")
    parts.append(ti.get("new_string", "") or "")
    for e in (ti.get("edits", []) or []):
        if isinstance(e, dict):
            parts.append(e.get("new_string", "") or "")
print("\n".join(p for p in parts if p != ""))
PY
)

# For Bash with an empty command there is nothing to enforce on the
# tooling-rules path. The invariants path below still runs (an empty
# INVARIANT_TEXT simply matches no deny_pattern).
if [ "$TOOL" = "Bash" ] && [ -z "$CMD" ] && [ -z "$INVARIANT_TEXT" ]; then
  exit 0
fi

# 2. Walk up from $PWD for .claude/project-constitution.md.
CONST=""
dir="$PWD"
while :; do
  if [ -f "$dir/.claude/project-constitution.md" ]; then
    CONST="$dir/.claude/project-constitution.md"
    break
  fi
  [ "$dir" = "/" ] && break
  parent=$(dirname "$dir")
  [ "$parent" = "$dir" ] && break
  dir="$parent"
done

# No constitution anywhere up-tree → fail open, SILENT.
[ -n "$CONST" ] || exit 0

# --- 2b. AGE-SKEW NUDGE (loom-1lj) -------------------------------------
# A constitution pins the project's tooling profile; tooling drifts when
# devbox.json / a lockfile / .tool-versions / flake.nix changes but the
# constitution is never re-audited. On the FIRST Bash call per shell
# session, if the constitution's mtime is older than the NEWEST tooling
# manifest by more than 7 days, emit a ONE-TIME stderr nudge suggesting
# `/audit-project --check=constitution`. This is purely INFO — it never
# affects the allow/block decision below and never blocks (fail-open
# posture preserved). It runs BEFORE the yq-missing check because it
# only stat()s mtimes; no YAML parse is needed, so it fires even on a
# host without yq.
#
# One-shot per session: a sentinel under $XDG_RUNTIME_DIR keyed on the
# constitution's path. $XDG_RUNTIME_DIR is per-login-session and cleared
# on logout, so the sentinel naturally scopes "once per session". When
# $XDG_RUNTIME_DIR is unset we fall back to $TMPDIR/tmp — the nudge then
# de-dupes per that dir's lifetime, which is an acceptable degradation
# for an INFO-only message.
SKEW_BASE="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"
if command -v sha256sum >/dev/null 2>&1; then
  SKEW_KEY=$(printf '%s' "$CONST" | sha256sum | cut -d' ' -f1)
else
  SKEW_KEY=$(printf '%s' "$CONST" | cksum | tr -d ' ')
fi
SKEW_SENTINEL="$SKEW_BASE/loom-constitution-ageskew-$SKEW_KEY"
if [ ! -e "$SKEW_SENTINEL" ]; then
  CONST_DIR=$(dirname "$(dirname "$CONST")")   # .../<root>/.claude/x → <root>
  CONST_MTIME=$(stat -c %Y "$CONST" 2>/dev/null || stat -f %m "$CONST" 2>/dev/null || echo 0)
  NEWEST_TOOLING=0
  NEWEST_NAME=""
  for f in "$CONST_DIR"/devbox.json "$CONST_DIR"/*.lock "$CONST_DIR"/.tool-versions "$CONST_DIR"/flake.nix; do
    [ -f "$f" ] || continue
    m=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
    if [ "$m" -gt "$NEWEST_TOOLING" ]; then
      NEWEST_TOOLING="$m"
      NEWEST_NAME=$(basename "$f")
    fi
  done
  # 7 days = 604800 seconds. Fire only when a tooling manifest exists AND
  # is newer than the constitution by strictly more than that window.
  SEVEN_DAYS=604800
  if [ "$NEWEST_TOOLING" -gt 0 ] \
     && [ "$CONST_MTIME" -gt 0 ] \
     && [ $((NEWEST_TOOLING - CONST_MTIME)) -gt "$SEVEN_DAYS" ]; then
    DAYS=$(( (NEWEST_TOOLING - CONST_MTIME) / 86400 ))
    echo "[constitution-enforce] INFO: $CONST is ~$DAYS days older than $NEWEST_NAME — the project's tooling may have drifted from the pinned profile. Consider re-running \`/audit-project --check=constitution\` to refresh it." >&2
    # Best-effort one-shot: write the sentinel so we nudge once per
    # session. A write failure is non-fatal (we'd just nudge again).
    : >"$SKEW_SENTINEL" 2>/dev/null || true
  fi
fi

# 3. yq missing → fail open with a stderr WARN (cannot parse the profile).
if ! command -v yq >/dev/null 2>&1; then
  echo "[constitution-enforce] WARN: \`yq\` not found in PATH — cannot parse $CONST; skipping enforcement (fail-open)." >&2
  exit 0
fi

# --- mtime-keyed cache --------------------------------------------------
# Computed UP FRONT so BOTH the invariants check (below) and the
# tooling-rules check (further below) read from the same mtime-keyed cache.
# The cache record carries SIX fields now:
#   run_prefix : package_manager : runtime : forbidden : bypass : invariants
# where `invariants` is a base64 of the JSON array yq extracts. On a cache
# HIT yq is not invoked at all (the cache test depends on this).
CACHE_BASE="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"
# sha256 of the absolute path → stable cache filename.
if command -v sha256sum >/dev/null 2>&1; then
  KEY=$(printf '%s' "$CONST" | sha256sum | cut -d' ' -f1)
else
  KEY=$(printf '%s' "$CONST" | cksum | tr -d ' ')
fi
CACHE_FILE="$CACHE_BASE/loom-constitution-$KEY.json"

# Current mtime (portable: GNU stat -c, BSD stat -f).
MTIME=$(stat -c %Y "$CONST" 2>/dev/null || stat -f %m "$CONST" 2>/dev/null || echo 0)

# Profile fields (tab-separated record):
#   run_prefix \t package_manager \t runtime \t forbidden(\n-joined) \t bypass(\n-joined)
PROFILE=""
USE_CACHE=0
if [ -f "$CACHE_FILE" ]; then
  CACHED_MTIME=$(sed -n '1p' "$CACHE_FILE" 2>/dev/null)
  if [ "$CACHED_MTIME" = "$MTIME" ]; then
    USE_CACHE=1
  fi
fi

FM_FILE=""
yq_get() {
  # yq_get '<expr>' — read a value from the extracted front-matter file;
  # never fails the caller (validity is probed separately below).
  yq -r "$1" "$FM_FILE" 2>/dev/null
}

if [ "$USE_CACHE" = "1" ]; then
  # Body of cache is the profile record (after the mtime line).
  PROFILE=$(sed -n '2,$p' "$CACHE_FILE" 2>/dev/null)
else
  # 4. Parse via yq. The constitution is a Markdown file whose YAML lives
  #    in front-matter between the first two `---` fences; the trailing
  #    prose is NOT YAML. yq reads the WHOLE file as a YAML stream and
  #    treats `---` as a document separator, so it would choke on the
  #    prose. Slice out ONLY the front-matter block first, then point yq
  #    at that slice. A file with no closing fence yields an empty slice
  #    → treated as malformed (fail-open with warn).
  FM_FILE=$(mktemp 2>/dev/null) || { echo "[constitution-enforce] WARN: mktemp failed; skipping enforcement (fail-open)." >&2; exit 0; }
  trap 'rm -f "$FM_FILE"' EXIT
  awk 'BEGIN{n=0}
       /^---[[:space:]]*$/{n++; if(n==1){next} if(n==2){exit}}
       n==1{print}' "$CONST" > "$FM_FILE"

  # Validity probe over the SLICE: empty slice (no front-matter) or a
  # YAML parse error → fail open with a WARN.
  if [ ! -s "$FM_FILE" ] || ! yq -e '.' "$FM_FILE" >/dev/null 2>&1; then
    echo "[constitution-enforce] WARN: malformed/absent YAML front-matter in $CONST — skipping enforcement (fail-open)." >&2
    exit 0
  fi

  RUN_PREFIX=$(yq_get '.shell.run_prefix')
  PKG=$(yq_get '.package_manager')
  RUNTIME=$(yq_get '.language.runtime')
  FORBIDDEN=$(yq_get '.forbidden[]')
  BYPASS=$(yq_get '.bypass_patterns[]')

  # yq prints the literal string "null" for an absent scalar; normalize.
  [ "$RUN_PREFIX" = "null" ] && RUN_PREFIX=""
  [ "$PKG" = "null" ] && PKG=""
  [ "$RUNTIME" = "null" ] && RUNTIME=""
  [ "$FORBIDDEN" = "null" ] && FORBIDDEN=""
  [ "$BYPASS" = "null" ] && BYPASS=""

  # --- invariants extraction (loom-z3m.14) -----------------------------
  # Extract the invariants: sequence-of-maps via per-index yq queries
  # (the same scalar/array verbs the rest of the hook uses, so it works
  # with both real yq and the stubs the tests install — no `-o=json`
  # dependency). Each invariant is encoded as a single line:
  #   <applies_to comma-joined> \t <id> \t <deny b64> \t <message b64>
  # The whole block is then base64'd as the cache record's 6th field.
  # A constitution with no invariants: section yields an empty INV_COUNT
  # → zero lines → empty field (the common case; one extra yq call only).
  INV_COUNT=$(yq_get '.invariants | length')
  case "$INV_COUNT" in (''|null|*[!0-9]*) INV_COUNT=0 ;; esac
  INV_RECORDS=""
  iv=0
  while [ "$iv" -lt "$INV_COUNT" ]; do
    iv_applies=$(yq_get ".invariants[$iv].applies_to[]" | paste -sd, -)
    iv_id=$(yq_get ".invariants[$iv].id");        [ "$iv_id" = "null" ] && iv_id=""
    iv_deny=$(yq_get ".invariants[$iv].deny_pattern"); [ "$iv_deny" = "null" ] && iv_deny=""
    iv_msg=$(yq_get ".invariants[$iv].message");   [ "$iv_msg" = "null" ] && iv_msg=""
    # tab-delimited; deny/message base64'd so embedded tabs/newlines are
    # flattened. applies_to + id are simple tokens kept plain.
    INV_RECORDS="${INV_RECORDS}${iv_applies}	${iv_id}	$(printf '%s' "$iv_deny" | base64 | tr -d '\n')	$(printf '%s' "$iv_msg" | base64 | tr -d '\n')
"
    iv=$((iv + 1))
  done

  # Assemble the profile record. EVERY field is base64-encoded and the
  # fields are joined with a single `:` (base64 alphabet never contains
  # `:`). This survives the two pitfalls that a tab-delimited record hit:
  #   - empty leading/trailing fields (run_prefix="" on a no-shell repo):
  #     bash `read` strips leading IFS-whitespace, which silently
  #     DROPPED an empty first field and shifted every value left by one.
  #     `cut -d:` preserves empty fields positionally.
  #   - embedded newlines in the forbidden/bypass lists: base64 flattens
  #     them so the record stays single-line.
  enc() { printf '%s' "$1" | base64 | tr -d '\n'; }
  PROFILE=$(printf '%s:%s:%s:%s:%s:%s' \
    "$(enc "$RUN_PREFIX")" "$(enc "$PKG")" "$(enc "$RUNTIME")" \
    "$(enc "$FORBIDDEN")" "$(enc "$BYPASS")" "$(enc "$INV_RECORDS")")

  # Best-effort cache write (mtime header + profile body). Never fatal.
  { printf '%s\n%s\n' "$MTIME" "$PROFILE" >"$CACHE_FILE"; } 2>/dev/null || true
fi

# --- Unpack the profile record (positional cut preserves empty fields) -
dec() { printf '%s' "$1" | base64 -d 2>/dev/null; }
RUN_PREFIX=$(dec "$(printf '%s' "$PROFILE" | cut -d: -f1)")
PKG=$(dec "$(printf '%s' "$PROFILE" | cut -d: -f2)")
RUNTIME=$(dec "$(printf '%s' "$PROFILE" | cut -d: -f3)")
FORBIDDEN=$(dec "$(printf '%s' "$PROFILE" | cut -d: -f4)")
BYPASS=$(dec "$(printf '%s' "$PROFILE" | cut -d: -f5)")
INV_RECORDS=$(dec "$(printf '%s' "$PROFILE" | cut -d: -f6)")

# --- INVARIANTS check (loom-z3m.14) ------------------------------------
# Architectural-invariant enforcement runs for Bash AND the write-class
# tools (Edit/Write/MultiEdit). For each invariant line whose applies_to
# includes the CURRENT tool, the regex deny_pattern is matched
# (python re.search) against INVARIANT_TEXT. A match → exit 2 with the
# invariant's message. Fail-open: an uncompilable deny_pattern degrades
# to "no match". INV_RECORDS comes from the mtime cache, so a cache hit
# triggers NO yq re-parse here.
if [ -n "$INV_RECORDS" ]; then
  while IFS=$'\t' read -r iv_applies iv_id iv_deny_b64 iv_msg_b64; do
    [ -n "$iv_applies" ] || [ -n "$iv_id" ] || [ -n "$iv_deny_b64" ] || continue
    # applies_to is comma-joined; does it include the current tool?
    case ",$iv_applies," in
      *",$TOOL,"*) : ;;
      *) continue ;;
    esac
    iv_deny=$(printf '%s' "$iv_deny_b64" | base64 -d 2>/dev/null)
    [ -n "$iv_deny" ] || continue
    if DENY="$iv_deny" TEXT="$INVARIANT_TEXT" python3 - <<'PY'
import os, re, sys
deny = os.environ.get("DENY", "")
text = os.environ.get("TEXT", "")
try:
    rx = re.compile(deny)
except re.error:
    sys.exit(0)   # uncompilable pattern → fail open (no match)
sys.exit(2 if rx.search(text) else 0)
PY
    then
      : # no match → next invariant
    else
      [ "$?" -eq 2 ] || continue   # python error → fail open
      iv_msg=$(printf '%s' "$iv_msg_b64" | base64 -d 2>/dev/null)
      cat >&2 <<EOF
[constitution-enforce] BLOCKED: this $TOOL call violates a project architectural invariant${iv_id:+ ($iv_id)}.

  $iv_msg

Source: $CONST
Bypass (use sparingly): LOOM_CONSTITUTION_SKIP=1 <command>
EOF
      exit 2
    fi
  done <<EOF
$INV_RECORDS
EOF
fi

# Write-class tools have no argv-shaped tooling-rules path — invariants
# are their only enforcement arm. Having cleared the invariant gate, allow.
case "$TOOL" in
  Edit|Write|MultiEdit) exit 0 ;;
esac

# --- Decide: allow / block --------------------------------------------
# All argv-shape matching is delegated to python (shlex), so the rule
# tokens are compared against parsed argv tokens — never against raw
# substrings of the command string. python prints one of:
#   ALLOW
#   BLOCK\t<suggestion text>
DECISION=$(
  CMD="$CMD" RUN_PREFIX="$RUN_PREFIX" PKG="$PKG" RUNTIME="$RUNTIME" \
  FORBIDDEN="$FORBIDDEN" BYPASS="$BYPASS" python3 - <<'PY'
import os, shlex, sys

cmd = os.environ.get("CMD", "")
run_prefix = os.environ.get("RUN_PREFIX", "").strip()
pkg = os.environ.get("PKG", "").strip()
runtime = os.environ.get("RUNTIME", "").strip()
forbidden = [l for l in os.environ.get("FORBIDDEN", "").splitlines() if l.strip()]
bypass = [l for l in os.environ.get("BYPASS", "").splitlines() if l.strip()]

def allow():
    print("ALLOW")
    sys.exit(0)

def block(msg):
    print("BLOCK\t" + msg)
    sys.exit(0)

# Tokenize. A command may chain several invocations with ; && || |.
# We split on those operators (as standalone tokens) into sub-commands
# and check each sub-command's argv independently. Unbalanced quotes →
# we cannot prove a violation → ALLOW (fail open).
try:
    toks = shlex.split(cmd, posix=True)
except ValueError:
    allow()

OPS = {";", "&&", "||", "|", "&"}
subcmds = []
cur = []
for t in toks:
    if t in OPS:
        if cur:
            subcmds.append(cur)
        cur = []
    else:
        cur.append(t)
if cur:
    subcmds.append(cur)

# A package-manager → "install/add/remove/..." verb set. We only block a
# competing manager when it is invoked with one of these mutating verbs,
# matching the canonical failure the field guards against (mixing
# managers for dependency resolution), not e.g. `npm --version`.
PKG_VERBS = {"install", "i", "add", "remove", "rm", "uninstall",
             "update", "upgrade", "ci", "exec", "dlx", "run"}
COMPETING = {"pnpm", "npm", "yarn", "pip", "pip3", "poetry", "uv",
             "cargo", "go", "bun"}

# Map a package_manager value to the canonical install invocation hint.
def install_hint(mgr):
    return {
        "pnpm": "pnpm install", "npm": "npm install", "yarn": "yarn add",
        "pip": "pip install", "uv": "uv pip install",
        "poetry": "poetry add", "cargo": "cargo add", "go": "go get",
        "bun": "bun install",
    }.get(mgr, f"{mgr} <verb>")

# Bare language runtimes that should go through the shell run_prefix.
RUNTIME_BINS = {
    "python": ["python", "python3"],
    "node": ["node"],
    "go": ["go"],
    "rust": ["cargo"],
    "bash": [],   # bash itself is the host shell; nothing to wrap
}

def first_real_token(argv):
    # Skip leading VAR=value assignments and an `env` prefix, return the
    # program token (basename-normalized) plus the argv tail.
    i = 0
    while i < len(argv):
        a = argv[i]
        if "=" in a and not a.startswith("-") and "/" not in a.split("=")[0]:
            i += 1; continue
        if a == "env":
            i += 1; continue
        break
    if i >= len(argv):
        return None, []
    prog = argv[i]
    base = prog.rsplit("/", 1)[-1]   # /usr/bin/python → python
    return base, argv[i+1:]

def matches_bypass(argv):
    # A bypass pattern matches when its whitespace-split words appear as a
    # contiguous run of argv tokens anywhere in the sub-command.
    for pat in bypass:
        pwords = pat.split()
        if not pwords:
            continue
        n = len(pwords)
        for k in range(len(argv) - n + 1):
            if argv[k:k+n] == pwords:
                return True
    return False

def matches_phrase(argv, phrase):
    pwords = phrase.split()
    if not pwords:
        return False
    n = len(pwords)
    for k in range(len(argv) - n + 1):
        if argv[k:k+n] == pwords:
            return True
    return False

for argv in subcmds:
    if not argv:
        continue
    # Allow-list wins: a bypass-pattern hit clears this sub-command.
    if matches_bypass(argv):
        continue

    prog, tail = first_real_token(argv)
    if prog is None:
        continue

    # (a) forbidden phrases — adjacent-argv-token match.
    for phrase in forbidden:
        if matches_phrase(argv, phrase):
            block(f"`{phrase}` is forbidden by this project's constitution "
                  f"(.claude/project-constitution.md). "
                  + (f"Use `{install_hint(pkg)}` instead." if pkg and pkg != "none"
                     else "Remove it or pick the project's canonical command."))

    # (b) competing package manager invoked with a mutating verb.
    if pkg and pkg != "none" and prog in COMPETING and prog != pkg:
        verb = tail[0] if tail and not tail[0].startswith("-") else ""
        if verb in PKG_VERBS:
            block(f"`{prog} {verb}` uses a package manager other than the "
                  f"project's pinned `{pkg}`. Use `{install_hint(pkg)}` "
                  f"(or the matching `{pkg}` subcommand) instead.")

    # (c) bare language runtime invoked WITHOUT the shell run_prefix.
    if run_prefix and runtime in RUNTIME_BINS:
        bins = RUNTIME_BINS[runtime]
        if prog in bins:
            # Already prefixed? The run_prefix words must be the leading
            # argv tokens of this sub-command for it to count as wrapped.
            pre = run_prefix.split()
            if argv[:len(pre)] != pre:
                block(f"`{prog}` should be run through this project's shell "
                      f"envelope. Use `{run_prefix} {prog} ...` "
                      f"(constitution shell.run_prefix = `{run_prefix}`).")

allow()
PY
)

# --- Act on the decision ----------------------------------------------
VERB=$(printf '%s' "$DECISION" | sed -n '1p' | cut -f1)
if [ "$VERB" = "BLOCK" ]; then
  SUGGESTION=$(printf '%s' "$DECISION" | cut -f2-)
  cat >&2 <<EOF
[constitution-enforce] BLOCKED: this command violates the project constitution.

  command = $CMD

  $SUGGESTION

Source: $CONST
Bypass (use sparingly): LOOM_CONSTITUTION_SKIP=1 <command>
EOF
  exit 2
fi

exit 0
