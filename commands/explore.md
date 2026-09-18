---
description: "Open or advance an exploration for <idea>. Loads the explore skill — loom's above-bead SUB-design primitive, the front-door to /design-a-cycle (the ladder is explore → design → build). It blends FOUR source tiers (1 self · 2 repo+docs · 3 web · 4 peer-reviewed literature) to converge WITH the user on shared understanding, via a HYBRID loop: light tiers 1+2 in-thread, heavy tiers 3+4 dispatched as a deep-research round when a thread needs grounding, central writes nothing but the capture (lean-central). Memory is ONE drawer in the <wing>/decisions room tagged exploration. NOT a bead and NOT a design cycle — no soundness gate, no epic. Two user-declared exits, one of which central recommends while naming the other as the live alternative: REST (status=rested, standing artifact) and PROMOTE (opens /design-a-cycle whose decisions are wired grounded_in this drawer, status=promoted)."
disable-model-invocation: true
---

Invoke the `explore` skill and follow it exactly as presented.

If the user supplied an `<idea>` as the slash-command argument
(`$ARGUMENTS`), treat that as the exploration's question and start by
reading the substrate STATE for it: search the project's
`<wing>/decisions` room for an existing drawer tagged `exploration`
whose question matches. If no `<idea>` was supplied, ask the user what
to explore before seeding any drawer.

If an active exploration drawer already exists for `$ARGUMENTS`, READ
its STATE HEADER first and ADVANCE it — do not re-seed over it. If none
exists, seed one from `templates/exploration/EXPLORATION.md.template`
(plain `sed` substitution of `{{ question }}` / `{{ wing }}`), file it
into `<wing>/decisions` via `mempalace_add_drawer`, and tag it
`exploration`.

Run the HYBRID loop: light tiers (1 self + 2 repo+docs) in-thread with
the user; heavy tiers (3 web + 4 peer-reviewed literature) dispatched
as a `deep-research` round WHEN a thread needs grounding — not every
turn. Synthesize the returns back into the dialogue and precipitate
FIRM findings into the drawer + KG triples; central writes nothing but
the capture (lean-central, loom-5m94).

At the exit gate the user declares the exit, and you still take a
position. Start with the read off the STATE HEADER, in numbers rather
than adjectives. Three signals carry it: how many `open-threads` are
still being chased, whether `current-understanding` moved this round or
held, and whether tier 4 ran on a topic that has a literature. "Two
open threads, understanding unchanged for two rounds, tier 4 done" is a
read the user can overrule. "The exploration looks mature" isn't.

Then recommend one exit and name the other as the live alternative.
Threads shrinking to none with the understanding holding steady points
at PROMOTE. Threads still opening, or an untouched tier 4 on a topic
with a literature, points at REST. Say which one you'd take and why in
a line, then name the other.

A recommendation isn't a decision. Do NOT auto-promote, do NOT
auto-rest, and do NOT flip `status` on implicit assent. The user picks:

- **REST** → set `status=rested`; the drawer stands as a standing
  understanding artifact.
- **PROMOTE** → open `/design-a-cycle` on the converged topic, wire its
  decisions `grounded_in` this exploration drawer, and set
  `status=promoted`.

This is an ABOVE-bead SUB-design primitive, NOT a bead and NOT a design
cycle — there is no soundness gate and no epic emission. To open a full
design cycle directly (the idea is already design-ready), use
`/design-a-cycle <topic>` instead.
