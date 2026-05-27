---
description: "Interactive prune of stale `~/.loom/upstream/<owner>/<repo>/` clones. Refuses removal if any open `upstream:watch` bead references the clone OR if the clone has uncommitted changes. Asks user per-dir before destructive ops. Never auto-destructive."
disable-model-invocation: true
---

Interactive garbage-collection sweep for the central upstream clone
cache (`~/.loom/upstream/<owner>/<repo>/`). The cache is shared
across loom-managed projects so we don't re-clone a popular upstream
N times; over time some entries become stale (their watch-beads
closed, the contribution merged or rejected). This command surfaces
each candidate clone, refuses the unsafe ones, and asks the user
per-clone before any `rm -rf`.

**Never auto-destructive.** Two structural refusals fire BEFORE the
prompt, and the prompt itself requires explicit user assent.

Design source: drawer `drawer_loom_decisions_a6e64f9cfb21a9d16fc47604`
(loom/decisions wing, 2026-05-27 — "Manual prune via
`/loom-upstream-gc` — interactive, asks per clone; refuses removal
if open `upstream:watch` bead points at it OR if dir has uncommitted
changes."). Tracks loom-k2g.4.

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
WATCH_REFS=$(bd list --label=upstream:watch --status=open --json 2>/dev/null \
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

## Step 3 — per-clone gating + user prompt

For each clone, run both safety gates BEFORE asking the user. If
either gate fires, REFUSE this clone (don't prompt) and continue to
the next.

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

  # Both gates passed — ask user before destructive op.
  echo "  Both safety gates passed (clean tree + no open watch-bead reference)."
done
```

After both gates pass for a clone, surface the candidate to the
user and prompt for assent. Use `AskUserQuestion` for the prompt
(matches the interactive house style — see also `/audit-project`'s
item gates). Prompt shape:

> "Prune clone `<owner>/<repo>` at `<full-path>`? (y/N)"

Options: `Yes — rm -rf this clone` / `No — keep it`. Default to
"No". Only on explicit "Yes" do you proceed.

On user assent:
```bash
rm -rf "$clone"
echo "  PRUNED: $clone"
# Clean up an empty owner-dir to avoid leaving stub directories.
owner_dir="$(dirname "$clone")"
if [ -d "$owner_dir" ] && [ -z "$(ls -A "$owner_dir")" ]; then
  rmdir "$owner_dir"
  echo "  Removed empty owner dir: $owner_dir"
fi
```

On user decline (or any non-Yes answer), skip and move on. Never
re-prompt — one prompt per clone, decline is final for this run.

## Step 4 — summary

After iterating, report counts:

```bash
echo "----"
echo "Summary: $pruned_count clone(s) pruned, $refused_count refused, $kept_count kept."
```

(Track counts in the loop with `pruned_count=$((pruned_count + 1))`
on the prune branch, etc. The exact accounting is implementation
detail — the contract is "user sees a final tally".)

## Contract — never auto-destructive

This command **NEVER** removes a clone without:
1. Both safety gates passing (clean tree AND no open watch-bead
   reference), AND
2. The user explicitly answering "Yes" to the per-clone prompt.

A gate failure short-circuits to "REFUSE" with no prompt. A user
decline short-circuits to "skip" with no removal. There is no
`--all` / `--force` / `--yes` flag — manual prune means per-clone
manual.

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
