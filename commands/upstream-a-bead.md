---
description: "Run the upstream-a-bead activity recipe on the named upstream-contribution bead. Loads the upstream-a-bead skill (which defers to bead-lifecycle-shell for phases A/B/C/D and owns the upstream-specific variable middle: lock-lane → clone → RED → GREEN → draft → review → file + spawn watch-bead). Two lanes: --issue-only (codifies the loom-45i triad filing pattern; skips M3-M5) and --issue+pr (full clone + RED/GREEN + PR draft)."
disable-model-invocation: true
---

Invoke the `upstream-a-bead` skill and follow it exactly as presented.

If the user supplied a bead-id as the slash-command argument, treat that
as the chosen bead and start at phase A1 (MemPalace upstream-family
search). If no bead-id was supplied, run `bd list --label=upstream:work
--limit 0 --status=open` and take the top-priority open bead. Say in one
line which bead you took and what else was ready, then claim it.

At step M1: lock the contract (symptom + diagnosis + proposed fix) and
pick the lane (`--issue-only` / `--issue+pr` / intractable) before
dispatching the worker. The upstream tree decides the lane: whether it
has a test harness, whether the change is prose or code, and what its
CONTRIBUTING.md asks for. Announce the lane you picked and what decided
it.

At step M6: show the user only the strings the M5 scrub flagged as
candidate-private, with your call on each. Wait for a yes before the M7
`gh` calls. Which project names are codenames, and which affiliations
the user wants public, isn't derivable from any tree, so that list is
the whole ask. A filed issue keeps a public edit history, so a leaked
string stays leaked.

At phase D3: dispatch `drawer-author` and `kg-relationship-extractor`
subagents in parallel; review each subagent's output before filing
via `mempalace_add_drawer` / `mempalace_kg_add`. The closing drawer
must include WHAT LANDED + privacy-redactions + fork-detection +
CONTRIBUTING-adaptations sections.

For non-upstream beads (bug, feature, refactor, research, cleanup,
docs), use the matching `<activity>-a-bead` recipe directly, or
invoke `/working-a-bead <bead-id>` to let the router pick.
