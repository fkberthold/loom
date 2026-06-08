# `templates/design-doc/` — the L2 living-design-document skeleton

This directory holds the skeleton for a **DESIGN DOC drawer** — the L2
prose working-surface a [`/design-a-cycle`](../../skills/design-a-cycle/)
orchestrator maintains across a design cycle. It mirrors
[`templates/diataxis/`](../diataxis/): a `*.template` skeleton with
`{{ }}` placeholders that a consumer substitutes with `sed`.

## What's here

- `DESIGN-DOC.md.template` — the skeleton. A structured **STATE HEADER**
  (the orchestrator reads/updates it each cycle) above the prose
  reasoning sections (Question/Scope, Decisions-locked, Grounding-
  checklist, Lineage).

## Where it lives once populated

Unlike the diataxis tree (which becomes a `docs/` site built by
mkdocs), a populated design doc is the **body of a MemPalace drawer**
in the `<wing>/decisions` room. There is no build step — copy the
populated body into a drawer via `mempalace_add_drawer`, then keep it
current with `mempalace_update_drawer`. It is the L2 layer of the
three-layer substrate:

- **L1** — the MemPalace KG spine (durable source-of-truth, agent-
  optimized). Locked decisions PRECIPITATE into KG triples.
- **L2** — *this drawer* (prose working-surface; reason here, then
  precipitate). Wins on narrative INTENT; the KG wins on queryable
  CURRENT-STATE.
- **L3** — optional executable specs (Given-When-Then / `INVARIANT:`)
  that become a handoff bead's RED test.

## Substitution mechanism

Substitution is plain `sed` — no Python, no envsubst, no external
scaffold tool (loom is mostly markdown + bash + JSON per `CLAUDE.md`),
matching the `templates/diataxis/` convention exactly. Two tokens:

| Token         | Replace with                                  |
|---------------|-----------------------------------------------|
| `{{ topic }}` | the design cycle's topic (e.g. `auth rework`) |
| `{{ wing }}`  | the MemPalace wing (e.g. `loom`)              |

Copy the skeleton, substitute the two tokens, then drop the
`.template` suffix:

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

After substitution, `grep -r '{{' /tmp/my-design` should return
nothing — any surviving `{{ ... }}` is an unfilled placeholder.
