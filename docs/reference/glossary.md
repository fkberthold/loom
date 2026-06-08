# Glossary

## AAAK

Compressed memory dialect MemPalace uses for diary entries
(approximately 30× compression). Format:
`KEY:value|KEY:value|⭐⭐⭐`. Three-letter capitalised entity codes,
`*action*` emotion markers, pipe-separated fields. Read naturally;
expand entity codes mentally. Spec retrievable via
`mempalace_get_aaak_spec`.

## Above-bead orchestrator

A loom workflow that operates at a *campaign / arc* altitude above
any single bead — it iterates over a topic, spawns research and
emits an implementation epic, but is not itself a bead or epic. Its
state lives in the layered design substrate (L2 design-doc drawer
header + L1 KG), never in `bd`. `design-a-cycle` is the canonical
above-bead orchestrator (loom-tdua). Contrast with a *recipe*,
which works exactly one bead from claim to merge.

## Bead

A beads issue (`bd` CLI tracker).

## bd-state integrity

The property that `.beads/issues.jsonl` always matches the
authoritative dolt store, even across history-rewriting git
operations. Loom maintains it with a layered defense: the
`scripts/bd-merge-driver.sh` merge driver (`git merge`, loom-4um),
the `post-rewrite.sh` git hook (rebase / amend, loom-yjo), and the
`bd-worktree-preseed.sh` PreToolUse hook (fresh-worktree first
write, loom-x4m). Dolt is the source of truth across all three.

## Closet

MemPalace secondary index (`topic|entities|→drawer_ids`). Greedily
packed to approximately 1500 characters. Not directly exposed;
referenced by `kg_add(source_closet=…)`.

## Drawer

Unit of MemPalace content. Carries `wing` / `room` / `source_file`
metadata.

## design-a-cycle

The above-bead orchestrator skill / `/design-a-cycle <topic>`
command that drives a design cycle's Plan → Research → Architect
cadence over the layered design substrate, gates on two-tier
soundness, then hands off to `create-beads` to spawn the
implementation epic. NOT an activity recipe — it is stateless beyond
the substrate it maintains (loom-tdua).

## Design-predicate set

The SOFT-recommended (not enforced) KG predicate vocabulary a design
cycle uses on its L1 spine to record locked structure + invariants:
`supersedes_design_of`, `grounded_in`, `emits_bead`,
`soundness_tier`, and `depends_on_invariant`. The set exists so
independent cycles converge on a shared vocabulary by default; the
KG is open, so a cycle that needs a different shape is free to
deviate (loom-tdua).

## dispatch-middle

The skill / `/dispatch-middle <bead>` command that orchestrates a
bead's variable RED→GREEN middle as a pipeline of INDEPENDENT
subagents — test-author → implementer (→ optional verify) — sharing
one worktree. Central invokes once and writes nothing, then
integrates (verify + merge + close + capture). It is the
friction-inversion lever: it makes dispatch cheaper than inline
(loom-5m94).

## Family

A class of related bugs sharing a fix pattern (e.g.,
classifier-validator-demotion: `huu.7.1`, `huu.15.2`, `huu.19.3`,
`0qw`).

## Friction-inversion

The design lever behind `dispatch-middle`: rather than exhort the
central agent to dispatch a worker (which loses to the lower
friction of just editing inline), make the dispatched path the
*cheaper* one — a single `/dispatch-middle <bead>` invocation runs
the whole test-author → implementer pipeline, so the discipline wins
on convenience instead of willpower (loom-5m94).

## HAW

Hundred Acre Woods. Frank's primary project; historical source of
the workflow-infrastructure design captured in MemPalace drawer
"WORKFLOW INFRASTRUCTURE PLAN".

## KG

MemPalace knowledge graph. SQLite-backed S→P→O triples with
`valid_from` / `ended` timestamps.

## Layered design substrate

The three-layer home for a design cycle's state, where `design-a-cycle`
precipitates in-flight prose reasoning into structure (loom-tdua):

- **L1 — KG spine.** The queryable knowledge-graph layer holding the
  cycle's locked structure + invariants as S→P→O triples (see
  design-predicate set). Update-in-place.
- **L2 — design-doc drawer.** The MemPalace drawer (scaffolded from
  `templates/design-doc/`) whose header carries status + in-flight
  reasoning + locked-decision sections.
- **L3 — executable specs.** OPTIONAL — the `RED:` lines / test
  scenarios a Tier-1 decision emits onto its handoff bead.

The human Diataxis docs are a downstream projection rendered from
the substrate, never the substrate itself (precedence
system/beads/MemPalace > docs, per loom-9z1.10).

## Loom

This repository. Workflow-infrastructure package: skills, slash
commands, subagents, hooks, helpers, and settings snippets installed
into `~/.claude/`.

## MCP

Model Context Protocol. MemPalace exposes 29 MCP tools.

## Recipe

An activity-shaped workflow (`bugfix-a-bead`, `feature-a-bead`,
`refactor-a-bead`, `research-a-bead`, `cleanup-a-bead`,
`docs-a-bead`, `upstream-a-bead`) that supplies its own variable
middle and defers to `bead-lifecycle-shell` for the surrounding
phases. A recipe works exactly one bead from claim to merge;
contrast with an *above-bead orchestrator*.

## RED: line

A single structured line in a bead's description
(`RED: <spec>`) carrying the executable spec a Tier-1 design
decision emitted — a behavioral Given-When-Then scenario or a
structural `INVARIANT: …`. The implementation bead inherits its RED
test from this line: the recipe's RED→GREEN middle starts from the
`RED:` text rather than re-deriving the acceptance criterion. Optional
by construction (parallel to the loom-asr `Files:` line) — a decision
with no testable altitude carries Tier 0 only and its bead omits the
line (loom-tdua).

## Room

Topic or aspect within a MemPalace wing (e.g., `decisions`, `diary`).

## Subagent

Isolated worker with its own context that returns a reviewable
summary. Loom ships four: `bug-family-researcher`, `drawer-author`,
`kg-relationship-extractor`, `project-onboarder`.

## test-author/implementer split

The `dispatch-middle` discipline of giving the RED test and the
GREEN fix to two INDEPENDENT subagents with disjoint context: the
test-author sees only the locked CONTRACT and writes the failing
test; the implementer sees only the RED-test-as-file and makes it
pass. Neither agent is both author and code-author of the same
behavior — the structural enforcement of the
test-author≠code-author anti-pattern the dispatch-nudge hook also
guards (loom-5m94).

## Tunnel

Explicit cross-wing link in MemPalace.

## Two-tier soundness

The gate `design-a-cycle` checks before handoff (loom-tdua, lineage
loom-5w6). **Tier 0** is the always-on *coherence floor* — the
locked decisions must be internally consistent and grounded.
**Tier 1** is an OPTIONAL *executable-spec ceiling* — a locked
decision with a natural testable altitude emits its spec forward as
the handoff bead's `RED:` line. A decision with no testable altitude
reaches Tier 0 only; forcing Tier 1 on every decision would
re-import the design→build mismatch loom-l0f diagnosed.

## Wing

Project namespace in MemPalace.

## Wisp

Ephemeral beads molecule (no audit trail; deleted after work).
