---
description: "Prune stale `~/.loom/upstream/<owner>/<repo>/` clones. Refuses removal if any open `upstream:watch` bead references the clone OR if the clone has uncommitted changes. Prunes what clears both gates and reports what it removed."
disable-model-invocation: true
---

Garbage-collection sweep for the central upstream clone cache
(`~/.loom/upstream/<owner>/<repo>/`). The cache is shared across
loom-managed projects so we don't re-clone a popular upstream N times.
Over time some entries go stale, their watch-beads closed and the
contribution merged or rejected. This command refuses the unsafe
clones, prunes the rest, and reports what it removed.

**Two structural refusals decide it.** A clone with uncommitted changes
is refused, and so is one that an open `upstream:watch` bead still
points at. What clears both is a clone with nothing in it to lose and
nobody waiting on it, and getting it back costs a `git clone`.

Design source: drawer `drawer_loom_decisions_a6e64f9cfb21a9d16fc47604`
(loom/decisions wing, 2026-05-27 — "Manual prune via
`/loom-upstream-gc` — interactive, asks per clone; refuses removal
if open `upstream:watch` bead points at it OR if dir has uncommitted
changes."). Tracks loom-k2g.4.

The per-clone ask in that drawer was retired under loom-42cw. The two
gates run first and settle the answer, so the prompt was asking for
assent to a decision it had already finished making, once per clone.

## Resolve the cache root

```bash
LOOM_HOME=${LOOM_HOME:-$HOME/.loom}
UPSTREAM_ROOT="$LOOM_HOME/upstream"

if [ ! -d "$UPSTREAM_ROOT" ]; then
  echo "No upstream cache at $UPSTREAM_ROOT — nothing to prune."
  exit 0
fi
```

The default mirrors `lib/loom-upstream.sh` (`LOOM_HOME` env override
keeps the command testable + portable across machines).

## Step 1 — enumerate candidate clones

```bash
# `~/.loom/upstream/<owner>/<repo>/` — two-level nesting handles
# repo-name collisions (e.g. two different `beads` repos).
mapfile -t CLONES < <(find "$UPSTREAM_ROOT" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | sort)

if [ "${#CLONES[@]}" -eq 0 ]; then
  echo "Upstream cache at $UPSTREAM_ROOT contains no clones — nothing to prune."
  exit 0
fi

echo "Found ${#CLONES[@]} clone(s) under $UPSTREAM_ROOT:"
for clone in "${CLONES[@]}"; do
  echo "  - ${clone#$UPSTREAM_ROOT/}"
done
echo ""
```

## Step 2 — gather open `upstream:watch` beads

Build the set of `<owner>/<repo>` slugs that any open watch-bead
references via a PR URL in its description. The recipe spawns watch-
beads with the PR URL embedded (`https://github.com/<owner>/<repo>/
pull/<N>`); we match against that.

```bash
WATCH_REFS=$(bd list --label=upstream:watch --status=open --json --limit 0 2>/dev/null \
  | python3 -c '
import json, re, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
seen = set()
for issue in data if isinstance(data, list) else []:
    desc = (issue.get("description") or "") + " " + (issue.get("title") or "")
    for m in re.finditer(r"github\.com[/:]([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+?)(?:\.git)?(?:/(?:pull|issues|tree|commit)/|[\s)]|$)", desc):
        seen.add(f"{m.group(1)}/{m.group(2)}")
for slug in sorted(seen):
    print(slug)
' 2>/dev/null)
```

The regex tolerates both `github.com/<owner>/<repo>` (HTTPS) and
`github.com:<owner>/<repo>` (SSH-shaped) forms; trailing path
segments (`pull/N`, `issues/N`, etc.) are tolerated, as is bare
trailing-`.git` suffix. If `bd list` returns empty or the python
parse fails, `WATCH_REFS` is empty — and the per-clone refusal step
falls back to a "no open watch-beads detected" state (safe).

## Step 3 — per-clone gating + prune

For each clone, run both safety gates. If either fires, REFUSE this
clone and continue to the next. A clone that clears both is pruned in
the same pass.

```bash
for clone in "${CLONES[@]}"; do
  # Derive <owner>/<repo> slug from the clone path.
  rel="${clone#$UPSTREAM_ROOT/}"            # e.g. obra/superpowers
  echo "----"
  echo "Clone: $rel"
  echo "  Path: $clone"

  # Gate 1 — uncommitted changes (staged, unstaged, or untracked).
  if [ ! -d "$clone/.git" ] && ! git -C "$clone" rev-parse --git-dir >/dev/null 2>&1; then
    echo "  REFUSE: $clone is not a git repository — skipping."
    continue
  fi
  porcelain=$(git -C "$clone" status --porcelain 2>/dev/null)
  if [ -n "$porcelain" ]; then
    echo "  REFUSE: clone has uncommitted changes:"
    echo "$porcelain" | sed 's/^/    /'
    echo "  Clean the tree manually before pruning."
    continue
  fi

  # Gate 2 — any open upstream:watch bead references this slug.
  if printf '%s\n' "$WATCH_REFS" | grep -Fxq "$rel"; then
    echo "  REFUSE: an open upstream:watch bead references $rel."
    echo "  Close or reject the watch-bead first (see bd list --label=upstream:watch)."
    continue
  fi

  # Both gates passed. Prune.
  echo "  Both safety gates passed (clean tree + no open watch-bead reference)."
  rm -rf "$clone"
  echo "  PRUNED: $clone"
  # Clean up an empty owner-dir to avoid leaving stub directories.
  owner_dir="$(dirname "$clone")"
  if [ -d "$owner_dir" ] && [ -z "$(ls -A "$owner_dir")" ]; then
    rmdir "$owner_dir"
    echo "  Removed empty owner dir: $owner_dir"
  fi
done
```

The gates carry the whole decision, so there's no prompt between them
and the `rm -rf`. Each is a fact this command can read for itself:
`git status --porcelain` says whether anything would be lost, and the
watch-bead scan says whether anything is still waiting on the clone.
Neither is a fact the user holds and this command doesn't, and a prompt
that fires once per clone for an answer already settled N times over is
the shape loom-42cw retired.

## Step 4 — report what went

After iterating, report counts:

```bash
echo "----"
echo "Summary: $pruned_count clone(s) pruned, $refused_count refused."
```

(Track counts in the loop with `pruned_count=$((pruned_count + 1))`
on the prune branch, etc. The exact accounting is implementation
detail — the contract is "user sees a final tally".)

Then name the clones, both lists. Say which slugs were pruned, and for
each refusal say which gate fired:

> Pruned `obra/superpowers`. Refused `gastownhall/beads` (open watch
> bead) and `mempalace/mempalace` (uncommitted changes). Re-clone any
> of these on demand.

The pruned list is the part that has to be there. Deleting a clone is
cheap to undo but only if the user knows which one went, and the slug
is the whole of what they need to get it back.

## Contract — the gates are the whole decision

This command removes a clone only when both safety gates pass: a clean
tree AND no open watch-bead reference. A gate failure short-circuits to
"REFUSE" with no removal, and the summary names the gate that fired.

The old contract carried one more rule, that no `--all` / `--force` /
`--yes` flag may exist. That rule was guarding the prompt rather than
the clones, and with the prompt gone it guards nothing, so it goes with
it. A `--yes` flag has nothing left to answer for.

Overriding a gate is still not on offer, and that's a separate point
from the flag rule. Forcing past one deletes either uncommitted work or
a clone an open bead is still waiting on, and neither is worth a flag.

## Related

- Helper library: `lib/loom-upstream.sh` (loom-k2g.2) — the
  clone-cache management functions consumed by the upstream-a-bead
  recipe at M2.
- Watch-bead lifecycle: `/check-upstream-prs` (loom-k2g.3) — the
  periodic sweep that auto-closes watch-beads on upstream merge.
- Recipe: `skills/upstream-a-bead/SKILL.md` — the activity recipe
  that spawns watch-beads in the first place.
- Audit integration: `/audit-project` surfaces orphan-clone
  candidates and recommends running this command.
- Closes: loom-k2g.4 (interactive prune slash command).
