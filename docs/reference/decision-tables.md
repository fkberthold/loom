# Decision tables

Tool-selection lookups. Each table maps a situation to the
loom-shipped surface that handles it.

## `bd remember` vs MemPalace drawer

| Need to capture | Use |
|---|---|
| One-line tribal fact ("Haiku rejects `access_key=`, use `api_key=`") | `bd remember` (auto-injects at next `bd prime`) |
| Multi-paragraph decision with options + reasoning | MemPalace drawer (`mempalace_add_drawer`) |
| Per-agent introspective note ("today I learned…") | MemPalace diary (`mempalace_diary_write`) |
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

| Situation | Use |
|---|---|
| 2+ unblocked beads on disjoint files | `superpowers:dispatching-parallel-agents` |
| Beads share files or have logical dependency | Sequential (one recipe per bead) |
| 43-bead epic across 3 architectural layers | Agent teams (experimental; Phase 4 deferred) |

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
