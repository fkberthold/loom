#!/usr/bin/env bash
# lib/loom-wing-resolve.sh — resolve a project's MemPalace wing.
#
# loom-pc3x's invariant: every site that derives a project's wing reads
# it from ONE declared source, so no two sites can disagree for the same
# project. This file IS that source. Call sites source it and call
# `loom_wing_resolve`; none of them re-derives the chain locally.
#
# THE CHAIN (decided by Frank 2026-08-21, amended and then shortened the
# same day, recorded on loom-pc3x and loom-6fyj):
#
#   1. explicit --wing flag
#   2. <root>/mempalace.yaml              wing:
#   3. .claude/project-constitution.md    wing:
#   4. basename $root
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
# root is in hand, and rung 4 says so.
#
# WHY THE PREFIX IS NOT A RUNG AT ALL (loom-6fyj, the same day). It went
# below the basename first, then off the chain. The step in between is
# worth stating, because it is why the flag went too. Rung 4 takes
# `basename $root` and the root policy below always yields a root, so
# rung 4 always answers. A rung under it can never fire, and the
# bd-prefix flag fed exactly that rung. The flag parsed, the usage block
# described it, and no value a caller passed could change a single
# answer. That is worse than no flag, because it reads like a contract
# the code has quietly declined to honor.
#
# `loom_wing_from_bd_prefix` stays exported, because the caller the
# prefix was written for does not want a ranked answer at all.
# hooks/bd-close-capture.sh resolves a wing when cwd is not the project
# repo, holding a bead id and no root it trusts. It already builds a
# CANDIDATE SET, and loom-qw9i has it join this function's answer to that
# set rather than asking the chain to rank one. A building block suits
# that caller. A rung never did.
#
# DUAL MODE. The file is both a sourceable library and an executable CLI,
# following lib/bd-id-extract.sh. Sourcing it defines the functions and
# does nothing else.
#
# Functions (sourceable):
#   loom_wing_resolve [flags]              echo the resolved wing
#   loom_wing_resolve_kv [flags]           echo wing= and wing_source=
#   loom_wing_project_root [dir]           the root policy, on its own
#   loom_wing_from_mempalace_yaml <root>   rung 2 alone (rc 1 if absent)
#   loom_wing_from_constitution <root>     rung 3 alone (rc 1 if absent)
#   loom_wing_from_bd_prefix <root>        the bd prefix, off the chain
#                                          (rc 1 if there is no tracker)
#
# Flags (shared by both resolve functions and by the CLI):
#   --root <path>       project root. Precedence: explicit --root →
#                       `loom_wing_project_root` → $PWD. A nonexistent
#                       explicit --root is an error, and an explicit one
#                       is never redirected (loom-l78w).
#   --wing <name>       rung 1. Wins over everything below it.
#
# Every flag here can change the answer, and that is a tested invariant
# (loom-6fyj, section 14 of lib/tests/loom-wing-resolve.test.sh). Adding
# one means showing it does something.
#
# CLI output (stdout, one key=value per line):
#   wing=<name>
#   wing_source=<flag|mempalace_yaml|constitution|basename>
#
# Exit codes:
#   0   resolved (rung 4 always yields something, so this is the norm)
#   2   bad flag, or an explicit --root that is not a directory
#
# Lineage: loom-pc3x (the chain), loom-kpke (the P1 that forced it),
# loom-6fyj (dropping the rung that could not fire).

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
# The bd prefix — a building block, not a rung
# ---------------------------------------------------------------------

# Load lib/bd-id-extract.sh on demand. Prefix parsing is that file's job
# (loom-6mf7: parse sites adopt its functions instead of guessing at a
# character class), and the chain below never calls it, so the load
# happens only when a caller asks for the prefix directly.
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
# Root defaulting — the MAIN checkout, never a linked worktree
# ---------------------------------------------------------------------

