---
description: "Run the upstream-a-bead activity recipe on the named upstream-contribution bead. Loads the upstream-a-bead skill (which defers to bead-lifecycle-shell for phases A/B/C/D and owns the upstream-specific variable middle: lock-lane → clone → RED → GREEN → draft → review → file + spawn watch-bead). Two lanes: --issue-only (codifies the loom-45i triad filing pattern; skips M3-M5) and --issue+pr (full clone + RED/GREEN + PR draft)."
disable-model-invocation: true
---

Invoke the `upstream-a-bead` skill and follow it exactly as presented.

If the user supplied a bead-id as the slash-command argument, treat that
as the chosen bead and start at phase A1 (MemPalace upstream-family
search). If no bead-id was supplied, run `bd list --label=upstream:work
--status=open` first and confirm with the user which bead to work
before claiming.

At step M1: lock the contract (symptom + diagnosis + proposed fix) AND
pick the lane (`--issue-only` / `--issue+pr` / intractable) BEFORE
dispatching the worker. Lane is the load-bearing decision — surface it
explicitly to the user and get confirmation.

At step M6: present the drafted `/tmp/issue-<bead>.md` (and
`/tmp/pr-<bead>.md` for `--issue+pr`) inline to the user and wait for
explicit approval before the M7 `gh` calls. The review gate is the
privacy-redaction guard per loom-45i — never auto-file on worker
return.

At phase D3: dispatch `drawer-author` and `kg-relationship-extractor`
subagents in parallel; review each subagent's output before filing
via `mempalace_add_drawer` / `mempalace_kg_add`. The closing drawer
must include WHAT LANDED + privacy-redactions + fork-detection +
CONTRIBUTING-adaptations sections.

For non-upstream beads (bug, feature, refactor, research, cleanup,
docs), use the matching `<activity>-a-bead` recipe directly, or
invoke `/working-a-bead <bead-id>` to let the router pick.
