---
description: "List + prune orphan agent worktrees (stale .claude/worktrees/agent-* whose dispatching process is dead) and leftover background bash processes left behind by finished/crashed dispatches. Surfaced by the worktree-bg-inventory sensor (WT/BG:N in the statusline)."
disable-model-invocation: true
---

Orphan-cleanup ritual. The user invoked `/cleanup-orphans` (often
after the `worktree-bg-inventory` sensor surfaced a `WT/BG:N` chip in
the statusline, or after a mid-dispatch crash). The job: enumerate the
stale agent worktrees + leftover background processes, present them,
and prune the ones the user confirms. This closes the gap
`finishing-a-development-branch` leaves — it closes+merges a bead but
never sweeps the live worktree/process inventory (loom-z3m.7).

**Posture: enumerate-then-confirm, never auto-destroy.** `git worktree
remove` and `kill` are destructive. List first, let the user choose,
prune only what they confirm. Run every step from the MAIN repo root
(not inside a worktree — `cd` there first if `pwd` shows a
`.claude/worktrees/agent-*` path; the cwd-drift guard backstops this).

## 1. Enumerate orphan worktrees

List every linked worktree and flag the orphans — agent worktrees
(`.claude/worktrees/agent-*`) whose locking dispatcher PID is dead, or
whose checked-out bead is already closed/merged.

```bash
# ORPHAN-WORKTREES:START — list agent worktrees + liveness of their lock pid.
git worktree list --porcelain 2>/dev/null | awk '
  /^worktree /   { wt=$2 }
  /^branch /     { br=$2 }
  /^locked /     {
    pid=""
    if (match($0, /\(([a-z]+ )?[0-9]+/)) {
      s=substr($0, RSTART, RLENGTH); gsub(/[^0-9]/,"",s); pid=s
    }
    if (wt ~ /\/\.claude\/worktrees\/agent-/) {
      print wt "\t" br "\t" pid
    }
  }
' | while IFS=$'\t' read -r wt br pid; do
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      alive="ALIVE(pid $pid)"
    else
      alive="DEAD(pid ${pid:-?})  <- ORPHAN candidate"
    fi
    printf '  %s  [%s]  %s\n' "$wt" "$br" "$alive"
done
# ORPHAN-WORKTREES:END
```

Cross-check each candidate's branch against bd: a worktree whose bead
is `closed` (and whose branch is merged into main) is a strong prune
candidate even if the locking process happens to still be alive. For a
branch `frank/<bead-id>`, run `bd show <bead-id>` and
`git branch --merged main | grep <branch>` to confirm.

## 2. Enumerate leftover background processes

List long-running background bash processes the session (or a dead
dispatch) left behind — the orphan classes called out in
`.claude/rules/dispatched-agents.md` (concurrency-caution): orphaned
`bd-post-rewrite` children that survived a `TaskStop`, runaway suite/
loop runners, etc.

```bash
# ORPHAN-BGPROCS:START — list candidate leftover bg procs.
# Tunable pattern; widen if a project spawns differently-named loops.
PATTERN="${LOOM_BG_PROC_PATTERN:-bd-post-rewrite|loom-.*loop}"
pgrep -fa "$PATTERN" 2>/dev/null || echo "  (none matched /$PATTERN/)"
# ORPHAN-BGPROCS:END
```

Treat anything matching `bd-post-rewrite` as a high-priority kill
target after any `TaskStop` (it races on git/bd state and yields false
suite numbers — the loom-fx9m finding).

## 3. Present + confirm

Show the user the orphan worktrees and bg procs found. For each, ask
whether to prune. Group them so a single "yes, all" is possible, but
never assume it. If nothing was found, say so and exit.

## 4. Prune (only what the user confirmed)

Worktrees — remove + drop the branch if it's fully merged:

```bash
# For each CONFIRMED orphan worktree path $WT:
git worktree remove "$WT"            # add --force only if the user OKs a dirty tree
# git worktree remove --force "$WT"  # use when $WT has uncommitted/untracked WIP the user discarded
git worktree prune                   # clean up any stale admin entries
# Optionally drop the now-unreferenced branch if merged:
# git branch -d frank/<bead-id>      # -d refuses unmerged; use -D only on explicit OK
```

Background processes — terminate gently, then escalate only if needed:

```bash
# For each CONFIRMED leftover pid $PID:
kill "$PID" 2>/dev/null              # SIGTERM first
# kill -9 "$PID"                     # SIGKILL only if it ignores SIGTERM and the user OKs
```

If WIP in a dirty worktree needs preserving across the removal, surface
that to the user BEFORE `--force` — offer to commit it on its branch or
stash it first. Never `--force`-remove a dirty worktree silently.

## 5. Re-inventory + clear the chip

After pruning, re-run step 1's snippet to confirm the orphans are gone,
then refresh the sensor's count so the statusline chip clears:

```bash
~/.claude/scripts/workflow-state set orphan_pressure=0
```

The next `worktree-bg-inventory` PreToolUse fire will re-measure
anyway; this just clears the chip immediately for the user.

## What to skip

- A worktree whose locking PID is ALIVE and whose bead is still
  open/in_progress is an active dispatch — do NOT prune it. Leave it.
- The MAIN worktree (`/repos/<project>`) and the current session's own
  worktree are never prune targets.
- If the user only wants the listing (a dry inventory), stop after
  steps 1-2 and don't prompt to prune.