# _loom_wing_abs_dir <base> <path> — canonicalize a path git reported.
#
# git answers these relative as often as absolute, and not consistently
# between them: at a repo root `--git-dir` and `--git-common-dir` both
# say `.git`, but one directory down the first says `/abs/repo/.git`
# while the second says `../.git`. Comparing the two raw would call
# every subdirectory of every ordinary checkout a linked worktree, so
# both sides come through here first.
_loom_wing_abs_dir() {
  local base="$1" p="$2"
  [ -n "$p" ] || return 1
  case "$p" in /*) ;; *) p="$base/$p" ;; esac
  [ -d "$p" ] || return 1
  ( cd "$p" && pwd -P )
}

# loom_wing_project_root [dir] — the root to resolve against when the
# caller named none. Defaults to $PWD's.
#
# Inside a LINKED WORKTREE the plain toplevel is the worktree's own
# directory, and every rung below then reads the worktree: rung 4 takes
# its basename and answers `agent-<hash>`, while rungs 2 and 3 hunt for
# a mempalace.yaml and a constitution the worktree's branch need not
# carry. A worktree of loom is loom, and `agent-<hash>` is not a wing —
# it names a directory that will not exist next week, so filing there
# splits the project's memory the same way loom-kpke did (loom-l78w).
#
# Correcting the ROOT rather than rung 4 is the point. Rungs 2 and 3 are
# there to read the project's own declarations, and a rung-4 special
# case would have left both of them reading the worktree.
#
# git tells the two apart: --git-dir and --git-common-dir differ only
# inside a linked worktree, and the main checkout is the common dir's
# parent. That parent is CONFIRMED against git before it is used, so a
# layout where the common dir is not `<root>/.git` (--separate-git-dir,
# an exported GIT_DIR) falls back to the plain toplevel instead of
# guessing a root out of a path shape.
#
# This governs the DEFAULT only. An explicit --root is passed through
# untouched: a caller that names a worktree path on purpose is asking a
# different question from one that named nothing, and gets the answer it
# asked for.
loom_wing_project_root() {
  local dir="${1:-$PWD}"
  local top gitdir common cand cand_top cand_common

  top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)
  if [ -z "$top" ]; then printf '%s\n' "$dir"; return 0; fi

  gitdir=$(_loom_wing_abs_dir "$dir" "$(git -C "$dir" rev-parse --git-dir 2>/dev/null)") \
    || { printf '%s\n' "$top"; return 0; }
  common=$(_loom_wing_abs_dir "$dir" "$(git -C "$dir" rev-parse --git-common-dir 2>/dev/null)") \
    || { printf '%s\n' "$top"; return 0; }

  # Equal means an ordinary checkout. Nothing to redirect.
  if [ "$gitdir" = "$common" ]; then printf '%s\n' "$top"; return 0; fi

  cand=$(dirname "$common")
  cand_top=$(git -C "$cand" rev-parse --show-toplevel 2>/dev/null)
  cand_common=$(_loom_wing_abs_dir "$cand" "$(git -C "$cand" rev-parse --git-common-dir 2>/dev/null)")
  if [ -n "$cand_top" ] && [ "$cand_common" = "$common" ]; then
    printf '%s\n' "$cand_top"
    return 0
  fi

  printf '%s\n' "$top"
}

# ---------------------------------------------------------------------
# The chain
# ---------------------------------------------------------------------

loom_wing_resolve_kv() {
  local root_flag="" wing_flag=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --root=*)      root_flag="${1#--root=}" ;;
      --root)        shift; root_flag="${1:-}" ;;
      --wing=*)      wing_flag="${1#--wing=}" ;;
      --wing)        shift; wing_flag="${1:-}" ;;
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
    root=$(loom_wing_project_root "$PWD")
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

  # Rung 4, the last one. The root policy above always yields a root, so
  # this always answers and the chain has no floor below it. That is why
  # there is no fifth rung here (loom-6fyj): a rung under this one could
  # never fire, and a flag feeding it could never change an answer.
  if [ -z "$wing" ] && [ -n "$root" ]; then
    wing=$(basename "$root")
    src="basename"
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
