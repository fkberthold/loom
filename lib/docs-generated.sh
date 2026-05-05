#!/usr/bin/env bash
# lib/docs-generated.sh — shared detector for "is <root>/docs/ generated?"
#
# Used by both /audit-project (skip docs/ drift checks) and
# /docs-scaffold (refuse to scaffold over a generated tree).
#
# Contract:
#   bash lib/docs-generated.sh <root>
#     exit 0 = docs/ IS generated; stdout: one-line reason
#     exit 1 = docs/ is NOT generated (hand-written, or absent); stdout: one-line reason
#     exit 2 = usage error
#
# Two signals — either sufficient:
#   1. docs/ matches a .gitignore entry under <root> (any .gitignore file
#      under root, not just root-level)
#   2. docs/* referenced as a cp/build target in any of:
#        - scripts/*.sh
#        - Makefile (root)
#        - package.json scripts.*
#        - pyproject.toml [tool.*] sections
#
# When docs/ doesn't exist, the answer is "not generated" — there's
# nothing to skip / refuse over.
#
# Lineage:
#   - loom-qp0 (audit-project skip)
#   - loom-3hb (docs-scaffold refuse)
#   - drawer_loom_decisions_dfb5ece53785610c83ca6619 (loom-b6o close-out, signal G)

set -uo pipefail

if [ $# -ne 1 ]; then
  echo "usage: docs-generated.sh <project-root>" >&2
  exit 2
fi

ROOT="$1"

if [ ! -d "$ROOT" ]; then
  echo "root does not exist: $ROOT" >&2
  exit 2
fi

# Normalize: realpath to drop trailing slashes etc., fall back to as-given
ROOT="$(cd "$ROOT" 2>/dev/null && pwd || echo "$ROOT")"

# If docs/ doesn't exist at all, nothing to detect.
if [ ! -d "$ROOT/docs" ]; then
  echo "no docs/ directory at $ROOT — not generated"
  exit 1
fi

# ---------------------------------------------------------------------
# Signal 1 — docs/ matches a .gitignore entry under <root>
# ---------------------------------------------------------------------
# A line matches when, after stripping leading/trailing whitespace and
# any leading '/', it equals one of:  docs   docs/   docs/*   /docs   /docs/
# We DO NOT match substrings (so 'mydocs/' or 'old-docs/' don't count).
# Comment lines and blank lines are ignored.
check_gitignore() {
  local gi
  while IFS= read -r -d '' gi; do
    while IFS= read -r line || [ -n "$line" ]; do
      # strip leading/trailing whitespace
      line="${line#"${line%%[![:space:]]*}"}"
      line="${line%"${line##*[![:space:]]}"}"
      # skip blank + comment
      [ -z "$line" ] && continue
      case "$line" in \#*) continue ;; esac
      # strip leading slash for normalization (gitignore treats /docs and docs the same when root-anchored)
      local norm="${line#/}"
      # also strip trailing /* or **
      case "$norm" in
        docs|docs/|docs/\*|docs/\*\*)
          echo "Signal 1: docs/ matches .gitignore entry '$line' in $gi"
          return 0
          ;;
      esac
    done <"$gi"
  done < <(find "$ROOT" -name .gitignore -type f -print0 2>/dev/null)
  return 1
}

# ---------------------------------------------------------------------
# Signal 2 — docs/ referenced as build / copy target
# ---------------------------------------------------------------------
# We look for the literal token "docs/" (or "docs " followed by a path
# operator) appearing as a write target in any of:
#   - scripts/*.sh
#   - Makefile at root
#   - package.json scripts.* values
#   - pyproject.toml [tool.*] sections
#
# Heuristic: presence of "docs" / "docs/" in those build files is
# strong evidence — these files describe the build, and a docs
# reference inside them is almost always a write/output target.
# We accept some false-positives here in exchange for simplicity;
# false-positives mean "skip/refuse" which is the safe direction.
check_build_targets() {
  # 2a: scripts/*.sh — look for docs/ as a path OR a `=docs` assignment
  if [ -d "$ROOT/scripts" ]; then
    local sh
    while IFS= read -r -d '' sh; do
      # Two patterns, either sufficient:
      #   - `docs/` as a path token (preceded by whitespace, '"', '=', '/', or line-start)
      #   - `=docs` or `=docs"` or `="docs"` — assigning the bare 'docs' token (e.g. DOCS=docs)
      if grep -Eq '(^|[[:space:]"=/])docs/' "$sh" 2>/dev/null \
         || grep -Eq '=("|'"'"')?docs("|'"'"'|/|[[:space:]]|$)' "$sh" 2>/dev/null; then
        echo "Signal 2: scripts/ build script references docs/ ($sh)"
        return 0
      fi
    done < <(find "$ROOT/scripts" -maxdepth 1 -name '*.sh' -type f -print0 2>/dev/null)
  fi

  # 2b: Makefile at root
  if [ -f "$ROOT/Makefile" ]; then
    if grep -Eq '(^|[[:space:]"=/])docs(/|[[:space:]]|$)' "$ROOT/Makefile" 2>/dev/null; then
      echo "Signal 2: Makefile references docs/ ($ROOT/Makefile)"
      return 0
    fi
  fi

  # 2c: package.json scripts.*
  # We don't fully parse JSON; a substring match within the file is
  # sufficient for the heuristic, scoped to lines that look like
  # script entries (anything between the "scripts" key and the next })
  # is approximated as "any line containing 'docs' inside package.json".
  if [ -f "$ROOT/package.json" ]; then
    # Scope: only flag if "docs" appears somewhere AND a "scripts" key exists.
    if grep -q '"scripts"' "$ROOT/package.json" 2>/dev/null \
       && grep -Eq '(^|[[:space:]"=/])docs(/|[[:space:]]|"|$)' "$ROOT/package.json" 2>/dev/null; then
      echo "Signal 2: package.json references docs/ ($ROOT/package.json)"
      return 0
    fi
  fi

  # 2d: pyproject.toml [tool.*]
  if [ -f "$ROOT/pyproject.toml" ]; then
    # Scope: only inside a [tool.*] or build-system section. Approximate
    # with "any 'docs' reference under a [tool" header" — read line-by-line.
    awk '
      /^\[/ { in_tool = ($0 ~ /^\[tool\./ || $0 ~ /^\[build-system\]/) }
      in_tool && /(^|[ \t"=/])docs([ \t/"]|$)/ { found = 1 }
      END { exit found ? 0 : 1 }
    ' "$ROOT/pyproject.toml" 2>/dev/null && {
      echo "Signal 2: pyproject.toml [tool.*] references docs/ ($ROOT/pyproject.toml)"
      return 0
    }
  fi

  return 1
}

# ---------------------------------------------------------------------
# Run signals
# ---------------------------------------------------------------------
if reason=$(check_gitignore); then
  echo "$reason"
  exit 0
fi

if reason=$(check_build_targets); then
  echo "$reason"
  exit 0
fi

echo "no generated-docs signal at $ROOT (docs/ appears hand-written)"
exit 1
