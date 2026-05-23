---
description: "Sweep the current project's open beads for ones that may be cleared by a recently-closed loom bead. Reads `upstream:loom`-labeled beads + heuristic keyword matches and pairs them against loom's `.beads/issues.jsonl`. Read-only / suggest-only — never closes any project bead."
disable-model-invocation: true
---

Run a cross-tracker sweep: which open beads in this project might be
cleared by a recently-closed loom bead?

## Resolve the loom checkout

Locate loom on disk via `LOOM_REPO_PATH`, defaulting to
`$HOME/repos/loom`:

```bash
LOOM_REPO=${LOOM_REPO_PATH:-$HOME/repos/loom}
[ -d "$LOOM_REPO/.beads" ] || {
  echo "no loom checkout at $LOOM_REPO (set LOOM_REPO_PATH)"
  exit 0
}
```

Never hardcode `/home/<user>/repos/loom`. The env-var default keeps
the command portable across machines and dispatched agents (see
[docs/reference/upstream-loom-label.md](../docs/reference/upstream-loom-label.md)).

## Step 1 — gather candidate project beads

Two passes, unioned:

1. **Labeled set** — beads explicitly carrying `upstream:loom`:

   ```bash
   bd list --label upstream:loom --status=open --json
   ```

2. **Heuristic set** — open beads whose description matches the
   canonical keyword regex:

   ```
   loom-hook | hooks/ | loom-script | scripts/loom- | loom-<id>
   ```

   The `loom-<id>` arm uses word-boundary anchoring (`(^|[^a-zA-Z0-9_])loom-[a-z0-9]+`)
   so substrings like `heirloom-data` do NOT match.

   ```bash
   bd list --status=open --json \
     | jq -r '.[] | select(.description | test("(^|[^a-zA-Z0-9_])(loom-hook|loom-script|loom-[a-z0-9]+)|hooks/|scripts/loom-")) | .id'
   ```

Union the two sets. Heuristic-set members that already carry
`upstream:loom` collapse into the labeled set; heuristic-set members
without the label are candidates for item 15's suggestion (see
`/audit-project`).

## Step 2 — gather recently-closed loom beads

Read closed loom beads from the past 30 days:

```bash
( cd "$LOOM_REPO" && bd list --status=closed --since=30d --json )
```

If `--since` is not supported by the local bd version, fall back to
parsing the project's `.beads/issues.jsonl` directly (filter by
`status=="closed"` and `closed_at` within the window).

For each closed loom bead, extract the touched-file set from its close
reason or commit history. Specifically look for:

- hook names (`hooks/*.sh`)
- script names (`scripts/loom-*`)
- skill/agent paths (`skills/*/SKILL.md`, `agents/*.md`)
- the loom bead-ID itself (some downstream beads reference it
  literally in their description: "mirror of loom-x4m")

## Step 3 — pair candidates to closed loom beads

For each project candidate, compute the intersection between its
description's keyword hits and the closed loom beads' touched-file
set / bead-IDs. Strong pairing signals:

- **Direct bead-ID reference.** Project bead description contains
  `loom-x4m` and loom-x4m is in the closed set → strong pair.
- **Shared hook/script filename.** Project bead mentions
  `hooks/bd-worktree-preseed.sh` and a closed loom bead touched that
  same file → strong pair.
- **Same keyword category.** Project bead mentions `loom-hook` and
  multiple loom hooks closed → weak pair (surface all).

## Step 4 — render the report

```markdown
# Cross-tracker upstream sweep

Loom checkout: <LOOM_REPO> (resolved from LOOM_REPO_PATH or default)
Closed loom beads in window: <N>

## Candidate pairings

| Project bead | Description | Possibly cleared by |
|---|---|---|
| <id> | <one-line snippet> | <loom-id1>, <loom-id2> |

## Unlabeled heuristic matches

These open project beads match the loom-keyword regex but lack the
`upstream:loom` label. Run `/audit-project` for item 15's interactive
labeling gate, or apply manually:

  bd label add <id> upstream:loom

| Project bead | Match | Description |
|---|---|---|
| <id> | <which keyword hit> | <one-line snippet> |
```

If no pairings or matches are found, emit `## No candidates` and
exit 0.

## Contract — read-only / suggest-only

This command **never closes any project bead** and **never modifies
labels**. It only reads from both trackers and renders pairings. The
user reviews each suggested pairing manually, verifies the loom fix
actually addresses the project bead's symptom, and only then runs
`bd close <id>` or `bd label add` themselves.

The label-application half is owned by `/audit-project` item 15
(which has its own y/N/skip gate). This command is the
sweep-and-suggest half — orthogonal, lower-friction, runnable
on-demand or at session start.

## Related

- Label convention reference:
  [`docs/reference/upstream-loom-label.md`](../docs/reference/upstream-loom-label.md).
- Audit integration: `/audit-project` item 15 (upstream-loom-label-suggest).
- Closes: loom-z3m.11 (P2 feature).
