---
description: "Run the bugfix-a-bead activity recipe on the named bug bead. Loads the bugfix-a-bead skill (which defers to bead-lifecycle-shell for phases A/B/C/D and owns the bug-specific variable middle: debug → RED → GREEN → bug-class → enshrined-sweep). Dispatches the bug-family-researcher subagent at phase A1 and the drawer-author + kg-relationship-extractor subagents at phase D3."
disable-model-invocation: true
---

Invoke the `bugfix-a-bead` skill and follow it exactly as presented.

If the user supplied a bead-id as the slash-command argument, treat that
as the chosen bead and start at phase A1 (MemPalace bug-family search).
If no bead-id was supplied, run `bd ready` first and confirm with the
user which bead to work before claiming.

At phase A1: dispatch the `bug-family-researcher` subagent with the
bead's title + symptom; use its prior-art report to inform the design
BEFORE proceeding to step M2 (TDD RED).

At phase D3: dispatch `drawer-author` and `kg-relationship-extractor`
subagents in parallel; review each subagent's output before filing
via `mempalace_add_drawer` / `mempalace_kg_add`.

For non-bug beads (feature, refactor, research, cleanup, docs), use
the matching `<activity>-a-bead` recipe directly, or invoke
`/working-a-bead <bead-id>` to let the router pick.
