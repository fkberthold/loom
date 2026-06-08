# `templates/exploration/` — the light exploration-drawer skeleton

This directory holds the skeleton for an **EXPLORATION drawer** — the
light, SUB-design artifact that the [`/explore`](../../commands/)
command seeds when you open an exploration. It mirrors
[`templates/design-doc/`](../design-doc/) and
[`templates/diataxis/`](../diataxis/): a `*.template` skeleton with
`{{ }}` placeholders that a consumer substitutes with `sed`.

## What an exploration is

`/explore <idea>` opens **an exploration** — a NEW above-bead,
*sub-design* primitive, and the front-door to
[`/design-a-cycle`](../../skills/design-a-cycle/). An exploration is
**NOT a bead** and **NOT a design cycle**: there is no soundness gate.
Its purpose is to converge WITH the user on a shared understanding by
blending four source tiers:

- **Tier 1** — self / current-context reasoning.
- **Tier 2** — repo + docs dig.
- **Tier 3** — web common-usage.
- **Tier 4** — peer-reviewed literature.

The loop is **hybrid**: the light tiers (1 + 2) run in-thread; the
heavy tiers (3 + 4) are dispatched as a `deep-research` round when the
question warrants it.

## What's here

- `EXPLORATION.md.template` — the skeleton. A structured **STATE
  HEADER** (the exploration loop reads/updates it on every touch)
  above two prose-and-precipitate sections (**Inquiry log** — the
  permissive reasoning surface; **Findings** — the precipitated layer,
  each with provenance) plus **Lineage**.

### STATE HEADER fields

- **question** — the idea being explored (the `{{ question }}` token).
- **status** — one of `active` | `rested` | `promoted` (see the two
  exits below).
- **tiers-touched** — which of the four source tiers have been
  consulted.
- **open-threads** — unresolved sub-questions still being chased.
- **current-understanding** — the running synthesis the user and agent
  converge on.
- **opened** / **last-touched** — drawer lifecycle dates.
- **rested-on** / **promoted-to** — set when the matching exit fires.

### The two exits

An exploration ends one of two ways, recorded in `status`:

- **REST** — park it. `status` → `rested`, `rested-on` dated. The
  drawer stays in the palace as durable thinking; nothing is lost.
- **PROMOTE** — escalate it. `status` → `promoted`, `promoted-to` set,
  and `/design-a-cycle` opens a design cycle whose decisions are
  `grounded_in` this drawer.

## Where it lives once populated

Unlike the diataxis tree (which becomes a `docs/` site built by
mkdocs), a populated exploration is the **body of a MemPalace drawer**
in the `<wing>/decisions` room, tagged `exploration` (tag-not-room).
There is no build step — copy the populated body into a drawer via
`mempalace_add_drawer`, then keep it current with
`mempalace_update_drawer` as the four tiers come in.

The recommended (SOFT, not enforced) KG predicates for an exploration
are `explores`, `grounded_in`, `surfaced_finding`, `has_open_thread`,
and `informs_design_of`.

## Substitution mechanism

Substitution is plain `sed` — no Python, no envsubst, no external
scaffold tool (loom is mostly markdown + bash + JSON per `CLAUDE.md`),
matching the `templates/design-doc/` and `templates/diataxis/`
conventions exactly. Two tokens:

| Token            | Replace with                                       |
|------------------|----------------------------------------------------|
| `{{ question }}` | the exploration's question (e.g. `explore the X`)  |
| `{{ wing }}`     | the MemPalace wing (e.g. `loom`)                   |

Copy the skeleton, substitute the two tokens, then drop the
`.template` suffix:

```bash
QUESTION="what shape should the explore primitive take"
WING="loom"

cp -r templates/exploration/. /tmp/my-exploration/

# substitute placeholders in every regular file
find /tmp/my-exploration -type f -exec sed -i \
  -e "s|{{ question }}|$QUESTION|g" \
  -e "s|{{ wing }}|$WING|g" \
  {} +

# rename *.template -> *
find /tmp/my-exploration -type f -name '*.template' \
  -exec sh -c 'mv "$1" "${1%.template}"' _ {} \;
```

After substitution, `grep -r '{{' /tmp/my-exploration` should return
nothing — any surviving `{{ ... }}` is an unfilled placeholder.
