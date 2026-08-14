#!/usr/bin/env bash
# lib/bd-id-extract.sh — detect bead-IDs in stdin text.
#
# Companion to skills/audit-project/SKILL.md Check 2a. Replaces the
# previous ad-hoc-prose approach (every agent invented their own regex,
# which broke on snake_case prefixes like `liza_base-*`) with a small,
# deterministic helper.
#
# THE MODEL. Every hand-rolled bead-ID regex in loom's history has been
# a guess at the SHAPE of a project prefix — `[a-z][a-z0-9]*`, then
# `[a-z][a-z0-9-]*`, then `[a-z][a-z0-9_-]*` — and each guess broke on
# the next prefix shape it had not anticipated. This helper does not
# guess: it detects the project's bd prefix as a LITERAL string and
# anchors the scan on that literal, so the `_` vs `-` vs anything-else
# question never arises. Parse sites should adopt these functions rather
# than patch their own character class (loom-6mf7).
#
# DUAL MODE. The file is both an executable CLI and a sourceable
# library. Sourcing it defines the functions and does nothing else — no
# argument parsing, no stdin read, no shell-option mutation.
#
# Functions (sourceable):
#   bd_id_prefix_of <id>        echo the literal prefix of one bead ID
#   bd_id_detect_prefix [root]  echo the project's bd prefix (rc 1 if none)
#   bd_id_pattern <prefix>      echo the ERE matching IDs under <prefix>
#   bd_id_scan <prefix>         stdin -> matching IDs, deduped, in order
#
# CLI behavior:
#   1. Detect the project's bd prefix as a LITERAL string (from
#      .beads/issues.jsonl or `bd list`; --prefix overrides).
#   2. Scan stdin for tokens of shape <prefix>-<3+ alnum chars> with
#      optional dotted sub-suffix, at any depth (loom-9z1.8,
#      loom-z3m.1.4), each at the START of its token — a match embedded
#      in a path (`infra/loom-cluster.tf`, `check-loom-upstream.md`) is
#      a filename, not a bead ID (loom-ib6y; see BD_ID_TOKEN_START).
#   3. For each unique candidate, run `bd show <id>` from the project
#      root. Non-zero exit ⇒ dead. Emit one ID per line on stdout,
#      preserving the order of first occurrence.
#
# Flags:
#   --prefix=<prefix>   Override prefix auto-detection.
#   --root=<path>       Project root for bd lookups (default: PWD).
#
# Exit codes:
#   0   Success (dead list may be empty).
#   1   Could not detect a prefix (no --prefix, no .beads/issues.jsonl,
#       and `bd list` returned nothing usable).
#   2   Bad flag / usage.
#
# Lineage:
#   loom-6m8 (original). loom-6mf7 made it sourceable and adopted it in
#   hooks/bd-claim-research.sh. Cousin: hooks/bd-close-capture.sh (same
#   regex family, python-side).

# ---------------------------------------------------------------------------
# Prefix detection
# ---------------------------------------------------------------------------
#
# A bead ID is <prefix>-<suffix> where <suffix> is 3+ chars from
# [a-z0-9] with optional .<more>. The prefix is everything up to the
# LAST `-` followed by a valid suffix shape.

# bd_id_prefix_of <id> — echo the prefix portion of an ID like
# "liza_base-e63", "tla-puzzles-bwv", or "loom-9z1.8". Strips the
# trailing -<3+alnum>(.<...>)* to leave the literal prefix. rc 1 if the
# argument is not ID-shaped.
bd_id_prefix_of() {
  local id="${1:-}"
  # Strip optional .<rest> dotted sub-suffix first.
  local stripped="${id%%.*}"
  # The suffix is the segment after the LAST hyphen.
  local suffix="${stripped##*-}"
  # Anything before that last hyphen is the prefix.
  local prefix="${stripped%-*}"
  # Sanity: suffix must be 3+ chars [a-z0-9].
  if printf '%s' "$suffix" | grep -qE '^[a-z0-9]{3,}$' && [ -n "$prefix" ]; then
    printf '%s' "$prefix"
    return 0
  fi
  return 1
}

# bd_id_detect_prefix [root] — echo the project's literal bd prefix.
# Order: first record in <root>/.beads/issues.jsonl, then the first
# record from `bd list --limit 1 --json` run in <root>. rc 1 if neither
# yields an ID-shaped record.
bd_id_detect_prefix() {
  local root="${1:-$PWD}"
  local prefix="" first_id=""

  if [ -f "$root/.beads/issues.jsonl" ]; then
    first_id=$(head -1 "$root/.beads/issues.jsonl" 2>/dev/null \
      | grep -oE '"id":"[^"]+"' \
      | head -1 \
      | sed -E 's/^"id":"([^"]+)"$/\1/')
    if [ -n "$first_id" ]; then
      prefix=$(bd_id_prefix_of "$first_id" || true)
    fi
  fi

  if [ -z "$prefix" ] && command -v bd >/dev/null 2>&1; then
    first_id=$( (cd "$root" 2>/dev/null && bd list --limit 1 --json 2>/dev/null) \
      | grep -oE '"id":[[:space:]]*"[^"]+"' \
      | head -1 \
      | sed -E 's/^"id":[[:space:]]*"([^"]+)"$/\1/')
    if [ -n "$first_id" ]; then
      prefix=$(bd_id_prefix_of "$first_id" || true)
    fi
  fi

  [ -n "$prefix" ] || return 1
  printf '%s' "$prefix"
}

