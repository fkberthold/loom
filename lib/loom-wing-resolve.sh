#!/usr/bin/env bash
# lib/loom-wing-resolve.sh — resolve a project's MemPalace wing.
#
# loom-pc3x's invariant: every site that derives a project's wing reads
# it from ONE declared source, so no two sites can disagree for the same
# project. This file IS that source. Call sites source it and call
# `loom_wing_resolve`; none of them re-derives the chain locally.
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
# declaration and already carries the wing plus its rooms. Where a
# project wrote one, it beats a guess. Rung 3 exists so the repos that
# already carry a constitution get a home for the wing without anyone
# writing a new file. No project has to move.
#
# WHAT WENT WRONG BEFORE THIS (loom-kpke, P1). Both
# scripts/loom-audit-resolve and scripts/loom-mine-history took
# `basename $root` verbatim and never read mempalace.yaml. Measured on
# tla-puzzles 2026-08-05, both resolved `tla-puzzles`, a wing that does
# not exist. The live wing is `tla_puzzles` with 932 drawers. Nothing
# errored. A mine run without a manual --wing override would have filed
# 144 drawers into a brand-new wrong wing and split the project's memory
# across two spellings.
#
# WHY THE BASENAME OUTRANKS THE BD PREFIX (the 2026-08-21 amendment).
# Measured 2026-08-20 over the 8 repos under ~/repos that carry
# `.beads/issues.jsonl`, the bd prefix and the directory name disagree
# three times, and the directory name is right all three times:
#
#   dreamer-engine   prefix `dream`   wing `dreamer-engine` (1350 drawers)
#   sharedvoice      prefix `sv`      wing `sharedvoice`    (192 drawers)
#   tla-puzzles      prefix `tla`     wing `tla_puzzles`    (via rung 2)
#
# Wings `dream` and `sv` hold nothing. A chain that ranked the prefix
# above the directory name sent two live projects to empty wings, which
# is the defect loom-kpke filed. So the prefix is a poor guess whenever a
# root is in hand, and rung 4 now says so.
#
# Rung 5 is what the prefix was written for: resolving a wing when cwd is
# not the project repo, which is where hooks/bd-close-capture.sh sits
# (loom-qw9i). That caller holds a bead id and no root it trusts.
#
# ONE CONSEQUENCE, STATED PLAINLY. Rung 4 takes `basename $root`, and the
# root policy below always yields a root, so rung 4 always answers and
# the chain never reaches rung 5 today. That is the point of the
# demotion, not a gap in it. A caller that needs the prefix SEARCHED
# rather than ranked last should call `loom_wing_from_bd_prefix` and add
# the answer to its own candidate list, which is what loom-qw9i asks
# bd-close-capture to do. `--bd-prefix <p>` stays parsed and honored so
# that caller can hand its prefix in without a second code path.
#
# The rung is no longer opt-in. The opt-in was a precedence workaround
# wearing a flag: with the prefix above the basename, the only thing
# stopping it from beating the directory name was a caller choosing not
# to ask. Rung order does that job now, so the guard guards nothing and
# rung 5 detects a prefix on its own when it is reached.
#
# DUAL MODE. The file is both a sourceable library and an executable CLI,
# following lib/bd-id-extract.sh. Sourcing it defines the functions and
# does nothing else.
#
# Functions (sourceable):
#   loom_wing_resolve [flags]              echo the resolved wing
#   loom_wing_resolve_kv [flags]           echo wing= and wing_source=
#   loom_wing_from_mempalace_yaml <root>   rung 2 alone (rc 1 if absent)
#   loom_wing_from_constitution <root>     rung 3 alone (rc 1 if absent)
#   loom_wing_from_bd_prefix <root>        rung 5 detection (rc 1 if absent)
#
# Flags (shared by both resolve functions and by the CLI):
#   --root <path>       project root. Precedence: explicit --root →
#                       `git -C $PWD rev-parse --show-toplevel` → $PWD.
#                       A nonexistent explicit --root is an error.
#   --wing <name>       rung 1. Wins over everything below it.
#   --bd-prefix <p>     rung 5. A literal prefix, which is how a caller
#                       hands one in. The word `auto` asks for the same
#                       detection rung 5 does on its own, so passing it
#                       changes nothing.
#
# CLI output (stdout, one key=value per line):
#   wing=<name>
#   wing_source=<flag|mempalace_yaml|constitution|basename|bd_prefix>
#
# Exit codes:
#   0   resolved (rung 4 always yields something, so this is the norm)
#   2   bad flag, or an explicit --root that is not a directory
#
# Lineage: loom-pc3x (the chain), loom-kpke (the P1 that forced it).

