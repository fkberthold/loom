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
  in-progress RESUME header (step 1a) + since-last-session digest (step 1b,
  only fires on >3-day gap) + CI health (step 1c) + active-design-cycle scan
  (step 1d) + active-explorations scan (step 1e) + `bd list --status=in_progress` + reconcile + pick. Skip palace status/KG-stats/diary-deep-dive (steps 3-4)
  unless the user asks. Tell the user: "workflow mode is light; abbreviated
  startup."
- **off** — skip the skill entirely. Acknowledge: "workflow mode is off;
  startup skill disabled. Use `bd ready` directly if needed." Don't
  prime the palace or pick a bead unless the user asks explicitly.

If the SessionStart onboarding hook just asked the user to pick a mode
(no `<project>/.claude/workflow.json`), surface that prompt and resolve
it before running the rest of this skill.

## Steps

1. **Prime beads.** Run `bd prime` (auto-fires on session start in Claude Code, but explicit fallback never hurts). Then `bd stats` for health and `bd ready -n 10` for unblocked work.

1a. **Surface in-progress work first — "RESUME?" header.** Run `bd list --status=in_progress --json` and parse each entry's id, title, and updated/last-touched timestamp. For each in_progress bead, also surface a recency cue from the last diary entry (via `mempalace_diary_read("claude-opus", 3)` or project-agent-wing equivalent) when the diary timestamp lines up with the bead's last_touched window. Print a single block:

   ```
   RESUME? In-progress beads outrank fresh-ready work:
     - <id> "<title>" — last touched <age> · diary: "<one-line summary>"
   ```

   Resume cues outrank ready-bead selection — a half-finished bead is almost always the right next move (loom-z3m.1 f4: liza_base-n7pb sat in_progress unnoticed across sessions until the user surfaced it manually). **Skip the header entirely if `bd list --status=in_progress --json` returns an empty array** — no in_progress means nothing to resume; emitting an empty "RESUME?" block on every cold-start is just noise. Tolerance: if `bd list` errors, emit `(bd in_progress check skipped)` and continue. **Never fail the skill on this step.**

1b. **Since you were last here — long-gap digest.** Detect time since the last user prompt: prefer the mtime of the latest `~/.claude/projects/<slug>/*.jsonl` transcript file; fall back to message-timestamp parsing inside that file. If the gap is **>3 days**, emit a "Since you were last here:" digest combining:

   - `bd list --status=closed --since="<gap_start>"` — what shipped while away
   - `mempalace_diary_read("claude-opus", 3)` — recent introspective notes (substitute your own agent wing)
   - `git log --oneline --since="<gap_start>" main` — last N main commits

   Print as one block under a "Since you were last here:" header. Threshold rationale: 3-day gaps are where the user reliably loses local state ("get me up to speed" — loom-z3m.1 f2, HAW user away >1 week). **Skip the digest entirely when the gap is <=3 days** — recent sessions don't need a digest, the user still has the context. Tolerance: if any sub-call errors (no transcript dir, mempalace offline, git log fails), degrade that sub-line to `(<tool> unavailable)` and continue. **Never fail the skill on this step.** Stays in `light` mode (cheap when triggered, silent when not).