# ---------------------------------------------------------------------------
# Scanning
# ---------------------------------------------------------------------------

# bd_id_pattern <prefix> — echo the ERE matching bead IDs under the given
# LITERAL prefix: <prefix>-<3+ alnum>(.<1+ alnum>)*.
#
# The dotted tail repeats, so multi-level sub-bead IDs (loom-z3m.1.4)
# match whole rather than truncating at the first level. The {3,} suffix
# minimum keeps shell/prose noise (`[a-z]` in a grep literal) from
# parsing as an ID.
#
# Regex metacharacters in the prefix are escaped (only `.` and `+` are
# realistic in practice; bd prefixes are alnum + `-` + `_`).
bd_id_pattern() {
  local prefix="${1:-}"
  local esc
  esc=$(printf '%s' "$prefix" | sed 's/[.[\*^$+?(){}|]/\\&/g')
  printf '%s%s' "$esc" '-[a-z0-9]{3,}(\.[a-z0-9]+)*'
}

# BD_ID_TOKEN_START — the ERE fragment that must precede a bead ID: the
# start of a line, or one character that cannot be part of a path/token.
#
# THE STRUCTURAL RULE (loom-ib6y). A bead ID must begin at the START of
# its token, where a token is a maximal run of [A-Za-z0-9._/-] plus `_`.
# That single positional property is what separates a bead ID from a
# FILENAME:
#
#   infra/loom-cluster.tf         `loom-` follows `/`   → path-embedded
#   commands/check-loom-upstream  `loom-` follows `-`   → mid-token
#   bd update loom-apcn --claim   `loom-` follows ` `   → a real operand
#
# It is deliberately NOT an extension test. An allowlist of extensions
# (.md, .sh, .json, …) turns green on the extensions someone happened to
# list and leaves `.tf`, `.zig`, `.nix`, `.bats`, `.mdx` — and any
# extension invented tomorrow — parsing as bead IDs. That is loom-6mf7's
# finding restated: immunity is STRUCTURAL, not a better character class,
# and an enumeration is a character class in a different hat. Position
# within the token is a property of the input string, so this rule needs
# no list and no tracker lookup.
#
# WHAT IT DOES NOT COVER, on purpose. A filename at a token boundary
# (`git add loom-notes.qqq`) is token-identical to a real ghost ID
# (`loom-9z1.deadie`) — same prefix, same alnum body, same alphabetic
# dotted tail. No rule over the input string alone can separate them, so
# the scan does not try: it stays PERMISSIVE and emits both. That is the
# correct polarity for this lib's own caller, `bd_id_extract_main`
# (audit-project Check 2a), which reports the candidates that do NOT
# resolve — validating existence here would empty its dead-list. The
# opposite-polarity caller, hooks/bd-claim-research.sh, resolves the
# ambiguity against the tracker on its own side.
BD_ID_TOKEN_START='(^|[^A-Za-z0-9._/-])'

# bd_id_scan <prefix> — read stdin, emit every bead ID under <prefix>,
# one per line, deduped, preserving order of first occurrence. Always
# rc 0 (no matches is not an error).
#
# Only IDs at a token start are emitted (see BD_ID_TOKEN_START). ERE has
# no look-behind, so the boundary character is matched-and-consumed, then
# discarded by re-scanning each hit for the bare pattern.
bd_id_scan() {
  local prefix="${1:-}"
  [ -n "$prefix" ] || return 0
  local pattern input
  pattern=$(bd_id_pattern "$prefix")
  input=$(cat || true)
  [ -n "$input" ] || return 0
  printf '%s' "$input" | grep -oE "$BD_ID_TOKEN_START$pattern" 2>/dev/null \
    | grep -oE "$pattern" 2>/dev/null \
    | awk '!seen[$0]++' || true
  return 0
}

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

# Print the leading comment block (line 2 through the first blank line).
bd_id_extract_usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

bd_id_extract_main() {
  local PREFIX="" ROOT="$PWD"

  while [ $# -gt 0 ]; do
    case "$1" in
      --prefix=*) PREFIX="${1#--prefix=}" ;;
      --prefix)   shift; PREFIX="${1:-}" ;;
      --root=*)   ROOT="${1#--root=}" ;;
      --root)     shift; ROOT="${1:-}" ;;
      -h|--help)
        bd_id_extract_usage
        return 0
        ;;
      *)
        printf 'bd-id-extract: unknown flag %s\n' "$1" >&2
        return 2
        ;;
    esac
    shift
  done

  if [ -z "$PREFIX" ]; then
    PREFIX=$(bd_id_detect_prefix "$ROOT" || true)
  fi

  if [ -z "$PREFIX" ]; then
    printf 'bd-id-extract: could not detect bd prefix; pass --prefix=<name>\n' >&2
    return 1
  fi

  # Extract candidates (preserve order of first occurrence; dedup).
  local candidates
  candidates=$(bd_id_scan "$PREFIX")
  [ -n "$candidates" ] || return 0

  # Resolve each via `bd show`. Emit dead IDs.
  local id
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    if (cd "$ROOT" && bd show "$id" >/dev/null 2>&1); then
      : # live
    else
      printf '%s\n' "$id"
    fi
  done <<<"$candidates"

  return 0
}

# Executed, not sourced? Run the CLI. Sourcing stops here, having only
# defined the functions above.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  set -uo pipefail
  bd_id_extract_main "$@"
  exit $?
fi
