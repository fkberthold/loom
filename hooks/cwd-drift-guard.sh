#!/usr/bin/env bash
# PreToolUse hook for Bash. Refuses central-context operations
# (git merge, git push, bd close, bd update, bd dolt push) when
# the current working directory has silently drifted into a
# .claude/worktrees/agent-*/ worker worktree.
#
# Closes loom-d2o. Observed 2026-05-27 during the loom-7p6 + loom-cuk
# parallel-dispatch session: central's persistent-bash cwd resolved
# into a returned worker's worktree without an explicit `cd`. The
# subsequent `bd close` + `git merge --no-ff frank/<bead>` ran from
# the wrong tree — bd state surfaced a permissions warning; merge
# reported 'Already up to date' against the worktree's own HEAD
# instead of main.
#
# Sibling discipline: hooks/edit-write-pwd-guard.sh (loom-ymc) is the
# WORKER-SIDE variant — catches path leaks from a worker writing into
# MAIN. This hook is the CENTRAL-SIDE variant — catches central ops
# emitted from a worktree cwd. Same realpath canonicalization, same
# exit-2 convention, same literal-"1" bypass shape.
#
# Resolution rules:
#   - tool_name != "Bash" → exit 0
#   - cwd realpath NOT under any .claude/worktrees/agent-*/ → exit 0
#   - command does NOT match the central-op allowlist → exit 0
#   - LOOM_CWD_DRIFT_GUARD_SKIP=1 (literal "1") → exit 0
#   - otherwise → exit 2 with recovery message
#
# Central-op allowlist (anchored on command intent, whitespace-
# tolerant, accepts git options between `git` and the subcommand):
#   - git [...] merge
#   - git [...] push
#   - bd [...] close
#   - bd [...] update
#   - bd [...] dolt push
#
# Read-only ops (git status/log/diff/branch, bd list/show/ready/etc.)
# do NOT match — they're safe from any cwd.
#
# Bypass: LOOM_CWD_DRIFT_GUARD_SKIP=1 (literal-1 per loom-b1l)
#   For intentional cross-tree ops (e.g. merge prep from worktree).
#   Rejects =yes/=true/=0/empty by design.

set -uo pipefail

# Bypass — literal "1" only (loom-b1l convention).
if [ "${LOOM_CWD_DRIFT_GUARD_SKIP:-}" = "1" ]; then
  exit 0
fi

INPUT=$(cat)

# Parse tool name + command. jq if available, fallback to grep.
if command -v jq >/dev/null 2>&1; then
  TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""')
  CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
else
  TOOL=$(echo "$INPUT" | grep -oP '"tool_name"\s*:\s*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"/\1/')
  CMD=$(echo "$INPUT" | grep -oP '"command"\s*:\s*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"/\1/')
fi

# Bash-only.
[ "$TOOL" = "Bash" ] || exit 0

# Empty command → let underlying handle.
[ -n "$CMD" ] || exit 0

# Resolve cwd via realpath. The drift signature is a path containing
# .claude/worktrees/agent-<id> somewhere in the resolved chain.
PWD_REAL=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$PWD" 2>/dev/null) || PWD_REAL="$PWD"

# Detect the worktree-cwd signature.
case "$PWD_REAL" in
  */.claude/worktrees/agent-*) ;;
  *) exit 0 ;;
esac

# Extract the worktree root (everything up to and including the
# agent-<id> path segment) for the recovery hint.
WT_ROOT=$(echo "$PWD_REAL" | sed -E 's|(.*/\.claude/worktrees/agent-[^/]+).*|\1|')

# Compute main repo root: the segment before /.claude/worktrees/.
MAIN_ROOT=$(echo "$PWD_REAL" | sed -E 's|(.*)/\.claude/worktrees/.*|\1|')

# Central-op allowlist — anchored on command intent.
#   - command may start with `cd ... &&`, env-vars, etc. — match the
#     *intent* by looking for the bare subcommand sequence anywhere.
#   - `git [opts] merge` / `git [opts] push`
#   - `bd [opts] close` / `bd [opts] update` / `bd [opts] dolt push`
# `\s+` allows multiple spaces; `(--?\S+\s+)*` lets options sit
# between the verb and the subverb.
MATCHED=""
if echo "$CMD" | grep -qE '(^|[;&|[:space:]])git\s+(--?\S+\s+)*merge(\s|$)'; then
  MATCHED="git merge"
elif echo "$CMD" | grep -qE '(^|[;&|[:space:]])git\s+(--?\S+\s+)*push(\s|$)'; then
  MATCHED="git push"
elif echo "$CMD" | grep -qE '(^|[;&|[:space:]])bd\s+(--?\S+\s+)*dolt\s+push(\s|$)'; then
  MATCHED="bd dolt push"
elif echo "$CMD" | grep -qE '(^|[;&|[:space:]])bd\s+(--?\S+\s+)*close(\s|$)'; then
  MATCHED="bd close"
elif echo "$CMD" | grep -qE '(^|[;&|[:space:]])bd\s+(--?\S+\s+)*update(\s|$)'; then
  MATCHED="bd update"
fi

[ -n "$MATCHED" ] || exit 0

# Drift detected.
cat >&2 <<EOF
[cwd-drift-guard] BLOCKED: Bash refused.

  command  = $CMD
  cwd      = $PWD_REAL
  worktree = $WT_ROOT
  matched  = $MATCHED

Central-context operation ($MATCHED) emitted from inside a worker
worktree. This is the loom-d2o silent-cwd-drift: central's persistent-
bash cwd has resolved into a returned worker's worktree without an
explicit \`cd\`. Running this here will mis-route (bd state writes to
the worktree's dolt; \`git merge\` targets the worktree's own HEAD
instead of main; \`git push\` pushes the worker branch, not main).

To recover:
  cd $MAIN_ROOT && <retry command>

To bypass intentionally (rare — e.g. merging FROM the worktree on
purpose), set:
  LOOM_CWD_DRIFT_GUARD_SKIP=1 <command>
EOF
exit 2
