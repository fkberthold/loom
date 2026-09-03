---
description: "List + prune orphan agent worktrees (stale .claude/worktrees/agent-* whose dispatching process is dead) and leftover background bash processes left behind by finished/crashed dispatches. Surfaced by the worktree-bg-inventory sensor (WT/BG:N in the statusline)."
disable-model-invocation: true
---

Orphan-cleanup ritual. The user invoked `/cleanup-orphans` (often
after the `worktree-bg-inventory` sensor surfaced a `WT/BG:N` chip in
the statusline, or after a mid-dispatch crash). The job: enumerate the
stale agent worktrees + leftover background processes, prune the ones
that meet the orphan test, and report what went. This closes the gap
`finishing-a-development-branch` leaves — it closes+merges a bead but
never sweeps the live worktree/process inventory (loom-z3m.7).

**Posture: apply the orphan test, prune, then report.** `git worktree
remove` and `kill` are destructive, so the test that picks the targets
has to be mechanical, and it is. A dead lock PID, a closed bead, a
branch already merged into main. None of that turns on something the
user knows and this command doesn't, so it reports the sweep instead of
negotiating it.

Run every step from the MAIN repo root, not inside a worktree. If `pwd`
shows a `.claude/worktrees/agent-*` path, `cd` to the main root first.
The cwd-drift guard backstops this.

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

## 3. Sort the inventory

Read orphanhood off the inventory rather than putting it to the user.
A worktree is an orphan when its locking PID is dead, or when its bead
is closed and its branch is already merged into main. A background
process is a leftover when it matches the pattern and no live dispatch
owns it, and anything matching `bd-post-rewrite` after a `TaskStop` is
one by definition.

If nothing matched either test, say so and stop.

## 4. Prune

Worktrees. Commit any WIP first, then remove the tree, then drop the
branch if it's fully merged:

```bash
# For each orphan worktree path $WT:
# A dirty tree gets its WIP committed on its own branch before removal.
# That is strictly safer than asking about it: the commit costs nothing,
# and it turns "discard or keep?" into a question with one answer.
if [ -n "$(git -C "$WT" status --porcelain)" ]; then
  git -C "$WT" add -A
  git -C "$WT" commit -q -m "WIP salvaged by /cleanup-orphans"
fi
git worktree remove "$WT"
git worktree prune                   # clean up any stale admin entries
# Drop the now-unreferenced branch only when it is fully merged:
git branch -d frank/<bead-id>        # -d refuses unmerged, which is the point
```

The two halves interlock, which is what makes the salvage safe without
a prompt. Committing the WIP leaves the branch ahead of main, so the
`git branch -d` below it refuses to delete the branch and the work
stays reachable by name. Never use `-D` here. It's the one flag that
turns this sequence back into a question.

Background processes. Terminate gently, then escalate only if the
process ignored the signal:

```bash
# For each leftover pid $PID:
kill "$PID" 2>/dev/null              # SIGTERM first
sleep 1
kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null   # only if it survived
```

## 5. Report the sweep

Say what went, one line per class, naming the branches:

> Pruned 3 orphan worktrees (`frank/loom-a1b`, `frank/loom-c2d`,
> `frank/loom-e3f`) and killed one leftover `bd-post-rewrite`.
> `frank/loom-c2d` had uncommitted WIP, so I committed it on the branch
> before removing the tree and left the branch in place.

Name the branches every time. Pruning a worktree is the one action here
the user might have wanted pointed somewhere else, and the branch name
is what they need to go get it.

## 6. Re-inventory + clear the chip

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
  steps 1-2 and don't prune.
