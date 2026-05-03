---
description: "Run the canonical 14-step end-to-end bead workflow on the named bead. Loads the working-a-bead skill and follows it step by step, dispatching the bug-family-researcher subagent at step 1 and the drawer-author + kg-relationship-extractor subagents at step 14."
disable-model-invocation: true
---

Invoke the `working-a-bead` skill and follow it exactly as presented.

If the user supplied a bead-id as the slash-command argument, treat that
as the chosen bead and start at step 1 (MemPalace bug-family search).
If no bead-id was supplied, run `bd ready` first and confirm with the
user which bead to work before claiming.

At step 1: dispatch the `bug-family-researcher` subagent with the
bead's title + symptom; use its prior-art report to inform the design
BEFORE proceeding to step 4 (TDD).

At step 14: dispatch `drawer-author` and `kg-relationship-extractor`
subagents in parallel; review each subagent's output before filing
via `mempalace_add_drawer` / `mempalace_kg_add`.
