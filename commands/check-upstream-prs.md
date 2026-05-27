---
description: "Sweep open `upstream:watch` beads in the current project, query gh for each PR's state, and auto-close MERGED watch-beads. Surfaces CLOSED (rejected) and unreachable PRs for the user to review. No-op on still-OPEN PRs. Schedulable via the existing wake-up scheduler."
disable-model-invocation: true
---

Periodic sweep over the project's `upstream:watch` beads. Mirrors
`/check-loom-upstream` in shape but flows the OPPOSITE direction —
that command asks "which local beads might a recent LOOM close
clear?", this command asks "which local watch-beads can be cleared
because their UPSTREAM PR merged?".

Watch-beads are spawned at upstream-a-bead M7 with the upstream PR
URL embedded in their description (see
`skills/upstream-a-bead/SKILL.md` § M7 "Watch-bead spawn"). This
command parses that URL, queries the PR's current state, and
reconciles the bead.

Design source:
[`drawer_loom_decisions_a6e64f9cfb21a9d16fc47604`](mempalace://drawer_loom_decisions_a6e64f9cfb21a9d16fc47604)
(loom/decisions wing, 2026-05-27).

## What it does

For each open bead carrying the `upstream:watch` label:

1. Extract the first GitHub PR URL (`https://github.com/<owner>/<repo>/pull/<N>`)
   from the bead description.
2. `gh pr view <url> --json state,mergedAt`.
3. Dispatch on `state`:
   - **MERGED** → `bd close <bead-id> --reason="upstream merged: <PR-URL>"`.
   - **CLOSED** (rejected without merge) → surface for the user; do
     NOT auto-close. User decides whether to file a follow-up,
     adjust the upstream PR, or manually close the watch-bead.
   - **OPEN** → no-op. The sweep is idempotent for still-OPEN PRs.
   - **gh query failed / URL malformed / URL missing** → surface
     for the user; skip without aborting the sweep.

The sweep continues past any single failure — one unreachable URL
does not block reconciliation of the other watch-beads.

## Contract

- **Auto-closes only on `state == MERGED`.** Never on CLOSED, OPEN,
  or query-failure. Auto-closing on CLOSED would silently swallow
  rejection signal; auto-closing on query-failure would lose the
  watch-bead to a transient `gh` outage.
- **Read-only on bd state for non-MERGED.** No label edits, no
  status flips except the one explicit `bd close` per MERGED bead.
- **Idempotent.** Re-running the sweep with the same PR states
  produces the same set of closes; already-closed watch-beads are
  not in the `bd list --status=open` set on the next pass.
- **No new infrastructure.** Schedulable via the wake-up scheduler
  that ships with loom; this command is the unit of work, the
  scheduler is the cadence layer. Default cadence is deferred (see
  loom-k2g.3 description); user wires it up explicitly today.

## The sweep

```bash
# SWEEP — see lib/tests/check-upstream-prs.test.sh
set -uo pipefail

# 1. Gather open upstream:watch beads as id<TAB>description lines.
#    --status=open implied by default in most bd builds; pass
#    explicitly for portability. --json keeps description parsing
#    sane (newlines / quotes survive jq's -r).
beads=$(bd list --label=upstream:watch --status=open --json 2>/dev/null) || beads='[]'

count=$(printf '%s' "$beads" | jq 'length' 2>/dev/null || echo 0)
if [ "$count" = "0" ]; then
  echo "No open upstream:watch beads — nothing to sweep."
  exit 0
fi

echo "## /check-upstream-prs"
echo ""
echo "Sweeping $count open upstream:watch bead(s)."
echo ""

merged_ids=""
closed_ids=""
open_ids=""
skipped_ids=""

# 2. Iterate. id<TAB>description per line; description is the raw
#    bead text — we grep for the first PR URL.
while IFS=$'\t' read -r id desc; do
  [ -z "$id" ] && continue

  url=$(printf '%s' "$desc" | grep -oE 'https://github\.com/[^/[:space:]]+/[^/[:space:]]+/pull/[0-9]+' | head -1)
  if [ -z "$url" ]; then
    echo "- $id: SKIP — no PR URL parseable from description"
    skipped_ids="$skipped_ids $id"
    continue
  fi

  pr_json=$(gh pr view "$url" --json state,mergedAt 2>/dev/null) || pr_json=""
  if [ -z "$pr_json" ]; then
    echo "- $id: SKIP — gh query failed for $url"
    skipped_ids="$skipped_ids $id"
    continue
  fi

  state=$(printf '%s' "$pr_json" | jq -r '.state // "UNKNOWN"' 2>/dev/null || echo UNKNOWN)

  case "$state" in
    MERGED)
      echo "- $id: MERGED — closing ($url)"
      bd close "$id" --reason="upstream merged: $url" >/dev/null 2>&1 \
        && merged_ids="$merged_ids $id" \
        || echo "  (bd close failed for $id — investigate)"
      ;;
    CLOSED)
      echo "- $id: CLOSED (rejected) — surfacing for review ($url)"
      closed_ids="$closed_ids $id"
      ;;
    OPEN)
      open_ids="$open_ids $id"
      ;;
    *)
      echo "- $id: SKIP — unexpected state '$state' for $url"
      skipped_ids="$skipped_ids $id"
      ;;
  esac
done < <(printf '%s' "$beads" | jq -r '.[] | [.id, .description] | @tsv')

# 3. Summary block — terse counts the user can scan.
echo ""
echo "### Summary"
echo ""
merged_count=$(printf '%s' "$merged_ids" | wc -w | tr -d ' ')
closed_count=$(printf '%s' "$closed_ids" | wc -w | tr -d ' ')
open_count=$(printf '%s' "$open_ids" | wc -w | tr -d ' ')
skipped_count=$(printf '%s' "$skipped_ids" | wc -w | tr -d ' ')
echo "- MERGED + auto-closed: $merged_count"
echo "- CLOSED (rejected, needs user review): $closed_count"
echo "- OPEN (still in flight, no-op): $open_count"
echo "- SKIPPED (unparseable URL or gh failure): $skipped_count"

# 4. CLOSED block — promote for visibility. The user must manually
#    decide whether to close, reopen the local symptom, or file a
#    follow-up.
if [ "$closed_count" -gt 0 ]; then
  echo ""
  echo "### Rejected upstream PRs"
  echo ""
  for id in $closed_ids; do
    echo "- $id: review and decide — \`bd close $id\` or \`bd update $id ...\`."
  done
fi

exit 0
```

## Related

- Watch-bead spawn convention:
  [`skills/upstream-a-bead/SKILL.md`](../skills/upstream-a-bead/SKILL.md)
  § M7.
- Opposite-direction sibling:
  [`commands/check-loom-upstream.md`](check-loom-upstream.md)
  (project beads ↔ loom closes).
- Pruning the upstream clone cache: `/loom-upstream-gc`
  (loom-k2g.4, follow-on bead).
- Closes: loom-k2g.3.