1c. **Check CI health.** Run `gh run list --limit 3 --branch main --json status,conclusion,name,headSha,createdAt,databaseId` (or the equivalent for the project's default branch). If any of the last 3 runs has `conclusion: failure`, surface to the user as a single warning line: workflow name, short commit SHA, age. **Only when a failure is detected**, additionally run `gh run view <databaseId> --json conclusion,jobs` for the latest failing run and print the first non-success job's name plus a one-line failure summary (failure line / failing step name) inline with the warning. Skip the `gh run view` call when CI is green (don't burn API calls on healthy state). A red workflow from a prior session that sat unnoticed is the failure mode this step exists to prevent (loom-59w: Deploy docs sat red for 2 days before being noticed); the inline job-name + summary keeps the user from a follow-up roundtrip (loom-z3m.1 f1: "the build keeps failing in GHA. Building docs I believe."). Tolerance: if `gh` is not installed, not authenticated, or the call errors for any reason, emit `(gh unavailable — CI check skipped)` and continue. **Never fail the skill on this step.** The check stays in `light` mode too (cheap, high-signal); `off` mode skips it along with the rest of the skill. Note this step verifies the Deploy-docs run STATUS (build-green), not that the published site actually SERVES — a green run can still 404 if GitHub Pages is disabled (the 2026-06-08 silent-green outage). The serving layer (HTTP 200 / Pages `status=built`) is the wrap-up-time complement: `scripts/loom-docs-serving-check` (loom-7q1g, surfaced at Phase D1b of `bead-lifecycle-shell`), which probes actual serving on full-Diataxis projects.

1d. **Surface active design cycles — "ACTIVE DESIGN CYCLE" header.** A `/design-a-cycle` orchestrator is an *above-bead* unit: it iterates, spawns research beads + an implementation epic, and has no single RED→GREEN — so it is **not a bead**, and `bd ready` / `bd list --status=in_progress` will never surface it. Its state lives in an L2 **DESIGN DOC** drawer in the project's `<wing>/decisions` room, under a STATE HEADER block. Discover any *active* cycle so a cold-start resumes the design, not just the bead queue. Scan via `mempalace_search` (or `mempalace_list_drawers` for the project wing) for DESIGN DOC drawers — e.g. search `"DESIGN DOC STATE HEADER [CLARIFICATION] soundness"` scoped to the project wing — and treat a cycle as **active** when its STATE HEADER shows EITHER unresolved `[CLARIFICATION]` markers OR `soundness-status` != `green`. For each active cycle, print one line:

   ```
   ACTIVE DESIGN CYCLE: <topic> — cycle N, soundness <status>, M open markers, K research beads open
   ```

   Derive each field from the STATE HEADER block (`cycle-number`, `soundness-status`, the `open [CLARIFICATION] markers` list → M, the `spawned research-bead IDs` list → K; count K's still-open IDs via `bd list` when cheap, else report the listed count). A drawer whose STATE HEADER is fully resolved (no open markers AND soundness green) is *complete* — skip it. Resume a half-finished design cycle the same way an in-progress bead outranks fresh-ready work: an open cycle with unresolved markers is usually the right next move. This step is **INFO-only** — it surfaces context, it never claims or advances a cycle on its own. **Skip the header entirely when no active design cycle is found** — don't emit an empty "ACTIVE DESIGN CYCLE" block on every cold-start. Tolerance: if MemPalace is offline, the search errors, or the project has no design drawers, emit `(design-cycle check skipped)` (or nothing) and continue. **Never fail the skill on this step.** Stays in `light` mode too (cheap MemPalace scan, high-signal); `off` mode skips it along with the rest of the skill.

1e. **Surface active explorations — "ACTIVE EXPLORATION" header.** An *exploration* (opened via `/explore <idea>`) is a NEW above-bead, SUB-design primitive — the permissive front-door to `/design-a-cycle`, with NO soundness gate. Like a design cycle, an exploration is **not a bead** and has no single RED→GREEN, so `bd ready` / `bd list --status=in_progress` will never surface it. Its memory is ONE drawer in the project's `<wing>/decisions` room (loom's own lives in wing `loom`, room `decisions`), tagged `exploration` (tag-not-room), carrying a STATUS of `active` | `rested` | `promoted`. Discover any *active* exploration so a cold-start resumes the thinking, not just the bead queue. Scan via `mempalace_search` (or `mempalace_list_drawers` for the project wing) for drawers tagged `exploration` — the same way step 1d scans DESIGN DOC drawers — e.g. tag-filter on `exploration` scoped to the project wing, and treat an exploration as **active** only when its `status=active`. For each active exploration, print one line:

   ```
   ACTIVE EXPLORATION: <topic> — <N> open threads · understanding: "<current-understanding snippet>"
   ```

   Derive each field from the exploration drawer (the topic, the `open threads` list → N open-threads count, the `current understanding` section → snippet). **SKIP rested and promoted explorations** — `rested` and `promoted` are terminal states (a `rested` exploration was deliberately set aside; a `promoted` one already opened a `/design-a-cycle`), so surfacing them would be noise. Resume a half-finished exploration the same way an open design cycle outranks fresh-ready work: an `active` exploration is usually the right next move. This step is **INFO-only** — it surfaces context, it never claims or advances an exploration on its own. **Skip the header entirely when no active exploration is found** — don't emit an empty "ACTIVE EXPLORATION" block on every cold-start. Tolerance: if MemPalace is offline, the search errors, or the project has no exploration drawers, emit `(exploration scan skipped)` (or nothing) and continue. **Never fail the skill on this step.** Stays in `light` mode too (cheap MemPalace scan, high-signal); `off` mode skips it along with the rest of the skill.
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

6a. **Propose a parallel wave when ready beads are independent (fan-out detector).** Run `scripts/loom-fanout-detect`. It reads `bd ready --json` + each candidate's `bd show <id> --json`, and emits — one wave per line, space-separated IDs — each group of ready beads that have **NO dependency edge between them AND NO overlapping `Files:` path**. Beads with no `Files:` line declared are excluded (conservative: footprint unknown → not provably disjoint). When it emits a wave of ≥2 beads, surface this as the **DEFAULT** proposal *before* falling back to the serial single-bead pick from step 6:

   ```
   loom-X / loom-Y / loom-Z are independent (no dep edge, disjoint Files:).
   Dispatch N parallel workers? [y / edit / serial]
   ```

   - `y` → hand off to `superpowers:dispatching-parallel-agents`, one worker per bead in the wave.
   - `edit` → let the user prune/add beads, then dispatch the adjusted set.
   - `serial` → fall back to the single-bead pick (step 6).

   This is a **proposal, not an auto-dispatch** — central never fans out workers without the user's go-ahead (loom's nudge-not-block design). Why this step exists: `bd ready` is otherwise popped as a serial queue, so independence computed at bead *creation* (the splitting heuristic) is never re-surfaced at *work* time, and central does parallelizable beads one-at-a-time inline (loom-yb5; the bn7 session was all-inline/all-serial — exhibit A). The detector only sees beads that declare `Files:`; nudge under-declaring beads toward the convention rather than silently dropping them. Tolerance: if `scripts/loom-fanout-detect` is absent, `jq` is missing, or it errors, emit nothing and continue to step 7. **Never fail the skill on this step.**
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
| Upstream PR or issue contribution | `upstream-a-bead` |

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