# ---------------------------------------------------------------------
# YAML scalar reading
# ---------------------------------------------------------------------

# _loom_wing_yaml_scalar — read the TOP-LEVEL `wing:` value from stdin.
#
# Top-level means column 0. A `wing:` nested under `rooms:` carries
# leading whitespace and is a room's field, not the project's wing, so
# the anchor is what keeps the two apart. Quotes and a trailing YAML
# comment are stripped. An empty value returns rc 1 so the caller falls
# through to the next rung rather than resolving to the empty wing.
_loom_wing_yaml_scalar() {
  local raw val
  raw=$(grep -m1 -E '^wing:' 2>/dev/null || true)
  [ -n "$raw" ] || return 1
  val="${raw#wing:}"
  val=$(printf '%s' "$val" \
    | sed -e 's/[[:space:]]\{1,\}#.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  case "$val" in
    \"*\") val="${val#\"}"; val="${val%\"}" ;;
    \'*\') val="${val#\'}"; val="${val%\'}" ;;
  esac
  [ -n "$val" ] || return 1
  printf '%s' "$val"
}

# ---------------------------------------------------------------------
# Rung 2 — <root>/mempalace.yaml
# ---------------------------------------------------------------------

loom_wing_from_mempalace_yaml() {
  local root="${1:-$PWD}"
  local f="$root/mempalace.yaml"
  [ -f "$f" ] || return 1
  _loom_wing_yaml_scalar < "$f"
}

# ---------------------------------------------------------------------
# Rung 3 — <root>/.claude/project-constitution.md front matter
# ---------------------------------------------------------------------

# Only the YAML front matter counts. The prose body below it is markdown
# a human wrote, and a line there that happens to start with `wing:` is
# prose, not a declaration. The awk pass hands back the front matter only
# when it finds both fences, so a file with an open fence and no close
# reads as having none.
loom_wing_from_constitution() {
  local root="${1:-$PWD}"
  local f="$root/.claude/project-constitution.md"
  [ -f "$f" ] || return 1
  local fm
  fm=$(awk '
    NR == 1 { if ($0 != "---") exit 1; next }
    /^---[[:space:]]*$/ { closed = 1; exit 0 }
    { buf = buf $0 "\n" }
    END { if (closed) printf "%s", buf }
  ' "$f" 2>/dev/null)
  [ -n "$fm" ] || return 1
  printf '%s' "$fm" | _loom_wing_yaml_scalar
}

# ---------------------------------------------------------------------
# Rung 5 — bd id prefix
# ---------------------------------------------------------------------

# Load lib/bd-id-extract.sh on demand. Prefix parsing is that file's job
# (loom-6mf7: parse sites adopt its functions instead of guessing at a
# character class), and rung 5 sits under a rung that always answers, so
# most calls never need it.
#
# The source ladder puts LOOM_TEST_LIB_DIR first, per the Mode 6 rule in
# .claude/rules/dispatched-agents.md. Without that rung a worker running
# from a worktree loads MAIN's copy through the installed symlink and
# tests pass against code the worker never touched.
_loom_wing_load_bd_id_extract() {
  declare -F bd_id_detect_prefix >/dev/null 2>&1 && return 0
  local self_dir d
  self_dir=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
  for d in "${LOOM_TEST_LIB_DIR:-}" "$HOME/.claude/lib" "$self_dir"; do
    [ -n "$d" ] || continue
    if [ -f "$d/bd-id-extract.sh" ]; then
      # shellcheck source=./bd-id-extract.sh
      . "$d/bd-id-extract.sh" 2>/dev/null && return 0
    fi
  done
  return 1
}

# Read the project's bd prefix out of its own tracker. The guard on
# .beads/issues.jsonl matters: bd resolves a workspace by walking up the
# tree and by honoring BEADS_DIR, so calling it from a directory with no
# tracker can hand back a DIFFERENT project's prefix. That is the
# cross-project mixup this whole chain exists to stop.
loom_wing_from_bd_prefix() {
  local root="${1:-$PWD}"
  [ -f "$root/.beads/issues.jsonl" ] || return 1
  _loom_wing_load_bd_id_extract || return 1
  bd_id_detect_prefix "$root"
}

# ---------------------------------------------------------------------
# The chain
# ---------------------------------------------------------------------

loom_wing_resolve_kv() {
  local root_flag="" wing_flag="" bd_prefix=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --root=*)      root_flag="${1#--root=}" ;;
      --root)        shift; root_flag="${1:-}" ;;
      --wing=*)      wing_flag="${1#--wing=}" ;;
      --wing)        shift; wing_flag="${1:-}" ;;
      --bd-prefix=*) bd_prefix="${1#--bd-prefix=}" ;;
      --bd-prefix)   shift; bd_prefix="${1:-}" ;;
      -h|--help)     loom_wing_resolve_usage; return 0 ;;
      *)
        printf 'loom-wing-resolve: unrecognized argument: %s\n' "$1" >&2
        return 2
        ;;
    esac
    shift
  done

  # ---- resolve root ------------------------------------------------
  local root=""
  if [ -n "$root_flag" ]; then
    if [ ! -d "$root_flag" ]; then
      printf "loom-wing-resolve: --root '%s' is not a directory\n" "$root_flag" >&2
      return 2
    fi
    root=$(cd "$root_flag" && pwd -P)
  else
    root=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)
    [ -n "$root" ] || root="$PWD"
  fi

  # ---- walk the chain ----------------------------------------------
  local wing="" src=""

  if [ -n "$wing_flag" ]; then
    wing="$wing_flag"
    src="flag"
  fi

  if [ -z "$wing" ]; then
    if wing=$(loom_wing_from_mempalace_yaml "$root" 2>/dev/null); then
      src="mempalace_yaml"
    else
      wing=""
    fi
  fi

  if [ -z "$wing" ]; then
    if wing=$(loom_wing_from_constitution "$root" 2>/dev/null); then
      src="constitution"
    else
      wing=""
    fi
  fi

  if [ -z "$wing" ] && [ -n "$root" ]; then
    wing=$(basename "$root")
    src="basename"
  fi

  # Rung 5. Unreachable while rung 4 has a root to take a basename of,
  # which is the whole point of the amendment. It stays wired for the
  # caller the prefix was written for, and `--bd-prefix <p>` is how that
  # caller hands one in.
  if [ -z "$wing" ]; then
    local p="$bd_prefix"
    if [ -z "$p" ] || [ "$p" = "auto" ]; then
      p=$(loom_wing_from_bd_prefix "$root" 2>/dev/null) || p=""
    fi
    if [ -n "$p" ]; then
      wing="$p"
      src="bd_prefix"
    fi
  fi

  printf 'wing=%s\n' "$wing"
  printf 'wing_source=%s\n' "$src"
}

# loom_wing_resolve — the same chain, echoing just the wing. This is the
# form call sites want; loom_wing_resolve_kv is for a caller that also
# needs to know which rung fired.
loom_wing_resolve() {
  local kv rc
  kv=$(loom_wing_resolve_kv "$@")
  rc=$?
  [ "$rc" -eq 0 ] || return "$rc"
  printf '%s\n' "$kv" | sed -n 's/^wing=//p' | head -1
}

# ---------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------

# Print the leading comment block (line 2 through the first blank line).
loom_wing_resolve_usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# Executed, not sourced? Run the CLI. Sourcing stops here, having only
# defined the functions above.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  set -uo pipefail
  loom_wing_resolve_kv "$@"
  exit $?
fi
