# Claude Workflow Manual

> Personal runbook for Frank's Claude Code workflow stack:
> beads + MemPalace + Superpowers + Beadpowers + Claude Code primitives
> (skills, slash commands, hooks, subagents, path-scoped rules).
>
> Written 2026-05-02 after the workflow-infrastructure plan shipped
> (epic `hundred-acre-woods-2st`, commit `c5fa8dc`). Updated 2026-05-03
> for v1.5 (workflow modes + state file + status line; bead
> `hundred-acre-woods-jnd`). Treat this file as the user-facing manual;
> the canonical design lives in MemPalace drawer "WORKFLOW
> INFRASTRUCTURE PLAN" (hundred_acre_woods/decisions wing). When the
> two diverge, MemPalace is design truth and this is usage truth.

---

## Table of contents

1. [Mental model](#1-mental-model)
2. [What's installed and where](#2-whats-installed-and-where)
3. [Daily session lifecycle](#3-daily-session-lifecycle)
4. [The 14-step bead recipe](#4-the-14-step-bead-recipe)
5. [Reference: skills](#5-reference-skills)
6. [Reference: slash commands](#6-reference-slash-commands)
7. [Reference: subagents](#7-reference-subagents)
8. [Reference: hooks](#8-reference-hooks)
9. [Reference: path-scoped rules](#9-reference-path-scoped-rules)
10. [Reference: bd CLI](#10-reference-bd-cli)
11. [Reference: MemPalace MCP tools](#11-reference-mempalace-mcp-tools)
12. [Decision tables](#12-decision-tables)
13. [Bypass mechanisms + known limitations](#13-bypass-mechanisms--known-limitations)
14. [Common scenarios cookbook](#14-common-scenarios-cookbook)
15. [Glossary](#15-glossary)
16. [Where to update what](#16-where-to-update-what)

---

## 1. Mental model

### The four-axis memory model

Each tool persists a different axis of "knowledge that survives sessions."
The synergy is in their handoffs, not in any single tool's depth.

| Tool                    | Owns                                            | Surfaces at                |
|-------------------------|-------------------------------------------------|----------------------------|
| **beads**               | task state + project tribal knowledge           | `bd prime`, explicit query |
| **MemPalace drawers**   | verbatim decisions, lineage, quotes             | manual queries             |
| **MemPalace KG**        | structured S→P→O facts (time-windowed)          | `kg_query` / `kg_timeline` |
| **MemPalace diary**     | per-agent introspective continuity (AAAK)       | `diary_read` (manual)      |
| **superpowers** skills  | process discipline (TDD, debugging, verify)     | when invoked correctly     |
| **beadpowers** skills   | design → bead pipeline                          | when invoked correctly     |
| **Claude Code primitives** | the connective tissue between all of the above | various lifecycle events |

### The rule

> **The discipline can't be skipped because the primitives enforce it.**

Slash commands fire skills; skills load on demand; hooks fire on
lifecycle events automatically; subagents handle isolated work without
bloating the main context. Each tool's output should feed the next
tool's input via a primitive — if you have to remember to do it, the
plan failed.

### When to use this manual

- **Cold start**: read sections 1-3 to get oriented.
- **Starting a new bead**: section 4 (the recipe) + section 14 cookbook.
- **Looking up "what does X do?"**: sections 5-11.
- **Deciding between two tools**: section 12.
- **Something feels wrong**: section 13 (limitations) + section 16
  (where to update what).

### Workflow modes (v1.5, added 2026-05-03)

Not every project wants the full workflow ceremony. v1.5 introduces
three modes resolved from `<project>/.claude/workflow.json`:

| Mode    | Hooks | Skills | Status line | Use case |
|---------|-------|--------|-------------|----------|
| **full**  | all fire | recipe runs | populated | Active project, want all the discipline |
| **light** | informational only (close-capture never blocks) | recipe runs with reduced ceremony + warning | populated | Project where the recipe is too heavy but you want the visibility |
| **off**   | silent | recipe refuses; session-startup skipped | empty | Quick edits, exploratory spikes, projects where the workflow doesn't fit |

**Resolution priority** (first match wins):

1. `CLAUDE_WORKFLOW_OFF=1` env var → `off` (hard escape hatch)
2. `<project>/.claude/workflow.json` `.mode` field → that value
3. Default → `full`

**Ask-once-and-remember**: the SessionStart hook
`workflow-mode-onboarding.sh` detects an unconfigured beads workspace
(no `<project>/.claude/workflow.json`) and asks the agent to ask you
to pick a mode. The answer is written to `workflow.json` and is
remembered for future sessions.

**Quick CLI**:

```bash
~/.claude/scripts/workflow-state mode          # show resolved mode
~/.claude/scripts/workflow-state show          # full state JSON
~/.claude/scripts/workflow-state set stage=verify  # update stage
echo '{"v":1,"mode":"light"}' > .claude/workflow.json   # change mode
```

### State file + status line (v1.5, added 2026-05-03)

A per-project state file at `<project>/.claude/workflow-state.json`
records the agent's current activity + bead + recipe stage:

```json
{
  "v": 1,
  "mode": "full",
  "activity": "feature",
  "bead": "hundred-acre-woods-jnd",
  "stage": "tdd-green",
  "updated": "2026-05-03T06:30:00Z"
}
```

- **`activity`** = the kind of work (`bug` / `feature` / `refactor` /
  `research` / `cleanup` / `docs` / `task` / `epic` / `idle`). Hooks
  set it from the bd type at claim; v2 activity-shaped recipes will
  refine it.
- **`stage`** = position in the recipe ladder (`idle` / `claim` /
  `research` / `tdd-red` / `tdd-green` / `verify` / `review` /
  `commit` / `wrap-up` / `close`). Hooks reliably write `claim` and
  `close`; skills instruct the agent to update intermediate stages
  best-effort.
- **`updated`** = ISO-8601 UTC timestamp; the status line surfaces age
  so staleness is visible.

The Claude Code status line (configured in `~/.claude/settings.json`
`statusLine`) reads both files and prints:

```
WORKFLOW: full | feature:tdd-green | bead:jnd | 14m
```

Or `WORKFLOW: full | idle | <age>` between beads. Empty string outside
beads workspaces or when mode is `off`.

The state file is per-session ephemera: add
`.claude/workflow-state.json` to your project's `.gitignore`. The
config file `workflow.json` IS committed (it's a per-project policy).

---

## 2. What's installed and where

### Plugins enabled (in `~/.claude/settings.json`)

```
superpowers@superpowers-marketplace      # the original 14-skill set
superpowers@claude-plugins-official      # newer 5.x; both versions coexist
beads@beads-marketplace                  # the bd CLI + 19 skill wrappers
beadpowers@beadpowers-dev                # 3 skills (brainstorming, create-beads, using-beadpowers)
mempalace@mempalace                      # 29-tool MCP server + skills + hooks
context7-plugin@context7-marketplace     # docs lookup for libraries
```

### Files Frank owns (in `~/.claude/`)

```
~/.claude/
├── settings.json                 # permissions, plugins, hooks, statusLine
├── lib/                          # NEW (v1.5)
│   ├── workflow-mode.sh          # mode resolver (sourceable lib)
│   └── workflow-state.sh         # state-file r/w (sourceable lib)
├── scripts/                      # NEW (v1.5)
│   ├── workflow-state            # CLI wrapper for skills/agents
│   └── statusline.sh             # Claude Code statusLine target
├── skills/
│   ├── session-startup/SKILL.md  # cold-start ritual (extended)
│   └── working-a-bead/SKILL.md   # 14-step recipe
├── agents/
│   ├── bug-family-researcher.md
│   ├── drawer-author.md
│   └── kg-relationship-extractor.md
├── commands/
│   ├── working-a-bead.md         # /working-a-bead [bead-id]
│   ├── lineage.md                # /lineage <topic>
│   └── wrap-up.md                # /wrap-up
└── hooks/
    ├── bd-claim-research.sh      # advisory; mode-gated (full only)
    ├── bd-close-capture.sh       # blocking in full; never blocks in light/off
    ├── git-push-bd-sync.sh       # advisory; silent in off
    └── workflow-mode-onboarding.sh  # NEW (v1.5) — SessionStart hook
```

### Per-project files (in any project that uses this workflow)

```
<project>/
├── CLAUDE.md                     # always-loaded conventions
├── .claude/
│   ├── workflow.json             # NEW (v1.5) — committed; {"v":1, "mode":"full|light|off"}
│   ├── workflow-state.json       # NEW (v1.5) — gitignored; per-session state
│   └── rules/                    # path-scoped guidance, auto-loads
│       ├── tests.md              # paths: tests/**/*.py
│       ├── engine.md             # paths: engine/**/*.py
│       └── prompts.md            # paths: prompts/**/*.md
└── .beads/                       # bd state (committed to git)
    ├── issues.jsonl
    └── interactions.jsonl
```

Add `.claude/workflow-state.json` to your project's `.gitignore`. The
state file is updated continuously by hooks and skills — it's
per-session ephemera, not project state.

The `.claude/rules/` set above is HAW-specific. For other projects,
write equivalent path-scoped rules covering the load-bearing
conventions of THAT project's directories.

### MemPalace location

- Palace per project lives at `~/.mempalace/<project-name>/`.
- HAW palace: `~/.mempalace/dreamer-engine/` (note the historical name).
- Chroma DB + KG SQLite + diary all under that root.

---

## 3. Daily session lifecycle

### When you `/clear` or open a new session

Hooks fire automatically:

1. **`bd prime`** — beads injects context: ready queue, in-progress
   beads, recent activity, persistent memories. Auto-fires.
2. **`mempal-stop-hook`** — runs at previous session's end (saved
   diary + drawer state).
3. **superpowers + beadpowers session-start.sh** — load `using-superpowers`
   and `using-beadpowers` meta-skills.

Then trigger `/session-startup` manually (or paste "let's pick up where
we left off"). The skill walks 9 steps:

1. `bd prime` + `bd stats` + `bd ready -n 10`
2. `bd list --status=in_progress` (zombies before queue)
3. `mempalace_status` + `kg_stats`
4. `mempalace_search` for session-close drawers + `mempalace_diary_read("claude-opus", 3)` + read latest decision drawers
4a. `bd stale --status in_progress --days 7` + `bd memories <project-keyword>`
5. Reconcile bead queue vs MemPalace recommendations
6. Pick a bead
7. Surface the right process skill for the bead shape
8. Confirm intent with you before claiming
9. Hand off to `working-a-bead` skill

### When you start work on a bead

Run `/working-a-bead <bead-id>` (or invoke the skill manually if the
slash command hasn't reloaded). The skill walks the 14 steps in
section 4.

The `bd update --claim` PreToolUse hook fires automatically and
reminds you to dispatch the `bug-family-researcher` subagent.

### When you finish a bead

Run `/wrap-up`. It runs:

1. `bd preflight` (lint + stale + orphans checks)
2. Full test suite with exact pass/skip/fail counts
3. `git status` confirms working tree clean
4. Dispatches `drawer-author` + `kg-relationship-extractor` subagents
   in parallel
5. You review their output
6. `mempalace_check_duplicate` then `mempalace_add_drawer`
7. `mempalace_kg_add` for each approved triple
8. `mempalace_diary_write` (AAAK summary)
9. `bd close <id>` (the close-capture hook lets it through because
   capture is done)
10. `bd dolt push`
11. `git push`
12. Suggest follow-up beads (don't auto-file)

### When you stop a session

The `mempal-stop-hook` fires automatically at conversation end.
You'll see the AUTO-SAVE checkpoint message — that's the trigger
to write a diary entry + decision drawer + KG triples for whatever
you accomplished that wasn't captured during a `/wrap-up`.

---

## 4. The 14-step bead recipe

> Source: `~/.claude/skills/working-a-bead/SKILL.md`
>
> Trigger: `/working-a-bead <bead-id>`

1. **Search MemPalace for the bug family** (`mempalace_search` +
   `mempalace_kg_query` + `bd memories <keyword>`). Restate the
   design in terms of any sibling lineage found.
2. **Claim and isolate**: `bd update <id> --claim` + create worktree
   `.worktrees/<bead>` on branch `frank/<bead>`.
3. **Phase 1 root cause** (`superpowers:systematic-debugging`):
   read actual code paths the bead names; verify the bead's
   hypothesis.
4. **TDD RED first** (`superpowers:test-driven-development`): write
   failing test (verbatim symptom from transcript where possible),
   watch it fail, paste the failure to user output.
5. **GREEN minimal fix**: smallest change to make the test pass.
6. **Bug-class coverage**: second test exercising the bug class
   (parameterized over the affected set, or unit test on the
   contract). Frank's deploy-day rule: "test for the bug AND for
   the bug class."
7. **Full pytest sweep**: failures here are usually tests that
   enshrined the buggy contract; update them, don't work around
   them. (0qw surfaced 14 such tests.)
8. **(Multi-task)** `superpowers:subagent-driven-development`:
   fresh subagent per task, automatic two-stage review.
9. **(Per task)** `superpowers:requesting-code-review`: catch
   issues task-by-task before they compound.
10. **Verification** (`superpowers:verification-before-completion`):
    re-run from clean shell, confirm exact counts, check
    `git diff --stat` matches intended scope.
11. **Commit** on branch with subject + body naming symptom, root
    cause, fix, test counts, bug-family lineage if applicable.
12. **Finish branch** (`superpowers:finishing-a-development-branch`):
    four-option choice (merge / push & PR / keep / discard).
13. **Preflight + close + push**: `bd preflight` →
    `bd close --reason="..."` → `bd dolt push` → `git push` →
    confirm "up to date with origin."
14. **Capture decision in MemPalace**: drawer + KG triples + diary.
    `bd remember "<one-liner>"` for tribal facts (boundary:
    `bd remember` for one-liners, drawers for multi-paragraph
    decisions).

### Skip when

- Trivial fix (≤ 1 line, well-understood). Skip steps 2 + 12; the
  rest scale down.
- Pure spike. Use `superpowers:brainstorming` until a concrete bead
  emerges.
- Mid-task interruption. Recipe is for new bead starts.

---

## 5. Reference: skills

### `~/.claude/skills/working-a-bead/SKILL.md`

The 14-step recipe (above). Frontmatter has
`disable-model-invocation: true` so it only fires on explicit
invocation, not auto-firing in normal conversation.

### `~/.claude/skills/session-startup/SKILL.md`

Cold-start ritual. 9 steps (extended this session to include
`mempalace_diary_read` + `bd stale` + `bd memories` + handoff to
`working-a-bead`).

### `~/.claude/skills/audit-project/SKILL.md` (NEW v1.5, added 2026-05-03)

Manual-only project onboarding + health check. Walks a 9-item
checklist (git/branch hygiene, `.beads/`, bd hooks, `workflow.json`,
MemPalace wing, CLAUDE.md ≤200 lines, `.claude/rules/` for detected
directories, optional `.claude/agents/`+`commands/`, `bd memories`)
and offers template-generated fixes per gap. Frontmatter has
`disable-model-invocation: true`; never auto-suggested by
session-startup, working-a-bead, or any hook. Triggered exclusively
by `/audit-project`. The skill dispatches the `project-onboarder`
subagent for read-only scanning, then drives interactive fix
application from the main conversation.

### Bundled skills you should know about

- `superpowers:brainstorming` / `beadpowers:brainstorming` — design
  refinement before creative work. Boundary: beadpowers when output
  is beads; superpowers when output is `docs/`.
- `superpowers:systematic-debugging` — 4-phase process. Phase 1 (root
  cause) is non-negotiable before any fix.
- `superpowers:test-driven-development` — RED first, watched fail,
  GREEN, refactor.
- `superpowers:using-git-worktrees` — `.worktrees/<bead>` per bead.
- `superpowers:verification-before-completion` — evidence before
  claiming done.
- `superpowers:finishing-a-development-branch` — four-option
  merge/PR/keep/discard.
- `superpowers:requesting-code-review` / `receiving-code-review` —
  per-task code review (dormant; activate via `/wrap-up` or
  multi-task plans).
- `superpowers:subagent-driven-development` — fresh subagent per
  task in same session.
- `superpowers:dispatching-parallel-agents` — for 2+ independent
  bug domains. Trigger: `bd ready` shows multiple unblocked bugs
  on disjoint files.
- `superpowers:writing-plans` — bite-sized plans before multi-task
  work.

---

## 6. Reference: slash commands

All three have `disable-model-invocation: true` — only Frank
explicitly triggers them.

### `/working-a-bead [bead-id]`

Source: `~/.claude/commands/working-a-bead.md`

Loads the `working-a-bead` skill and runs the 14-step recipe
on the named bead. If no bead-id given, runs `bd ready` and
confirms with you which bead to work first.

### `/lineage <topic>`

Source: `~/.claude/commands/lineage.md`

Ad-hoc prior-art lookup. Dispatches the `bug-family-researcher`
subagent with the topic as input. Returns a structured
prior-art report. Use when you suspect a bug or design
question has prior art but don't know where it lives.

### `/wrap-up`

Source: `~/.claude/commands/wrap-up.md`

Close-time ritual. Runs preflight + drafts drawer/KG via
subagents + closes bead + pushes. The session-end superpower.

### `/audit-project` (NEW v1.5, added 2026-05-03)

Source: `~/.claude/commands/audit-project.md`

Project onboarding + health check. Dispatches the
`project-onboarder` subagent to scan workflow infrastructure
(git, beads, hooks, workflow.json, MemPalace wing, CLAUDE.md,
rules, optional agents/commands, memories) and walks each gap
with you, applying template-based fixes only after explicit
per-item approval. Strictly manual — must be typed; never auto-
suggested. Re-run after material project changes (e.g., a new
`tests/` dir warrants `tests.md`).

---

## 7. Reference: subagents

All three live in `~/.claude/agents/`. Model: inherit. None of them
write to MemPalace or beads themselves — they return reviewable
artifacts the main agent files after sign-off.

### `bug-family-researcher`

**Inputs**: bead title + symptom description (+ optional bead-id,
suspected code paths, key entities).

**Recipe**:
1. `mempalace_search` (semantic, top 3-5 results)
2. `mempalace_kg_query` for each named entity (S→P→O facts)
3. `mempalace_diary_read` (last 5 entries; AAAK-compressed)
4. `bd memories <keyword>` (tribal facts)
5. `bd search <keyword>` (related closed beads)

**Output**: ≤400-word structured prior-art markdown report:
family lineage, relevant decision drawers, KG facts, bd memories,
recommended approach, prior fixes that pattern-match, open
questions.

**Latency**: 5-15s per claim. Acceptable per locked decision.

### `drawer-author`

**Inputs**: bead-id + commit SHAs (+ optional context note).

**Recipe**:
1. `bd show <bead-id>`
2. `git show <sha> --stat` for each commit
3. Commit message bodies for rationale
4. `mempalace_search` for related drawers (lineage references)
5. `mempalace_kg_query` for relevant prior triples

**Output**: 300-600 word decision drawer body in HAW house style:
DECISION → ROOT CAUSE → PRIOR ART → WHY NOT THE OTHER OPTIONS →
WHAT SHIPPED → BUG-CLASS COVERAGE → BEHAVIORAL TRADE-OFF →
VERIFICATION → CALLER IMPACT → OPEN.

### `kg-relationship-extractor`

**Inputs**: bead-id + commit SHAs (+ optional drawer body if
drawer-author ran first).

**Patterns to look for**: sibling-of, family membership, closed-at,
caused-by, canonical-fix-pattern, superseded-by.

**Output**: ≤5 KG triples (subject → predicate → object +
valid_from + optional source_closet) with one-sentence "why" each.
Plus invalidations to consider.

### `project-onboarder` (NEW v1.5, added 2026-05-03)

**Inputs**: absolute path to project root + (optional) project
short name.

**Recipe** (read-only scan):
1. Git repo + branch + clean-tree check.
2. `.beads/` presence + DB.
3. bd hooks installed (pre-commit references bd).
4. `<root>/.claude/workflow.json` present + valid + mode set.
5. MemPalace wing matching project short name (via
   `mempalace_list_wings`).
6. CLAUDE.md present + line count ≤200.
7. `.claude/rules/` scaffolded for detected directories
   (`tests/` → `tests.md`, `engine/`/`src/` → `engine.md`,
   `prompts/` → `prompts.md`).
8. `.claude/agents/` + `.claude/commands/` present (informational).
9. `bd memories <project-keyword>` returns ≥1.

**Output**: ≤250-line structured checklist. Each item is
PASS/WARN/MISS with a one-sentence rationale and a suggested
fix line. Closes with PASS/WARN/MISS counts and the top-3 gaps
to fix first.

**Boundary**: read-only. Never runs `bd init`/`bd hooks install`/
file writes/MemPalace writes. The audit-project SKILL drives
interactive fixes from the main conversation; this subagent only
scans.

---

## 8. Reference: hooks

Three PreToolUse hooks (Bash matcher) and one SessionStart hook,
registered in `~/.claude/settings.json`. PreToolUse hooks fire in
registered order; any returning exit 2 blocks the tool call.

All hooks are mode-aware (v1.5). See section 1's "Workflow modes"
for the resolution rules.

### `bd-claim-research.sh`

**Trigger**: Bash command matching `bd update.*--claim`.

**Mode behavior**:
- `full`  — fires reminder + writes `bead`/`activity`/`stage=claim` to state file.
- `light` — silent (no reminder, no state write).
- `off`   — silent.

**Output**: `additionalContext` JSON reminding the agent to dispatch
`bug-family-researcher`. Activity inferred from `bd show <id>` Type:
line (`bug` / `feature` / `task` / `epic`).

### `bd-close-capture.sh`

**Trigger**: Bash command matching `bd close`.

**Mode behavior**:
- `full`  — blocks (exit 2) unless bypass; on bypass writes `stage=close`,
            `activity=idle`, `bead=null`.
- `light` — never blocks; writes `stage=close` to state.
- `off`   — never blocks; writes `stage=close` to state.

**Bypasses (full mode only)**:
- `--force` flag on the bd close command, OR
- `BD_CLOSE_FORCE=1` env var.

Reasoning: the most-skipped step is the decision drawer at close.
Blocking forces capture; bypass exists for trivial fixes / chore
closes / batch closes for already-captured work. Light/off modes
turn off the block entirely.

### `git-push-bd-sync.sh`

**Trigger**: Bash command matching `git push` (excludes `--dry-run`).

**Mode behavior**:
- `full`  — warns if `.beads/` has uncommitted modifications.
- `light` — warns (same as full; informational only).
- `off`   — silent.

### `workflow-mode-onboarding.sh` (NEW v1.5)

**Trigger**: SessionStart event in any beads workspace.

**Behavior**: non-blocking (exit 0).
1. Initializes `<project>/.claude/workflow-state.json` to idle if absent.
2. If `<project>/.claude/workflow.json` is missing, injects an
   `additionalContext` block instructing the agent to ask the user to
   pick a mode (full/light/off) and write the answer to `workflow.json`.

After the answer is written, future sessions skip the prompt
(ask-once-and-remember).

### Hot-reload caveat

It's unclear whether Claude Code reloads `settings.json` mid-session.
Hooks may not fire until the next `/clear` cycle. Test by
attempting `bd close <id>` without `--force` — if the hook fires,
hot-reload works; if not, restart the session.

---

## 9. Reference: path-scoped rules

Source: `<project>/.claude/rules/*.md` with YAML `paths` frontmatter.

Auto-loads when Claude works with files matching the path globs.
Saves context vs CLAUDE.md (which loads every session regardless).

### Existing rules in HAW

| File | Paths | Captures |
|---|---|---|
| `tests.md` | `tests/**/*.py` | TDD non-negotiable + bug-class coverage rule + enshrined-test rule + lineage citation + no DB mocking |
| `engine.md` | `engine/**/*.py` | async/sync split + LLM via NarrativeBackend only + 13p.3.11 inter-bot credential rules + Postgres pool/timeout bounds + no recovery.py |
| `prompts.md` | `prompts/**/*.md` | JSON-Null Discipline (huu.15.2/0qw lineage) + bold reservation + self-check envelope + Milne voice register + gate-test round-trip |

For other projects: identify the load-bearing conventions of each
directory and write equivalent rules. Keep each ≤30 lines.

---

## 10. Reference: bd CLI

### Daily commands

```bash
bd ready                    # unblocked work, ranked
bd ready -n 20              # show more
bd show <id>                # full issue details + dependencies
bd update <id> --claim      # take ownership (fires bd-claim-research hook)
bd close <id> --reason="x"  # close (BLOCKED by bd-close-capture hook by default)
bd close <id1> <id2> ...    # batch close
bd dolt push                # push beads state to Dolt remote
bd dolt pull                # pull beads state from Dolt remote
```

### Bypass + escape hatches

```bash
bd close <id> --force                  # bypass close-capture hook
BD_CLOSE_FORCE=1 bd close <id>         # also bypasses
bd defer <id> --until=2026-07-01       # postpone without blocking
bd defer <id> --until=tomorrow         # accepts: +1h, tomorrow, next monday, ISO date
bd supersede <id> --with=<new-id>      # mark replaced by newer
```

### Memory + lineage

```bash
bd remember "one-line tribal fact"     # auto-injects at next bd prime
bd memories <keyword>                  # search tribal facts
bd memories                            # list all
```

Boundary: `bd remember` for one-line project tribal facts that
should auto-inject; MemPalace drawer for multi-paragraph decisions
with options-considered context.

### Lifecycle hygiene

```bash
bd stale --status in_progress --days 7  # zombie tasks
bd orphans --details                    # commits referencing open issues
bd orphans --fix                        # batch close shipped work
bd preflight                            # PR-readiness checks
bd lint                                 # ensure beads have required sections
bd compact --days 30                    # squash old Dolt commits
```

### Dependencies + structure

```bash
bd dep add <issue> <depends-on>            # generic dep
bd dep add <issue> <parent> --type=parent-child
bd dep add <issue> <blocker> --type=blocks
bd blocked                                  # all blocked issues
bd graph                                    # visualise DAG (if installed)
```

### Workflows (advanced; not currently used in HAW)

```bash
bd formula list                       # available templates
bd mol pour <name>                    # spawn persistent molecule from formula
bd mol spawn <name> --wisp            # ephemeral instance
bd mol distill <epic> --as "Name"     # extract reusable proto from ad-hoc epic
```

### Hooks (one-time install)

```bash
bd hooks install        # pre-commit, post-merge, pre-push, post-checkout, prepare-commit-msg
bd hooks list           # verify
bd hooks uninstall      # remove
```

---

## 11. Reference: MemPalace MCP tools

29 MCP tools total. Categorized by usage frequency.

### High-frequency (use these regularly)

```
mempalace_status                     # palace overview at session start
mempalace_kg_stats                   # KG entity/triple counts
mempalace_search                     # semantic similarity over drawers
mempalace_kg_query                   # structured S→P→O lookup
mempalace_kg_add                     # add new fact
mempalace_add_drawer                 # file decision drawer
mempalace_diary_write                # AAAK session summary
mempalace_diary_read                 # recover own continuity
```

### Mid-frequency

```
mempalace_check_duplicate            # before add_drawer (prevents fragmentation)
mempalace_kg_timeline                # chronological story for entity
mempalace_kg_invalidate              # mark fact as no-longer-true
mempalace_get_drawer                 # fetch single drawer by ID
mempalace_list_drawers               # paginated, optional wing/room filter
mempalace_update_drawer              # modify content or relocate
```

### Low-frequency / advanced

```
mempalace_traverse                   # BFS walk from room, auto-detects tunnels
mempalace_list_wings / list_rooms    # palace structure inspection
mempalace_get_taxonomy               # full hierarchy
mempalace_create_tunnel              # explicit cross-wing link
mempalace_follow_tunnels             # navigate explicit tunnels
mempalace_find_tunnels               # discover bridging rooms
mempalace_list_tunnels               # all explicit tunnels
mempalace_graph_stats                # graph connectivity metrics
mempalace_memories_filed_away        # acknowledge silent checkpoint
mempalace_get_aaak_spec              # AAAK dialect reference
mempalace_hook_settings              # silent_save / desktop_toast flags
mempalace_reconnect                  # force HNSW index resync
mempalace_delete_drawer              # irreversible
mempalace_delete_tunnel              # remove explicit tunnel
```

### Architecture (1-paragraph reference)

- **Wing** = project (e.g., `hundred_acre_woods`, `dreamer-engine`,
  `wing_claude-opus`).
- **Room** = topic/aspect (e.g., `decisions`, `diary`, `architecture`,
  `experta`, `bdi`, `htn`).
- **Drawer** = unit of verbatim content (markdown body, source-file
  metadata, added_by metadata).
- **Closet** = secondary index (topic|entities|→drawer_ids); not
  directly exposed but referenced by `kg_add(source_closet=...)`.
- **Tunnel** = explicit cross-wing link, manually created
  (`create_tunnel` / `follow_tunnels`).
- **KG** = SQLite `knowledge_graph.sqlite3` with S→P→O triples
  (valid_from, ended, source_closet).
- **Diary** = per-agent personal wing (`wing_<agent_name>`,
  room=`diary`); AAAK-compressed entries.

---

## 12. Decision tables

### `bd remember` vs MemPalace drawer

| Need to capture | Use |
|---|---|
| One-line tribal fact ("Haiku rejects access_key=, use api_key=") | `bd remember` (auto-injects at next `bd prime`) |
| Multi-paragraph decision with options + reasoning | MemPalace drawer (`mempalace_add_drawer`) |
| Per-agent introspective note ("today I learned...") | MemPalace diary (`mempalace_diary_write`) |
| Structured S→P→O relationship (sibling-of, superseded-by) | MemPalace KG (`mempalace_kg_add`) |

### Brainstorming variant

| Output destination | Use |
|---|---|
| Beads (epics + tasks) | `beadpowers:brainstorming` (refuses to write `docs/plans/`) |
| Spec or plan in `docs/` | `superpowers:brainstorming` |

### Subagent vs main-context inline

| Work shape | Use |
|---|---|
| Read many files, return summary | Subagent (keeps main context clean) |
| Quick lookup with feedback loop | Main context (no subagent latency) |
| Same-session multi-task plan execution | `superpowers:subagent-driven-development` |
| Async session with checkpoints | `superpowers:executing-plans` |

### Parallel vs sequential beads

| Situation | Use |
|---|---|
| 2+ unblocked beads on disjoint files | `superpowers:dispatching-parallel-agents` |
| Beads share files or have logical dependency | Sequential (use the recipe per bead) |
| 43-bead epic across 3 architectural layers | Agent teams (experimental; deferred until Phase 4) |

### Skill vs hook

| Need | Use |
|---|---|
| Reasoning, multi-step workflow | Skill (model interprets) |
| Always-on guardrail (block X every time) | Hook (deterministic enforcement) |
| Reference material loaded on demand | Skill |
| Side effect on lifecycle event | Hook |

---

## 13. Bypass mechanisms + known limitations

### Bypass `bd close` blocking hook

Per-call bypass (full mode):

```bash
bd close <id> --force
# OR
BD_CLOSE_FORCE=1 bd close <id>
```

Either works. The `--force` flag is more discoverable; the env var
is faster for batch operations.

Project-wide bypass (v1.5):

```bash
# Disable workflow ceremony for this project entirely:
echo '{"v":1, "mode":"off"}' > .claude/workflow.json

# OR informational-only mode (recipe runs, hooks don't block):
echo '{"v":1, "mode":"light"}' > .claude/workflow.json

# OR session-scoped escape hatch:
CLAUDE_WORKFLOW_OFF=1 claude
```

### Skip the recipe entirely

For a ≤1-line trivial fix that's well understood:
- Skip step 2 (worktree).
- Skip step 12 (finishing-a-development-branch — fix on main directly).
- TDD discipline (steps 4-6) STILL applies. Trivial fixes still get
  tests.

For pure exploratory spikes:
- Use `superpowers:brainstorming` (or beadpowers variant).
- Don't engage the recipe until the spike yields a concrete bead.

### Settings.json hot-reload

Unverified whether Claude Code reloads settings.json mid-session.
Hooks may not fire until the next `/clear`. Test by attempting
`bd close <id>` without `--force` — if blocked, hot-reload works;
if not, restart the session.

### `bd doctor` not in embedded mode

Frank's beads setup is embedded (not server). `bd doctor` returns a
note rather than running checks. Health checks done manually:
- `ls -la .beads/embeddeddolt/` to confirm DB exists
- `bd version` to check version
- `bd init --force` if reinitialization needed

### Subagent latency

5-15s per dispatch (per locked decision 3, this is acceptable cost
for clean main context). If you need a faster lookup, run the
queries inline in main context instead.

### MemPalace search context cost

`mempalace_search` returns top results with full drawer content.
Large drawers can blow context. Use `mempalace_list_drawers` first
to inventory before searching, or use the subagent to keep the
expensive search in isolated context.

### Diary doesn't auto-surface

`mempalace_diary_write` accumulates per agent but is invisible
unless explicitly read via `mempalace_diary_read`. The session-startup
skill step 4 is the only ritual that reads it. If you skip
session-startup, your diary is dead weight.

### KG drift

KG triples don't auto-invalidate when code changes. If a bead is
superseded or a fact stops being true, manually call
`mempalace_kg_invalidate`. Drift accumulates if you don't.

---

## 14. Common scenarios cookbook

### "I just got assigned a new bug"

1. `/session-startup` if you haven't already.
2. `bd show <bead-id>` to read the symptom + hypothesis.
3. `/working-a-bead <bead-id>` to start the recipe. The
   bug-family-researcher subagent fires automatically (via
   the hook) at the claim step.
4. Follow the recipe. Most bugs go from claim to merged in 1-3
   hours; some take a multi-session arc.

### "I have 3 unrelated bugs to fix"

1. `bd ready` to confirm they're all unblocked.
2. Verify they touch disjoint files (`bd show <id>` × 3).
3. If yes: invoke `superpowers:dispatching-parallel-agents` to
   spawn one agent per bug. Each runs the recipe in its own
   worktree.
4. After all complete: batch merge in dependency order, run full
   suite once across the merged state, fix any cross-branch
   collateral in a single follow-up commit.
5. `/wrap-up` once for the batch (drawer-author handles each bead
   separately).

### "I want to do exploratory work — what fires?"

The recipe doesn't apply. Steps:
1. `superpowers:brainstorming` (or `beadpowers:brainstorming` if
   the output will be beads).
2. Iterate on the design through dialogue.
3. When a concrete bead emerges: `beadpowers:create-beads` to file,
   then `/working-a-bead <new-id>` to engage the recipe.

### "I think I've seen this bug before — where?"

`/lineage <topic>` (uses bug-family-researcher subagent for full
search). Or directly:
- `mempalace_search "symptom keywords"`
- `mempalace_kg_query "<entity-name>"` for any function/error/file
  named in the bug
- `mempalace_diary_read("claude-opus", 10)` if the prior context
  was an introspective note
- `bd search "keyword"` for related closed beads

### "Something about the workflow feels broken"

1. Check: did `settings.json` hot-reload? Try `/clear` and re-test.
2. Check hook smoke: `echo '{"tool_name":"Bash","tool_input":{"command":"bd close foo"}}' | bash ~/.claude/hooks/bd-close-capture.sh; echo $?`
3. Check the master plan drawer for known limitations:
   `mempalace_search "WORKFLOW INFRASTRUCTURE PLAN"`.
4. If you find a real gap: file a bead under epic
   `hundred-acre-woods-2st` (or successor). Update the plan
   drawer's status table.

### "I need to tweak a hook"

Sources:
- Hook scripts: `~/.claude/hooks/*.sh`
- Hook registration: `~/.claude/settings.json` →
  `hooks.PreToolUse[matcher=Bash]`
- Smoke-test pattern in section 13.

After tweaking, smoke-test before relying on it.

### "I want to add a new path-scoped rule for this project"

```bash
mkdir -p <project>/.claude/rules/
cat > <project>/.claude/rules/<area>.md <<'EOF'
---
paths:
  - <area>/**/*.py
description: <one-line description>
---

# <Area> discipline

(rules)
EOF
```

Keep each rule file ≤30 lines. Cite source lineage when applicable
(e.g., "huu.15.2 / 0qw lineage").

### "I'm at session end, what should fire?"

- `/wrap-up` for any beads that are about to close.
- The `mempal-stop-hook` fires automatically — when you see the
  AUTO-SAVE message, write a diary entry + decision drawer + KG
  triples for anything not captured by `/wrap-up`.
- `bd dolt push` + `git push` if not already done.
- Verify `git status` shows "up to date with origin."

---

## 15. Glossary

- **AAAK** — compressed memory dialect MemPalace uses for diary
  entries (~30× compression). Format: `KEY:value|KEY:value|⭐⭐⭐`.
  Entity codes (3-letter caps) + emotion markers (\*action\*) +
  pipe-separated fields. Read naturally; expand entity codes mentally.
- **Bead** — a beads issue (`bd` CLI tracker).
- **Closet** — MemPalace secondary index (topic|entities|→drawer_ids).
  Greedily packed ~1500 chars. Not directly exposed; referenced by
  `kg_add(source_closet=...)`.
- **Drawer** — unit of MemPalace content. Has wing/room/source_file
  metadata.
- **Family** — a class of related bugs sharing a fix pattern (e.g.,
  classifier-validator-demotion: huu.7.1, huu.15.2, huu.19.3, 0qw).
- **HAW** — Hundred Acre Woods (Frank's primary project).
- **KG** — MemPalace knowledge graph. SQLite-backed S→P→O triples
  with valid_from/ended timestamps.
- **MCP** — Model Context Protocol. MemPalace exposes 29 MCP tools.
- **Recipe** — the 14-step working-a-bead workflow.
- **Room** — topic/aspect within a wing (e.g., `decisions`, `diary`).
- **Subagent** — isolated worker with own context, returns summary.
- **Tunnel** — explicit cross-wing link in MemPalace.
- **Wing** — project namespace in MemPalace.
- **Wisp** — ephemeral beads molecule (no audit trail, deleted after work).

---

## 16. Where to update what

| You want to update | Edit this |
|---|---|
| The 14-step recipe | `~/.claude/skills/working-a-bead/SKILL.md` |
| Cold-start ritual | `~/.claude/skills/session-startup/SKILL.md` |
| Slash command behavior | `~/.claude/commands/<name>.md` |
| Subagent prompt | `~/.claude/agents/<name>.md` |
| Hook behavior | `~/.claude/hooks/<name>.sh` (shell) + `~/.claude/settings.json` (registration) |
| Mode resolution / state-file lib | `~/.claude/lib/workflow-mode.sh` and `~/.claude/lib/workflow-state.sh` |
| Status line script | `~/.claude/scripts/statusline.sh` |
| State-file CLI | `~/.claude/scripts/workflow-state` |
| Permission allowlist | `~/.claude/settings.json` `permissions.allow` |
| Project workflow mode (v1.5) | `<project>/.claude/workflow.json` `.mode` |
| Project conventions (always-on) | `<project>/CLAUDE.md` |
| Path-scoped conventions | `<project>/.claude/rules/<area>.md` |
| Project tribal one-liners | `bd remember "<insight>"` |
| Multi-paragraph decision | `mempalace_add_drawer` |
| Entity relationship | `mempalace_kg_add` |
| Personal session note | `mempalace_diary_write` |
| Workflow design (the source of truth for THIS file) | MemPalace drawer "WORKFLOW INFRASTRUCTURE PLAN" (hundred_acre_woods/decisions). Append a status drawer when shipping a build. |
| This manual | `~/repos/claude-workflow-manual.md` |
| Companion walkthrough | `~/repos/claude-workflow-walkthrough.md` |

---

## Appendix: provenance

- Workflow infrastructure shipped 2026-05-02 in commit `c5fa8dc`
  (hundred-acre-woods).
- Epic `hundred-acre-woods-2st`: 8/9 children closed (88%);
  remaining is Build 8 (agent teams pilot for Phase 4, deferred
  to 2026-07-01).
- Locked design decisions captured in MemPalace drawer
  "WORKFLOW INFRASTRUCTURE PLAN" (master) + 2 status update
  drawers (Builds 1+2 + Builds 4-7, 9, 10) + the
  process-lesson drawer ("SEARCH MEMPALACE BEFORE DESIGNING,
  NOT JUST AT SESSION START AND CLOSE").
- This manual was written same-day for Frank's `~/repos/`
  directory as the user-facing reference. When the manual and
  the MemPalace drawer disagree, the drawer is design truth and
  this manual gets updated to match.
