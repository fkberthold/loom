# upstream:loom — cross-tracker label convention

> Label downstream beads that exist only because of an open loom-side
> bug, so a later loom fix can be paired against them.

## Why this exists

Downstream projects (HAW, liza_base, tla-puzzles, etc.) frequently
file beads as workarounds for loom-side bugs — a misfiring hook, a
broken script, a missing AUTOFIX recipe. When the loom-side bug
eventually closes, the downstream workaround beads are quietly
obsolete, but there is no auto-clearing signal back to the project's
tracker. They linger in `bd ready`, cluttering the queue and tempting
re-implementation.

Surfaced 2026-05-23 (loom-z3m.11): HAW bead `7iz` was filed to mirror
what loom-x4m fixed (bd-worktree-preseed). Once loom-x4m landed and
the hook was installed, `7iz` had no work left — but `bd ready` still
listed it.

The label is the cross-tracker handshake. Pair it with the
`/check-loom-upstream` sweep to surface candidate clearings.

## Label literal

```
upstream:loom
```

The colon form (`<scope>:<value>`) is deliberate. It composes with bd's
existing label conventions (`type:bug`, `priority:p1`, `area:hooks`),
so listing / filtering by `--label upstream:loom` works without any
ambiguity. The alternative `loom-bug` was rejected because it reads
like a bead prefix (`loom-xyz`) and collides visually with loom's own
bead-IDs in `bd list` output.

## How to apply

When filing a bead that exists only because of a loom-side bug:

```bash
bd create "Workaround for loom-hook bd-close-capture mis-firing" \
  --label upstream:loom \
  --label type:bug
```

Or on an existing bead:

```bash
bd label add <bead-id> upstream:loom
```

If you noticed the workaround character only after filing, the audit
flow surfaces this — see "Audit integration" below.

## Audit integration

`/audit-project` ships item 15 ("Upstream:loom label suggestion") that
scans the project's open beads for descriptions matching the canonical
keyword set:

```
loom-hook | hooks/ | loom-script | scripts/loom- | loom-<id>
```

For each matching bead that lacks the `upstream:loom` label, the audit
emits an `INFO` line with a y/N/skip gate offering to apply the label.
**Informational only — never auto-applied.** A `skip` response writes
a memo to `.claude/loom-audit-state.json` so the same row does not
re-prompt on subsequent audits.

## /check-loom-upstream sweep

The companion slash command `/check-loom-upstream` reads
the project's `upstream:loom`-labeled beads and queries the loom repo
(via `LOOM_REPO_PATH`) for recently-closed loom beads that may have
addressed them. It pairs candidates and surfaces them as a
suggestion — read-only, never closes any project bead. The user
decides what to clear.

## LOOM_REPO_PATH

The loom repo's `.beads/issues.jsonl` is the source of truth for
recently-closed loom beads. The check-loom-upstream sweep needs to
locate that repo on disk. Resolution order:

1. `$LOOM_REPO_PATH` env var if set
2. `$HOME/repos/loom` (the documented default)

Override when your loom checkout lives elsewhere:

```bash
LOOM_REPO_PATH=~/code/loom /check-loom-upstream
```

Never hardcode `/home/<user>/repos/loom` in skills, commands, or
scripts. The env-var pattern keeps the tooling portable across
machines and dispatched agents.

## When NOT to use the label

- Beads that fix a project-internal bug that happens to touch a loom-
  installed hook. The label is for "this bead exists because loom is
  buggy" — not "this bead's path happens to overlap loom's surface."
- Beads tracking loom-feature requests filed in a project's tracker.
  Those should be filed in the loom tracker (`cd ~/repos/loom && bd
  create ...`) instead. Project trackers carry project-scoped work.

## Opposite direction — `upstream:work` and `upstream:watch`

The `upstream:loom` label moves discipline *into* loom from a
downstream project. The opposite direction — moving a fix from
loom OUT to someone else's repo — uses two paired labels:

| Label | Applied to | Meaning |
|---|---|---|
| `upstream:work` | A loom-side work-bead | Drives the upstream contribution. Closes FAST on PR file via the [`upstream-a-bead`](upstream-a-bead.md) recipe. |
| `upstream:watch` | A loom-side watch-bead | Auto-spawned at M7 of the recipe. Closes SLOW when [`/check-upstream-prs`](slash-commands/all-commands.md) detects the upstream PR merged (or surfaces for review on rejection). |

If you are filing a workaround bead in a downstream project because
of a loom-side bug, use `upstream:loom` (this page). If you are
filing a fix *against* someone else's repo from inside loom, use
`upstream:work` and follow [Contribute upstream](../how-to/contribute-upstream.md).
The two label conventions compose orthogonally — a single bead
never carries both.

## Lineage

- Closes: loom-z3m.11 (P2 feature, design locked 2026-05-22)
- Parent: loom-z3m (Cross-tracker dependency awareness epic)
- Sibling beads: HAW bead `7iz` (the canonical mirror-of-loom-x4m
  example that motivated this); future similar pairs.
