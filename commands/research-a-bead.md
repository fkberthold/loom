---
description: "Run the research-a-bead activity recipe on the named research bead. Loads the research-a-bead skill (which defers to bead-lifecycle-shell for phases A/B/C/D and owns the research-specific variable middle: define-question → search-prior-art → fetch-authoritative-docs → synthesize → file-findings). The drawer + KG triples filed at M5 ARE the deliverable — research beads are no-code by default."
disable-model-invocation: true
---

Invoke the `research-a-bead` skill and follow it exactly as presented.

If the user supplied a bead-id as the slash-command argument, treat that
as the chosen bead and start at phase A1 (MemPalace family search).
If no bead-id was supplied, run `bd ready` first and confirm with the
user which bead to work before claiming.

At phase A1: do the standard family search; if a sibling research
drawer already answers the question, restate the bead as "extends X"
or "narrows X" before proceeding to M1.

At step M1: state the operational question (one or two sentences) to
the user BEFORE searching. Misframed questions are the most expensive
failure mode of this recipe.

At step M5: dispatch `drawer-author` and `kg-relationship-extractor`
subagents (in parallel) to draft the closing artifacts. The drawer
is the bead's primary deliverable — file it BEFORE phase D3.

For non-research beads (bug, feature, refactor, cleanup, docs), use
the matching `<activity>-a-bead` recipe directly, or invoke
`/working-a-bead <bead-id>` to let the router pick.
