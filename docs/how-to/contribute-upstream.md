# Contribute a fix upstream

To drive a fix into someone else's repo — an SDK, a sibling plugin,
Claude Code itself — using loom's two-bead lifecycle and the
`upstream-a-bead` recipe, follow these steps.

## When to use this guide

- The symptom reproduces in a loom-managed project but the FIX
  cannot land locally. It belongs in someone else's repo and has to
  come back via a version bump or vendored update.
- A loom-side bead surfaced the issue and you have a clear contract
  (symptom + diagnosis + proposed fix shape).
- The upstream accepts external contributions. (If not, see
  [Skip when](#skip-when) below.)

For the opposite direction — labelling a *downstream* bead that
exists only because of a *loom-side* bug — see
[upstream:loom label](../reference/upstream-loom-label.md).

## Skip when

- The fix CAN land locally (a workaround, a pin, a hook bypass) —
  file the local fix as a bug/feature bead and use the matching
  recipe.
- The bug is in a loom-managed sibling project you own — use the
  normal `bugfix-a-bead` / `feature-a-bead` recipe with a worktree
  in that sibling project.
- The upstream owner has explicitly declined the change category, or
  the bug is by-design — file as a loom-98x "closed as
  upstream-pending" outcome (drawer-only; no issue; no watch-bead).
  The `upstream-a-bead` recipe accommodates this at M1.

## Precondition

- `gh auth status` passes. The M2 canonical-owner check and the M7
  filing both depend on it.
- You have a loom-side work-bead labelled `upstream:work` whose
  title follows the convention `upstream <owner>/<repo>: <symptom>`.
- You're inside the loom repo (or any loom-managed project) so the
  recipe's slash commands resolve.

## Worked example: loom-7bn (beadpowers splitting-heuristic)

The walkthrough below uses a representative work-bead. Substitute
your own bead-id and upstream `<owner>/<repo>` throughout. The
canary trial bead (loom-k2g.7) will later refine this guide with
real evidence captured from the first run.

### Frame the bead

The loom-side bead carries the upstream framing in its title and
labels:

```bash
bd create "upstream obra/beadpowers: splitting heuristic missing from create-beads" \
  --type feature \
  --label upstream:work \
  --priority p2
```

The title's `upstream <owner>/<repo>:` prefix is what the
`/working-a-bead` router pattern-matches when picking the recipe.

### Start the recipe

```text
/upstream-a-bead loom-<id>
```

Or, after `session-startup` surfaces the bead, let the router pick:

```text
/working-a-bead loom-<id>
```

The recipe runs phase A (search the upstream family in MemPalace,
claim, worktree) via `bead-lifecycle-shell`, then enters the
variable middle.

### M1 — lock the contract + lane (central)

Central drives the design dialogue with you. Three components must
be explicit before any worker is dispatched:

| Component | What to write |
|---|---|
| Symptom | What the user observed, verbatim from the loom-side bead. |
| Diagnosis | The upstream component + line / function / contract responsible. |
| Proposed fix | For `--issue+pr`: the shape of the PR change. For `--issue-only`: the shape of the change the upstream owner SHOULD make. |

Then pick exactly one lane:

| Lane | Use when |
|---|---|
| `--issue+pr` | Fix is small, well-scoped, upstream accepts external PRs, you have bandwidth to maintain the PR across review cycles. |
| `--issue-only` | Fix is large, ambiguous, requires upstream-owner-only context, or upstream prefers issue-first discussion. Skips M3 (RED) and M4 (GREEN). |
| intractable / upstream-pending | Recipe terminates after M1 with a drawer-only outcome. No issue, no PR, no watch-bead. |

When in doubt, default to `--issue-only` and follow up with a
separate work-bead to upgrade to a PR once the conversation
converges.

### M2 — clone into ~/.loom/upstream/ (worker)

A single worker is dispatched (via `Agent` + `isolation: "worktree"`)
to own M2 through M5. The worker writes stage `cloning` and runs
five checks:

1. **Existence check.** If `~/.loom/upstream/<owner>/<repo>/`
   already exists from a prior contribution, skip the clone.
   Otherwise: `git clone https://github.com/<owner>/<repo>.git
   ~/.loom/upstream/<owner>/<repo>/`.
2. **Canonical-owner check.** `gh repo view <owner>/<repo> --json
   owner,parent` — confirms the owner matches the brief and the
   target is not a fork. (Catches gastownhall-vs-steveyegge-style
   confusion per the loom-45i triad.)
3. **Dirty-state refusal.** `git status --porcelain` and `git log
   --branches --not --remotes --oneline` inside the clone. If
   either is non-empty (uncommitted changes or unpushed commits
   from a prior contribution), the worker stops and surfaces the
   conflict. Resolve via [`/loom-upstream-gc`](../reference/slash-commands/all-commands.md)
   or direct cleanup; the worker never auto-stashes or
   auto-discards.
4. **Fork-detect (`--issue+pr` only).** Check whether you have a
   fork. If absent: `gh repo fork <owner>/<repo> --remote=false`
   (the recipe adds the fork as a `fork` remote explicitly).
5. **`gh auth status`.** Re-confirm at M2 so an auth failure does
   not surface at M7 after the M3-M5 work is already done.

The `--issue-only` lane skips step 4 and skips ahead to M5 after
step 3. Clone hygiene still matters.

### M3 — RED test (worker, --issue+pr only)

The worker branches from upstream's default (`main` or `master`):

```bash
cd ~/.loom/upstream/<owner>/<repo>
git checkout -b loom-<bead-id>
```

The branch name carries your loom bead-id for lineage; M5's PR
title will rephrase it for the upstream audience.

The worker writes a failing test under upstream's test layout,
running with upstream's native test command (read upstream's
CONTRIBUTING.md to discover it: `npm test`, `pytest`, `go test`,
`cargo test`, `make test`, etc.). Loom does NOT impose a test
framework on the upstream.

The RED test must fail with the SYMPTOM from M1, not a setup error.
The worker captures the failure output verbatim and commits:

```bash
git commit -m "test: reproduce <symptom> (loom <bead-id>)"
```

The RED commit MUST precede the GREEN commit in upstream's git log
— this is the auditable test-first lineage the upstream owner
sees in PR review.

### M4 — GREEN fix (worker, --issue+pr only)

The worker adds the smallest change that makes the M3 test pass.
Scope is explicitly capped to what M3 exercises — the upstream
owner's review will be much more receptive to a minimal diff than
to a "while I was here" expansion.

Required before commit:

- Re-run the full upstream test suite (not just the new test) and
  confirm zero regressions.
- Read upstream's CONTRIBUTING.md and adapt commit format
  (conventional commits, sign-off trailers, DCO, etc.) before
  committing. Cheaper to do once than to fix in review feedback.

```bash
git commit -m "fix: <one-line> (loom <bead-id>)"
```

If the GREEN attempt reveals the fix is non-trivial (touches more
files than M1 anticipated, requires a design choice the upstream's
maintainers should make), the worker stops and surfaces to central
— the lane likely re-decides as `--issue-only`.

### M5 — draft the issue + PR bodies (worker)

The worker writes stage `draft` and produces:

- `/tmp/issue-<bead-id>.md` — symptom + reproduction + expected vs
  actual + proposed direction + context.
- `/tmp/pr-<bead-id>.md` (`--issue+pr` only) — summary + issue link
  placeholder (`<ISSUE-URL>`) + RED→GREEN evidence + adapted-to-
  CONTRIBUTING notes.

Before writing either file, the worker scrubs:

- Loom-managed project names that aren't relevant to the upstream
  (replace with generic terms like "a project using <upstream>").
- Internal user IDs, internal URLs, internal hostnames.

Bead IDs are FINE to include — they're meaningless to upstream but
invaluable for the watch-bead's future lineage. Loom-managed
project names are NOT.

The worker returns the file paths to central in its summary.

### M6 — user review gate (central)

Central reads the drafted files and quotes them inline so you can
review without leaving the chat. You'll be asked:

- "Issue body: any privacy redactions to add? Any rewording?"
- (`--issue+pr` only) "PR body: same questions."
- "Approve filing?"

**The gate is mandatory regardless of workflow mode.** Privacy
redaction is the gate's load-bearing job; silently filing on
assumed-approval defeats its purpose.

If you request `≤3-line` polish, central edits the `/tmp/` files in
place and re-asks for approval. If you request substantial changes,
a fresh worker is briefed with the corrected M3-M5 scope. If your
feedback suggests the M1 contract was wrong, the recipe re-enters
M1 — don't paper over a contract miss with body edits.

### M7 — auto-file + spawn watch-bead (central)

On your explicit approval, central runs:

For `--issue-only`:

```bash
gh issue create --repo <owner>/<repo> \
  --title "<title>" \
  --body-file /tmp/issue-<bead-id>.md
```

For `--issue+pr`, the sequence is:

```bash
# 1. File the issue first, capture the URL
gh issue create --repo <owner>/<repo> \
  --title "<title>" \
  --body-file /tmp/issue-<bead-id>.md

# 2. Edit /tmp/pr-<bead-id>.md to substitute <ISSUE-URL>

# 3. Push the upstream branch to your fork
git -C ~/.loom/upstream/<owner>/<repo>/ push fork loom-<bead-id>

# 4. File the PR against the upstream's main
gh pr create --repo <owner>/<repo> \
  --title "<title>" \
  --body-file /tmp/pr-<bead-id>.md \
  --base main \
  --head <user-handle>:loom-<bead-id>
```

Then central spawns the watch-bead:

```bash
bd create "watch upstream <owner>/<repo>#<N>: <one-line>" \
  --type task --priority p3 \
  --label upstream:watch

bd dep add <watch-bead-id> --blocked-by <work-bead-id>
```

The dependency edge keeps the watch-bead out of `bd ready` until
the work-bead closes.

### Phase B — verify the loom side AND the upstream side

Verify the loom-side branch first (`git diff --stat` on
`frank/<bead-id>` matches scope — typically just the closing
drawer). Then extend with the upstream verification:

```bash
# Issue is open
gh issue view <issue-URL> --json state,number

# PR exists and points at your fork (--issue+pr only)
gh pr view <pr-URL> --json state,headRefName

# Watch-bead exists with correct PR URL
bd list --label=upstream:watch

# Dependency edge resolves
bd dep list <watch-bead-id>

# RED before GREEN in upstream's log (--issue+pr only)
git -C ~/.loom/upstream/<owner>/<repo>/ log --oneline loom-<bead-id>
```

### Phase C — commit on the loom-side branch

```bash
git commit -m "upstream <owner>/<repo>#<N>: <symptom>

Lane: --issue+pr
PR: <pr-URL>
Issue: <issue-URL>
Watch-bead: <watch-bead-id>
Drawer: drawer_loom_decisions_<...>

Co-Authored-By: ..."
```

Then run `superpowers:finishing-a-development-branch`. Upstream-work
beads typically pick **merge to main** since the loom-side artifact
is just the drawer + lineage commit.

### Phase D — close + capture

Standard close: `bd preflight` → `bd close <id>` → `bd dolt push`
(if a remote is configured) → `git push`.

The closing decision drawer must name:

- WHAT LANDED — PR URL + issue URL + work-bead ID + watch-bead ID
  (all four lines explicit).
- Privacy redactions made — verbatim list, for the next
  contributor to the same upstream.
- Fork-detection result (`--issue+pr` only) — whether you had a
  fork, whether one was auto-created, the fork's remote name.
- CONTRIBUTING.md adaptations — commit format, test command,
  sign-off requirements observed.

KG triples to add via `mempalace_kg_add` (load-bearing for future
M1 sibling-contribution hunts):

- `<work-bead-id> filed_upstream_at <PR-URL>` (or `<issue-URL>` for
  `--issue-only`)
- `<work-bead-id> spawned_watch_bead <watch-bead-id>`
- `<owner>/<repo>#<N> contributed_by loom`

## After the work-bead closes

The watch-bead is now in `bd ready`. Run
[`/check-upstream-prs`](../reference/slash-commands/all-commands.md)
periodically (or via the wake-up scheduler) to sweep all open
`upstream:watch` beads:

- `state=MERGED` → watch-bead auto-closes; the upstream fix is
  live and you can bump the version in any loom-managed project
  that consumes it.
- `state=CLOSED` (rejected) → surfaced for your review; you decide
  whether to close the watch-bead, file a follow-up upstream
  bead, or accept the rejection as final.
- `state=OPEN` → no-op; the sweep waits.

To prune the `~/.loom/upstream/` cache once the watch-bead closes,
run [`/loom-upstream-gc`](../reference/slash-commands/all-commands.md).
It refuses removal if any `upstream:watch` bead still references
the clone OR if the clone has uncommitted changes.

## Outcome

You have an upstream issue (and optionally a PR) filed with
privacy-redacted bodies. The work-bead is closed; the watch-bead
waits for the upstream merge. The closing drawer captures
fork-detection and CONTRIBUTING-format findings that the next
contribution to the same upstream will reuse via the M1
sibling-contribution hunt.

## Related

- [upstream-a-bead recipe reference](../reference/upstream-a-bead.md)
  — full skill text and lane decision matrix.
- [upstream:loom label](../reference/upstream-loom-label.md) — the
  opposite-direction label, for downstream beads that exist only
  because of a *loom-side* bug.
- [Recipe family](../explanation/recipe-family.md) — why upstream
  is the 7th sibling activity recipe.
- [Finish a bead](./finish-a-bead.md) — the standard phase-D
  closeout the upstream recipe extends.
