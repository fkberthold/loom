# Decision tables

Tool-selection lookups. Each table maps a situation to the
loom-shipped surface that handles it.

## `bd remember` vs MemPalace drawer

| Need to capture | Use |
|---|---|
| One-line tribal fact ("Haiku rejects `access_key=`, use `api_key=`") | `bd remember` (auto-injects at next `bd prime`) |
| Multi-paragraph decision with options + reasoning | MemPalace drawer (`mempalace_add_drawer`) |
| Per-agent introspective note ("today I learned…") | MemPalace diary (`mempalace_diary_write`, param: `entry`) |
| Structured S→P→O relationship (sibling-of, superseded-by) | MemPalace KG (`mempalace_kg_add`) |

## Brainstorming variant

| Output destination | Use |
|---|---|
| Beads (epics + tasks) | `beadpowers:brainstorming` (refuses to write `docs/plans/`) |
| Spec or plan in `docs/` | `superpowers:brainstorming` |

## Subagent vs main-context inline

| Work shape | Use |
|---|---|
| Read many files, return summary | Subagent (keeps main context clean) |
| Quick lookup with feedback loop | Main context (no subagent latency) |
| Same-session multi-task plan execution | `superpowers:subagent-driven-development` |
| Async session with checkpoints | `superpowers:executing-plans` |

## Parallel vs sequential beads

Two ready beads are wave-compatible iff they have NO dependency edge
between them AND their declared `Files:` sets are DISJOINT.
`scripts/loom-fanout-detect` computes this from each bead's `Files:`
line (loom-asr) and surfaces a proposed wave at selection time; a
bead with no `Files:` line is treated as footprint-unknown and
excluded from any wave (degrades conservative).

| Situation | Use |
|---|---|
| 2+ unblocked beads, disjoint `Files:` sets, no dependency edge | `superpowers:dispatching-parallel-agents` (wave proposed by `scripts/loom-fanout-detect`) |
| Beads share files or have a dependency edge | Sequential (one recipe per bead) |
| A bead with no `Files:` line declared | Excluded from any proposed wave until the line is added |

## Within-bead dispatch posture

How to work a single bead's variable RED→GREEN middle. Worker
dispatch is the default; inline is the explicit, narrow exception.
Central records the call in the `workflow-state` `dispatch` field.

| Middle shape | Posture | `dispatch` field |
|---|---|---|
| Any RED→GREEN cycle (the default) | Dispatch a worker via `/dispatch-middle <bead>` | `dispatch=worker` |
| Change is ≤ ~15 lines AND single non-test file AND adds no new test | Inline (central edits directly) — waved through without justification | `dispatch=inline:<reason>` |
| Anything above the inline threshold | Dispatch (inline is not an option) | `dispatch=worker` |

## Design cycle vs activity recipe

Above-bead generative work vs a single contracted change.

| Work shape | Use |
|---|---|
| Open / advance generative design for a topic that will become beads | `/design-a-cycle <topic>` (above-bead orchestrator; emits an epic) |
| A single, already-contracted change to one bead | An `<activity>-a-bead` recipe (or `/working-a-bead <id>` to route) |
| A locked Tier-1 decision needs to become an implementation bead | `create-beads` handoff (carries the decision's `RED:` line) |

## Skill vs hook

| Need | Use |
|---|---|
| Reasoning, multi-step workflow | Skill (model interprets) |
| Always-on guardrail (block X every time) | Hook (deterministic enforcement) |
| Reference material loaded on demand | Skill |
| Side effect on lifecycle event | Hook |

## Recipe selection

| Bead shape / verb | Recipe |
|---|---|
| `bead.type=bug`, "X returns wrong value" | `bugfix-a-bead` |
| `bead.type=feature`, "build X" / "add Y" / "implement Z" | `feature-a-bead` |
| extract / rename / consolidate / restructure | `refactor-a-bead` |
| "research X" / "investigate Y" / "what do we know about Z" | `research-a-bead` |
| remove / delete / drop / rip out / retire / deprecate | `cleanup-a-bead` |
| document / docs / guide / README / walkthrough / manual | `docs-a-bead` |
| Ambiguous | `/working-a-bead <id>` (router); pass `--recipe=<name>` to override |
