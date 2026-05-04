---
description: "Close-time ritual for a finished bead (or batch of beads). Runs preflight + drafts decision drawer via subagent + drafts KG triples via subagent + closes bead + pushes to remote. The session-end superpower."
disable-model-invocation: true
---

End-of-bead ritual. The user invoked `/wrap-up` after finishing
implementation work on one or more beads. Take them through close +
capture + push, in order:

## 1. Verify ready to close

- Confirm with the user which bead(s) are wrapping up. If multiple,
  treat as a batch and process each in turn.
- Run `bd show <id>` for each bead to get the title + status (must be
  open or in_progress).
- Identify the commits that landed each bead's fix (via
  `git log --grep=<id>` if not already known).

## 2. Preflight checks

- `bd preflight` for PR-readiness gates (lint, stale, orphans).
- Run the project's full test suite with the standard command
  (e.g., `python3 -m pytest -q`) and report exact pass/skip/fail
  counts. Block the wrap-up if any test fails.
- `git status` to confirm working tree is clean.

## 3. Draft decision drawer + KG triples (subagents in parallel)

For each bead being wrapped, dispatch IN PARALLEL:

- `drawer-author` subagent with `bead-id` + commit SHAs. Returns a
  drafted decision drawer body in the project's house style.
- `kg-relationship-extractor` subagent with `bead-id` + commit SHAs.
  Returns up to 5 proposed KG triples.

Present each subagent's output to the user for review. After approval:

- `mempalace_check_duplicate` on the proposed drawer (similarity
  threshold 0.9). If a near-duplicate exists, ask the user whether to
  update the existing drawer (`update_drawer`) or file a new one.
- `mempalace_add_drawer` with the approved drawer body.
- `mempalace_kg_add` for each approved triple.
- `mempalace_diary_write` (params: `agent_name`, `entry`, optional
  `topic`) with an AAAK-compressed one-line session summary in the
  `entry` field. Note: the plugin returns an opaque `-32000 Internal
  tool error` when `entry` is missing or misnamed (e.g., as `content`).

## 4. Close bead(s) + push

- `bd close <id1> <id2> ... --reason="<one-line summary referencing the drawer>"`.
- `bd dolt push`.
- `git push`.
- Final `git status` to confirm "up to date with origin".

## 5. Suggest follow-ups

If the closing surfaced anything worth follow-up (deferred polish,
related beads to file), surface that to the user before exiting. Don't
file beads automatically — let the user decide.

## 6. (loom only) Re-deploy via install.sh

Loom is the workflow-infrastructure repo — its primitives only take
effect once symlinked into `~/.claude/`. Any /wrap-up that landed a
new, renamed, or moved skill / command / agent / hook / lib / script
needs install.sh to run before the changes are actually live.

**Detect loom checkout** (all conditions must hold):
- `pwd` repo root contains `install.sh` AND `settings.snippet.json`
- `install.sh` first line matches `#!/usr/bin/env bash` AND contains
  the literal `loom install.sh` in its header comment

If detected, run the deploy sequence below and report the output to
the user. Skip silently in any other project (this step is a no-op).

```bash
# Re-deploy: install.sh symlinks current loom files into ~/.claude/
# and prunes dangling loom-owned symlinks left over from renamed
# or deleted source files. Idempotent.
./install.sh
```

The historical (a) mkdir prelude (Gap 1) and (b) prune loop (Gap 2)
that used to live here are now folded into install.sh itself
(loom-1nf shipped Gap 3, loom-40e shipped Gap 2, Gap 1 was
silently fixed earlier). See drawer
`drawer_loom_decisions_5c6dbbce59f5373cf7b67935`
("install.sh — TWO RENAME-DEPLOY GAPS FOUND") for the full lineage.

## What to skip

- If the bead was a trivial fix (≤ 1 line), the drawer + KG triples
  may be overkill. Ask before dispatching the subagents.
- If the user explicitly says "no drawer", honour that but warn that
  future-Claude won't have lineage to find on the next sibling bug.
