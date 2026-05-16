# Session Startup — Prime beads + MemPalace, surface ready work and relevant skills

After `/clear`, after context compaction, or when opening a new session in a project that uses beads (`bd`) and MemPalace, run this routine before doing any other work. It rebuilds the picture future-you needs: what's queued, what was decided, and which process skill the next move calls for.

## When to use

- Session just started (first user prompt of a conversation)
- After `/clear` or context compaction
- Returning to a project after time away
- User says "let's pick up where we left off" / "what's next"
- You feel uncertain about project state and ad-hoc grepping won't fix it

**Skip when:** mid-task in an established session — this is for cold starts, not interruptions.

## Workflow modes (v1.5)

Check the resolved mode early via `~/.claude/scripts/workflow-state mode`
(reads `<project>/.claude/workflow.json` with env `CLAUDE_WORKFLOW_OFF=1`
override):

- **full** — run all 9 steps below. Default.
- **light** — run an abbreviated routine: `bd stats` + `bd ready -n 10` +
  `bd list --status=in_progress` + CI health (step 1a) + reconcile + pick.
  Skip palace status/KG-stats/diary-deep-dive (steps 3-4) unless the user
  asks. Tell the user: "workflow mode is light; abbreviated startup."
- **off** — skip the skill entirely. Acknowledge: "workflow mode is off;
  startup skill disabled. Use `bd ready` directly if needed." Don't
  prime the palace or pick a bead unless the user asks explicitly.

If the SessionStart onboarding hook just asked the user to pick a mode
(no `<project>/.claude/workflow.json`), surface that prompt and resolve
it before running the rest of this skill.

## Steps

1. **Prime beads.** Run `bd prime` (auto-fires on session start in Claude Code, but explicit fallback never hurts). Then `bd stats` for health and `bd ready -n 10` for unblocked work.

1a. **Check CI health.** Run `gh run list --limit 3 --branch main --json status,conclusion,name,headSha,createdAt` (or the equivalent for the project's default branch). If any of the last 3 runs has `conclusion: failure`, surface to the user as a single warning line: workflow name, short commit SHA, age. A red workflow from a prior session that sat unnoticed is the failure mode this step exists to prevent (loom-59w: Deploy docs sat red for 2 days before being noticed). Tolerance: if `gh` is not installed, not authenticated, or the call errors for any reason, emit `(gh unavailable — CI check skipped)` and continue. **Never fail the skill on this step.** The check stays in `light` mode too (cheap, high-signal); `off` mode skips it along with the rest of the skill.
2. **Check in-progress.** Run `bd list --status=in_progress`. Anything there outranks the ready queue — finish what was started.
3. **Prime palace.** Call `mempalace_status` and `mempalace_kg_stats`. Note wing/room shape; flag anything weird (zero drawers, zero current facts).
4. **Recover recent context.** Three sub-steps:
   - Run `mempalace_search` for "session close" / "next session" / "fresh session onboarding" or any project-specific START-HERE drawer.
   - Run `mempalace_diary_read("claude-opus", 3)` (substitute your own agent name) to recover introspective continuity from prior sessions. Diary entries are AAAK-compressed and cheap to scan; they often surface design pivots and learning that decision drawers don't.
   - Read the latest decision drawers in the project's wing from the last ~24 hours.

4a. **Surface zombie work + project tribal knowledge.** Two more queries that round out the picture:
   - `bd stale --status in_progress --days 7` — surfaces in-progress beads that haven't moved recently. Anything here is either real in-flight work that needs resumption, or a forgotten claim that should be unclaimed.
   - `bd memories <project-keyword>` — pulls one-line tribal facts that auto-injected at `bd prime` but may need re-surfacing if the keyword wasn't in the prime context. Boundary (per the workflow infrastructure plan): `bd memories` for tribal one-liners; MemPalace drawers for multi-paragraph decisions.
5. **Reconcile.** Compare what `bd ready` says with what the most recent diary/decision drawers recommend as the entry point. They should agree. If they don't (e.g., a drawer points at a now-closed bead), flag the divergence to the user.
6. **Pick a bead.** Default = top of `bd ready`. If user named a bead, use that. Run `bd show <id>` for context.
7. **Surface the right process skill** for the chosen bead BEFORE acting:

| Bead shape | Skill to invoke |
|---|---|
| Design work, new feature, "build X" | `superpowers:brainstorming` or `beadpowers:brainstorming` |
| Implementation with tests required | `superpowers:test-driven-development` |
| Bug, test failure, unexpected behavior | `superpowers:systematic-debugging` |
| Filing many beads from a finished design | `beadpowers:create-beads` |
| Independent parallel work streams | `superpowers:dispatching-parallel-agents` |
| Implementation that warrants isolation | `superpowers:using-git-worktrees` |
| Plan execution with review checkpoints | `superpowers:executing-plans` |
| Verifying completion before commit | `superpowers:verification-before-completion` |

8. **Confirm intent.** Tell the user the bead, the process skill, and the immediate next action (1-2 sentences). Wait for `yes` / redirect before claiming or coding.

9. **Hand off to the bead-execution recipe.** Once the user confirms the bead, invoke the activity recipe matching the bead's shape (today: `bugfix-a-bead`; coming: `feature-a-bead`, `refactor-a-bead`, `research-a-bead`, `cleanup-a-bead`, `docs-a-bead`) — or have the user trigger `/working-a-bead <id>` once the router lands. The recipe defers to `bead-lifecycle-shell` for phases A (search + claim), B (verification), C (commit + finish-branch), and D (close + capture); the recipe itself only owns the activity-specific variable middle. The lookup table in step 7 is the *index* into the right recipe.

## Example

```
User: /clear
[hooks fire bd prime automatically]
User: ok pick up where we left off

You: [run bd stats, bd ready, bd list --status=in_progress, mempalace_status,
      mempalace_search for "session close 2026-..."]
     [read top diary entry + latest decision drawer]

You: bd ready leads with 13p.4.2 (P0, MemPalace drawer rewrites). The latest
     session-close drawer recommends doing this before any other work because
     the old PHASE 4 START HERE drawer is misleading future sessions. No
     in_progress beads. I'll use superpowers:brainstorming if any drawer rewrites
     need design judgment, otherwise straight edits. Proceed?
```

## Critical

- **Don't skip MemPalace.** `bd ready` shows queue; the palace shows *why* the queue looks that way. Acting on bead state alone has bitten this workflow before — the bead's description may be stale relative to the most recent decision drawer.
- **Reconcile before acting.** If a drawer says "start with X" and X is closed, the drawer is stale and the queue is right. Surface the mismatch — it's usually a sign that 13p.4.2-style cleanup work is itself the next priority.
- **Process skill before action.** Per superpowers:using-superpowers / beadpowers:using-beadpowers — the relevant skill must be invoked before coding or filing. This step is where it happens.
- **Confirm before claiming.** `bd update <id> --claim` is reversible but noisy. Don't claim until the user signs off on the bead choice.
- **Don't run this skill mid-task.** Designed for cold starts. Mid-session use wastes context.
- **Search MemPalace at the design moment, not just at session start.** The cold-start search recovers context; the bead-claim search recovers patterns. Both matter. The `bead-lifecycle-shell` skill enforces the second search at phase A1 (called by every activity recipe); this cold-start skill only covers the first.
