#!/usr/bin/env bash
# lib/bd-id-extract.sh — detect dead bead-IDs in stdin text.
#
# Companion to skills/audit-project/SKILL.md Check 2a. Replaces the
# previous ad-hoc-prose approach (every agent invented their own regex,
# which broke on snake_case prefixes like `liza_base-*`) with a small,
# deterministic helper.
#
# Behavior:
#   1. Detect the project's bd prefix as a LITERAL string (from
#      .beads/issues.jsonl or .beads/config.yaml; --prefix overrides).
#   2. Scan stdin for tokens of shape <prefix>-<3+ alnum chars> with
#      optional dotted sub-suffix (loom-9z1.8). The prefix is a
#      literal, so `liza_base-` matches as-is and the `_` vs `-`
#      shape question never arises.
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
#   loom-6m8 (this bead). Cousin: hooks/bd-close-capture.sh (same
#   regex family; kept separate per loom-6m8 brief — unification is
#   a follow-up).

set -uo pipefail

PREFIX=""
ROOT="$PWD"

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix=*) PREFIX="${1#--prefix=}" ;;
    --prefix)   shift; PREFIX="${1:-}" ;;
    --root=*)   ROOT="${1#--root=}" ;;
    --root)     shift; ROOT="${1:-}" ;;
    -h|--help)
      sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      printf 'bd-id-extract: unknown flag %s\n' "$1" >&2
      exit 2
      ;;
  esac
  shift
done

# -------- Prefix detection -------------------------------------------------
#
# Order:
#   1. --prefix flag (already handled above)
#   2. First record in .beads/issues.jsonl
#   3. First record from `bd list --limit 1 --json`
#
# A bead ID is <prefix>-<suffix> where <suffix> is 3+ chars from
# [a-z0-9] with optional .<more>. The prefix is everything up to the
# LAST `-` followed by a valid suffix shape.

detect_prefix_from_id() {
  # Echo the prefix portion of an ID like "liza_base-e63" or
  # "tla-puzzles-bwv" or "loom-9z1.8".  Strip the trailing
  # -<3+alnum>(.<...>)? to leave the literal prefix.
  local id="$1"
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

if [ -z "$PREFIX" ]; then
  if [ -f "$ROOT/.beads/issues.jsonl" ]; then
    first_id=$(head -1 "$ROOT/.beads/issues.jsonl" 2>/dev/null \
      | grep -oE '"id":"[^"]+"' \
      | head -1 \
      | sed -E 's/^"id":"([^"]+)"$/\1/')
    if [ -n "$first_id" ]; then
      PREFIX=$(detect_prefix_from_id "$first_id" || true)
    fi
  fi
fi

if [ -z "$PREFIX" ]; then
  # Try `bd list` as a fallback.
  if command -v bd >/dev/null 2>&1; then
    first_id=$(cd "$ROOT" && bd list --limit 1 --json 2>/dev/null \
      | grep -oE '"id":[[:space:]]*"[^"]+"' \
      | head -1 \
      | sed -E 's/^"id":[[:space:]]*"([^"]+)"$/\1/')
    if [ -n "$first_id" ]; then
      PREFIX=$(detect_prefix_from_id "$first_id" || true)
    fi
  fi
fi

if [ -z "$PREFIX" ]; then
  printf 'bd-id-extract: could not detect bd prefix; pass --prefix=<name>\n' >&2
  exit 1
fi

# -------- Scan stdin -------------------------------------------------------
#
# Build a literal-prefix-anchored regex. Suffix is <3+ alnum> with optional
# dotted sub-suffix. Use word boundaries so prose punctuation doesn't pull
# trailing chars in.
#
# Escape regex metacharacters in the prefix (only `.` and `+` are realistic
# in practice; bd prefixes are alnum + `-` + `_`).

esc_prefix=$(printf '%s' "$PREFIX" | sed 's/[.[\*^$+?(){}|]/\\&/g')
# The regex: <prefix>-<3+ alnum>(.<1+ alnum>)*
# grep -oE will produce one match per occurrence; we dedup downstream.
pattern="${esc_prefix}-[a-z0-9]{3,}(\.[a-z0-9]+)*"

# Read stdin into a buffer (may be empty).
input=$(cat || true)
if [ -z "$input" ]; then
  exit 0
fi

# Extract candidates (preserve order of first occurrence; dedup).
candidates=$(printf '%s' "$input" | grep -oE "$pattern" 2>/dev/null \
  | awk '!seen[$0]++' || true)

[ -z "$candidates" ] && exit 0

# Resolve each via `bd show`. Capture dead IDs.
while IFS= read -r id; do
  [ -z "$id" ] && continue
  if (cd "$ROOT" && bd show "$id" >/dev/null 2>&1); then
    : # live
  else
    printf '%s\n' "$id"
  fi
done <<<"$candidates"

exit 0
