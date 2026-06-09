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

# shellcheck source=../lib/loom-hook-helpers.sh
. "$HOME/.claude/lib/loom-hook-helpers.sh" 2>/dev/null || \
  . "$(dirname "${BASH_SOURCE[0]}")/../lib/loom-hook-helpers.sh"

# Bypass — literal "1" only (loom-b1l convention).
if loom_env_enabled LOOM_CWD_DRIFT_GUARD_SKIP; then
  exit 0
fi

INPUT=$(cat)

# Parse tool name + command. jq if available, fallback to grep.
TOOL=$(json_get '.tool_name' 'tool_name' "$INPUT")
CMD=$(json_get '.tool_input.command' 'command' "$INPUT")

# Bash-only.
[ "$TOOL" = "Bash" ] || exit 0

# Empty command → let underlying handle.
[ -n "$CMD" ] || exit 0

# Worker-context exemption (loom-ehv, 2026-05-27).
# Claude Code's PreToolUse payload carries optional top-level
# `agent_id` / `agent_type` fields when the hook fires inside a
# subagent (Task-tool spawn — see https://code.claude.com/docs/en/hooks
# "PreToolUse Hook JSON Input"). Workers legitimately operate from
# their own `.claude/worktrees/agent-<id>/` worktree; the central-drift
# assumption only applies to the ORCHESTRATOR's persistent-bash
# session. Suppress the guard when either marker is a non-empty string.
#
# Why inline (not lib/subagent-detect.sh): that helper keys off
# `isSidechain` / `parentUuid` / `source` — fields present in
# SessionStart payloads but NOT documented in PreToolUse. Different
# schemas, different signals. Inlining keeps the guard self-contained.
AGENT_ID=$(json_get '.agent_id' 'agent_id' "$INPUT")
AGENT_TYPE=$(json_get '.agent_type' 'agent_type' "$INPUT")
if [ -n "$AGENT_ID" ] || [ -n "$AGENT_TYPE" ]; then
  exit 0
fi

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
