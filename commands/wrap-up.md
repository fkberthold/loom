---
description: "Close-time ritual for a finished bead (or batch of beads). Runs preflight + drafts decision drawer via subagent + drafts KG triples via subagent + closes bead + pushes to remote. The session-end superpower."
disable-model-invocation: true
---

End-of-bead ritual. The user invoked `/wrap-up` after finishing
implementation work on one or more beads. Take them through close +
capture + push, in order:

## 1. Verify ready to close

**Discovery sub-step (before asking the user)**: scan main for beads
that were merged but never closed. Surfaces stranded work from prior
parallel-dispatch sessions where the user's memory was the only
binding between "merged" and "closed" (loom-6p6, 2026-05-27 — after
loom-7p6.2–.6 were merged 2026-05-26 but never closed). Run the
snippet below; if it surfaces any IDs, present them as the default
close-set to the user with `"Found N bead(s) merged-to-main but
still open: <ids>. Close all?"` — user confirms, edits, or
overrides. If empty, fall through silently.

```bash
# DISCOVERY:START — find beads merged to main but still open/in_progress.
# Prefix-agnostic; reuses the canonical bead-ID regex from
# hooks/bd-close-capture.sh. Idempotent + safe to run in any project.
since=$(bd list --status=closed --json 2>/dev/null \
  | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: d=[]
print(max((x.get("closed_at","") for x in d if x.get("closed_at")), default=""))' 2>/dev/null)
[ -z "$since" ] && since='7 days ago'
ids=$(git log --since="$since" --format='%s' main 2>/dev/null \
  | grep -oE '[a-z][a-z0-9_-]*-[0-9a-z]{3,}(\.[0-9a-z]+)*' \
  | sort -u)
open_ids=""
for id in $ids; do
  status=$(bd show "$id" --json 2>/dev/null \
    | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: d=[]
print(d[0].get("status","") if isinstance(d,list) and d else "")' 2>/dev/null)
  case "$status" in open|in_progress) open_ids="$open_ids $id" ;; esac
done
open_ids=$(printf '%s\n' $open_ids | grep -v '^$' | sort -u)
if [ -n "$open_ids" ]; then
  echo "Found bead(s) merged-to-main but still open:"
  printf '  %s\n' $open_ids
fi
# DISCOVERY:END
```

Then continue with the user-confirmation flow:

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
- `bd dolt push` — but guard for solo workspaces (loom-hsb):
  ```bash
  if bd dolt remote list --json 2>/dev/null | grep -q '"name"'; then
    bd dolt push
  else
    echo "(solo bd workspace; no Dolt remote — skipping bd dolt push)"
  fi
  ```
- `git push`.
- Final `git status` to confirm "up to date with origin".

## 5. Suggest follow-ups

If the closing surfaced anything worth follow-up (deferred polish,
related beads to file), surface that to the user before exiting. Don't
file beads automatically — let the user decide.

## 6. Surface project deploy hint (if configured)

Some projects need a follow-up command run after the bead lands —
loom needs `./install.sh` to symlink primitives into `~/.claude/`;
a service repo might need a build step; most projects need
nothing.

Read the project's `.claude/workflow.json` `.deploy` field. If it
resolves to a non-empty string, surface it as a hint AND STOP —
do not auto-run it. The user decides when (and whether) to
execute the command.

```bash
# Print "Next step (project deploy): <cmd>" if .deploy is set;
# silent no-op otherwise. Always exits 0; safe in any project.
~/.claude/scripts/loom-print-deploy-hint
```

The script wraps `workflow_resolve_deploy` in a bash-shebanged
executable so it works regardless of the invoking shell (the lib
itself uses `BASH_SOURCE` for path detection and is bash-only;
the wrapper isolates that constraint).

**Configuring a project:** add a `.deploy` string to
`<project>/.claude/workflow.json`:

```json
{ "v": 1, "mode": "full", "deploy": "./install.sh" }
```

Loom itself ships this set to `./install.sh`. Any other project
that wants a hint adds its own command — `./scripts/build`,
`make deploy`, `kubectl apply -k ...`, whatever.

History: this section used to detect-and-run loom's `install.sh`
by literal-match on the file header, which leaked loom-specific
guidance into unrelated projects when Claude elided the literal
check (loom-0k0, 2026-05-26). The current shape is generic +
surface-only — projects opt in via workflow.json, and `/wrap-up`
never auto-runs a command. See
`drawer_loom_decisions_5c6dbbce59f5373cf7b67935`
("install.sh — TWO RENAME-DEPLOY GAPS FOUND") for the earlier
install.sh-gap lineage that lived in this section.

## What to skip

- If the bead was a trivial fix (≤ 1 line), the drawer + KG triples
  may be overkill. Ask before dispatching the subagents.
- If the user explicitly says "no drawer", honour that but warn that
  future-Claude won't have lineage to find on the next sibling bug.
