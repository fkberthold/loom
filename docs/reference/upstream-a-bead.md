# upstream-a-bead — reference

> Activity recipe for working an upstream-contribution-shaped bead.
> Owns the upstream-specific variable middle — lock contract + lane
> → clone upstream into `~/.loom/upstream/` → RED test → minimal
> GREEN fix → draft issue + PR with privacy redaction → user review
> gate → auto-file via `gh` + spawn watch-bead. Defers to the
> `bead-lifecycle-shell` skill for claim / isolate / verify / close /
> capture.

The recipe is the 7th sibling of the activity matrix
(bugfix / feature / refactor / research / cleanup / docs / upstream).
It runs in two lanes: `--issue-only` (codifies the loom-45i triad
filing pattern; skips M3-M5 of the variable middle) and `--issue+pr`
(full clone + RED/GREEN + PR draft). Lane is decided at M1 based on
bead framing and central judgment. A third "intractable /
upstream-pending" option terminates after M1 with a drawer-only
outcome (the loom-98x pattern).

The conceptual shift from sibling recipes is that the deliverable
lives *outside loom*. Loom-side phase C still commits a drawer +
branch on `frank/<bead-id>`, but the value the user cares about is
an upstream issue (and optionally a PR with RED/GREEN evidence)
filed against someone else's repo. The work-bead closes FAST on PR
file; a paired watch-bead is auto-spawned at M7 and closes SLOW
when [`/check-upstream-prs`](slash-commands/index.md) detects the
upstream merge.

## Related

| Item | Page |
|---|---|
| Sibling recipes (`bugfix-a-bead`, etc.) | [All skills](skills/all-skills.md) |
| Recipe-family design rationale | [Recipe family](../explanation/recipe-family.md) |
| End-to-end walkthrough | [Contribute upstream](../how-to/contribute-upstream.md) |
| Cross-tracker label (opposite direction) | [upstream:loom label](upstream-loom-label.md) |
| Slash commands (`/check-upstream-prs`, `/loom-upstream-gc`) | [All commands](slash-commands/all-commands.md) |

## Skill source

The full recipe body is included verbatim below from
`skills/upstream-a-bead/SKILL.md`. Edits go to the primitive, not
this page.

{%
  include-markdown "../../skills/upstream-a-bead/SKILL.md"
  heading-offset=1
%}
