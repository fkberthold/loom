# Design-doc template

> The L2 living-design-document skeleton at `templates/design-doc/`. A
> `*.template` file with `{{ topic }}` / `{{ wing }}` placeholders that
> a consumer substitutes with `sed`. Once populated, it becomes the
> body of a MemPalace drawer in the `<wing>/decisions` room — the L2
> prose working-surface a [`/design-a-cycle`](design-a-cycle.md)
> orchestrator maintains across a design cycle.

## Why this exists

T1 (`loom-dhra`) of epic **loom-tdua** — the design-phase system. A
design cycle reasons in prose but must precipitate its locked results
into structure. The template gives that prose a fixed shape: a
machine-read STATE HEADER the orchestrator reads/updates every cycle,
above human-and-agent-readable reasoning sections. It mirrors
`templates/diataxis/` exactly — a skeleton with `{{ }}` tokens
substituted by plain `sed`, no Python, matching loom's
markdown + bash + JSON constitution.

The consumer is `/design-a-cycle`: Step 1 of its sequence scaffolds a
populated drawer from this skeleton when no design-doc drawer exists for
the topic; Steps 0 and 2 read and update the STATE HEADER on every
subsequent invocation.

## Files

`templates/design-doc/` holds two files:

| File | Role |
|---|---|
| `DESIGN-DOC.md.template` | The skeleton. STATE HEADER + four reasoning sections. Substituted, suffix-stripped, then filed as a drawer body. |
| `README.md` | Directory README. Documents the substitution mechanism and where the populated doc lives. Not part of the drawer body. |

## The layered substrate

The populated design doc is the **L2 layer** of a three-layer design
substrate. There is no build step (unlike the diataxis tree, which
mkdocs renders into a site): the populated body is copied into a
MemPalace drawer via `mempalace_add_drawer` and kept current with
`mempalace_update_drawer`.

| Layer | What | Wins on |
|---|---|---|
| **L1** | The MemPalace KG spine — durable, agent-optimized source-of-truth. Locked decisions PRECIPITATE into KG triples. | Queryable CURRENT-STATE |
| **L2** | *This drawer* — the prose working-surface. Reason here, then precipitate. | Narrative INTENT |
| **L3** | Optional executable specs (Given-When-Then / `INVARIANT:`) that become a handoff bead's RED test. | Testable altitude |

The governing discipline is **reason in prose → precipitate to L1 KG**:
in-flight thinking happens on the permissive L2 prose surface, and as
decisions firm up they precipitate into the structured destinations
(L1 KG facts + the L2 locked-decision sections + `RED:`/`Files:` lines
on emitted beads). When L1 and L2 diverge, the KG wins on current-state
and the drawer wins on intent.

## STATE HEADER schema

The block at the top of the populated drawer that the orchestrator reads
and updates each cycle. `session-startup` surfaces active design cycles
by scanning for open `[CLARIFICATION]` markers in this header. The fields:

| Field | Type | Meaning |
|---|---|---|
| `cycle-number` | integer | The cadence iteration count. Starts at 0 in a fresh scaffold. |
| `soundness-status` | `red` / `amber` / `green` | The Tier-0 coherence gate state. Starts `red`. Do NOT hand off until `green`. |
| `locked-decisions` | list | Short handle of each decision that has locked (precipitated into all its layers). Empty in a fresh scaffold. |
| `open [CLARIFICATION] markers` | list | Each unresolved question, written as `[CLARIFICATION: <question>]`. A fresh scaffold carries one seed marker. The cadence drives toward emptying this list. |
| `spawned research-bead IDs` | list | Each `research-a-bead` spawned to ground an open marker. Lets the cycle track which markers are in-flight. |
| `target implementation-epic ID` | string | The epic the cycle handed off to. Set when `create-beads` runs at handoff; empty until then. |

## Reasoning sections

Below the STATE HEADER, four prose sections carry the cycle's narrative
reasoning:

### Question / Scope

The operational question the cycle answers, and the boundary — what is in
scope and what is explicitly out (the YAGNI cut). One or two paragraphs.
A reader should be able to tell whether a given concern belongs in the
cycle without reading further.

### Decisions-locked

One prose block per locked decision (`D1`, `D2`, …). Each block has a
fixed inner shape, and each PRECIPITATES into the L1 KG and (when it has
a testable altitude) an L3 spec:

| Sub-part | Content |
|---|---|
| **Decision** | The locked choice, one or two sentences. |
| **Grounding** | What the decision rests on — a research drawer ID, a sibling bead, a HAW lesson, or a source URL. No grounding ⇒ not yet sound (the Tier-0 floor). |
| **Options / why-not** | The alternatives considered and why each was rejected. |
| **L3 spec (optional)** | Tier-1 executable-spec emission. When the decision has a natural executable altitude, the spec written here seeds the spawned bead's RED test. A Given-When-Then scenario for behavioral altitude, or an `INVARIANT: <property>` line for structural altitude. A decision with no testable altitude carries Tier-0 only — expected and fine. |

### Grounding-checklist

The Tier-0 coherence gate, mechanized as a checklist (checklists act as
unit tests for specifications). The cycle is green only when every box is
checked:

- [ ] Every locked decision cites its grounding.
- [ ] Every locked decision names options-considered + why-not.
- [ ] No unresolved `[CLARIFICATION]` markers remain in the STATE HEADER.
- [ ] No locked decision violates a recorded constitutional invariant.
- [ ] Each Tier-1 decision's L3 spec is ready to seed its bead's RED test.

### Lineage

Provenance anchors: the wing/room, the grounding research drawers the
cycle consumed, the supersedes/superseded-by chain of prior design
drawers, and the emitted implementation epic (once `create-beads` runs).

## Substitution mechanism

Substitution is plain `sed` — no Python, no `envsubst`, no external
scaffold tool — matching the `templates/diataxis/` convention. Two tokens:

| Token | Replace with |
|---|---|
| `{{ topic }}` | The design cycle's topic (e.g. `auth rework`) |
| `{{ wing }}` | The MemPalace wing (e.g. `loom`) |

Copy the skeleton, substitute the two tokens, then drop the `.template`
suffix:

```bash
TOPIC="auth rework"
WING="loom"

cp -r templates/design-doc/. /tmp/my-design/

# substitute placeholders in every regular file
find /tmp/my-design -type f -exec sed -i \
  -e "s|{{ topic }}|$TOPIC|g" \
  -e "s|{{ wing }}|$WING|g" \
  {} +

# rename *.template -> *
find /tmp/my-design -type f -name '*.template' \
  -exec sh -c 'mv "$1" "${1%.template}"' _ {} \;
```

After substitution, `grep -r '{{' /tmp/my-design` must return nothing —
any surviving `{{ ... }}` is an unfilled placeholder.

## Cross-references

- **Template:** `templates/design-doc/DESIGN-DOC.md.template`
- **Template README:** `templates/design-doc/README.md`
- **Consumer:** [`/design-a-cycle`](design-a-cycle.md) (T2 of loom-tdua)
- **Foundation bead:** loom-dhra (T1 — this skeleton)
- **Parent epic:** loom-tdua (design-phase system)
- **Soundness lineage:** loom-5w6 (two-tier soundness + living-doc home)
- **Downstream contract consumer:** [`/dispatch-middle`](dispatch-middle.md) (reads the `RED:` line each Tier-1 decision emits)
