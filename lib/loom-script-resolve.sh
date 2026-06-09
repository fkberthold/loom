#!/usr/bin/env bash
# loom-script-resolve.sh — resolver for the loom "script/ convention".
#
# Exposes `loom_resolve_command <X>` implementing the three-rung
# resolution contract locked in loom-adm (the script/ convention drawer
# — D-pivot layering + resolution contract). Tracks loom-oxs.2.
#
# THE CONTRACT (strict priority order):
#   1. If `script/X` (or `scripts/X` — EITHER dir accepted) exists and
#      is executable → RUN it. Its exit code is AUTHORITATIVE: the
#      convention's stub semantics are exit 2 = not-wired stub, exit 0
#      = ran / genuinely-N/A. The resolver surfaces that code verbatim;
#      it never masks a stub's 2 into a 0.
#   2. Else if `canonical_commands.X` is set in
#      `.claude/project-constitution.md` → RUN that string command via
#      the shell. Its exit code is likewise authoritative.
#   3. Else → emit a warning to stderr ("no X command defined") and
#      return NON-ZERO. NEVER a silent pass / exit 0 — the
#      no-false-green guard. A missing command is a refusal, not a
#      success.
#
# THE LAYERING this encodes (loom-adm):
#   - script/  = the EXECUTABLE impl layer.
#   - constitution canonical_commands = the DECLARATIVE pointer.
#   - script/X is the DEFAULT IMPL of canonical_commands.X (present →
#     it IS the command; absent → the canonical_commands string; both
#     absent → warn, never pass).
#
# Conventions (mirror lib/loom-upstream.sh):
#   - Single-purpose functions; this file is SOURCED, not executed.
#   - Sourcing the library has NO side effects.
#   - jq-free AND yq-free: the constitution front-matter is parsed with
#     pure awk so the resolver carries no external-tool dependency
#     (loom has no application runtime; canonical_commands is a flat
#     two-space-indented block, easy to slice without a YAML engine).
#   - Project root is discovered by walking up from $PWD for
#     .claude/project-constitution.md (same walk as
#     hooks/constitution-enforce.sh). The script/ + scripts/ probe is
#     anchored at that root; absent a constitution, $PWD is the root so
#     a bare script/X still resolves.

# Intentionally NO `set -euo pipefail` at sourcing time — callers manage
# their own shell options. Functions use explicit returns.

# ---------------------------------------------------------------------
# _loom_sr_find_root
#   Walk up from $PWD looking for .claude/project-constitution.md.
#   Echo the directory containing it. If none is found, echo $PWD
#   (a project may have script/ without a constitution).
# ---------------------------------------------------------------------
_loom_sr_find_root() {
  local dir parent
  dir="$PWD"
  while :; do
    if [ -f "$dir/.claude/project-constitution.md" ]; then
      echo "$dir"
      return 0
    fi
    [ "$dir" = "/" ] && break
    parent=$(dirname "$dir")
    [ "$parent" = "$dir" ] && break
    dir="$parent"
  done
  echo "$PWD"
}

# ---------------------------------------------------------------------
# _loom_sr_canonical_command <root> <X>
#   Extract canonical_commands.X from <root>/.claude/project-
#   constitution.md. Echo the value on stdout. Returns 0 iff a
#   NON-EMPTY value is set; returns 1 (with no output) when the key is
#   absent, empty, or the constitution itself is missing.
#
#   jq-free / yq-free: slices the front-matter (between the first two
#   `---` fences), then reads the two-space-indented `<X>:` line under
#   the `canonical_commands:` block with awk. Surrounding single/double
#   quotes on the value are stripped.
# ---------------------------------------------------------------------
_loom_sr_canonical_command() {
  local root="$1" x="$2" const val
  const="$root/.claude/project-constitution.md"
  [ -f "$const" ] || return 1

  val=$(awk -v key="$x" '
    BEGIN { in_fm = 0; fences = 0; in_block = 0 }
    # Track front-matter fences: front-matter is between the 1st and 2nd `---`.
    /^---[[:space:]]*$/ {
      fences++
      if (fences == 1) { in_fm = 1; next }
      if (fences == 2) { in_fm = 0; exit }
      next
    }
    in_fm != 1 { next }

    # Enter the canonical_commands: block.
    /^canonical_commands:[[:space:]]*$/ { in_block = 1; next }

    # A new top-level key (column 0, non-space) ends the block.
    in_block == 1 && /^[^[:space:]]/ { in_block = 0 }

    in_block == 1 {
      # Match exactly two-space-indented `  <key>:` then the value.
      line = $0
      # Strip the leading two-space indent.
      if (line ~ /^  [^[:space:]]/) {
        rest = substr(line, 3)
        # Split on the FIRST colon.
        ci = index(rest, ":")
        if (ci > 0) {
          k = substr(rest, 1, ci - 1)
          v = substr(rest, ci + 1)
          if (k == key) {
            # Trim leading/trailing whitespace from the value.
            gsub(/^[[:space:]]+/, "", v)
            gsub(/[[:space:]]+$/, "", v)
            print v
            exit
          }
        }
      }
    }
  ' "$const")

  # Strip a single layer of surrounding matching quotes.
  case "$val" in
    \"*\") val="${val#\"}"; val="${val%\"}" ;;
    \'*\') val="${val#\'}"; val="${val%\'}" ;;
  esac

  [ -n "$val" ] || return 1
  printf '%s\n' "$val"
  return 0
}

# ---------------------------------------------------------------------
# loom_resolve_command <X> [extra-args...]
#   The public entry point. Resolves command X through the three-rung
#   contract and RUNS the resolved command, propagating its exit code.
#   Any [extra-args...] are forwarded to the resolved command (a
#   script/X or the canonical_commands string).
# ---------------------------------------------------------------------
loom_resolve_command() {
  local x="$1"
  if [ -z "$x" ]; then
    echo "loom_resolve_command: missing command name argument" >&2
    return 2
  fi
  shift

  local root
  root=$(_loom_sr_find_root)

  # Rung 1 — executable script/X or scripts/X (script/ wins; prefer the
  # singular dir when both exist, matching the convention's default).
  local candidate
  for candidate in "$root/script/$x" "$root/scripts/$x"; do
    if [ -f "$candidate" ] && [ -x "$candidate" ]; then
      "$candidate" "$@"
      return $?
    fi
  done

  # Rung 2 — canonical_commands.X string from the constitution.
  local cmd
  if cmd=$(_loom_sr_canonical_command "$root" "$x"); then
    # Run the declarative string through the shell so it can carry its
    # own arguments/quoting; forward any extra args after it.
    if [ "$#" -gt 0 ]; then
      bash -c "$cmd \"\$@\"" _ "$@"
    else
      bash -c "$cmd"
    fi
    return $?
  fi

  # Rung 3 — no script, no canonical_commands.X → warn + non-zero.
  # NEVER a silent pass: a missing command is a refusal, not success.
  echo "loom_resolve_command: no $x command defined — neither script/$x (or scripts/$x) nor canonical_commands.$x in .claude/project-constitution.md. Define one before relying on \`$x\`." >&2
  return 1
}
