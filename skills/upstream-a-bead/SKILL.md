---
name: upstream-a-bead
description: Activity recipe for working an upstream-contribution-shaped beads issue. Owns the upstream-specific variable middle — lock contract + lane → clone upstream into ~/.loom/upstream/ → RED test in the upstream tree → minimal GREEN fix → draft issue + PR with privacy redaction → user review gate → auto-file via gh + spawn watch-bead. Defers to the bead-lifecycle-shell skill for claim/isolate/verify/close/capture. Two lanes: `--issue-only` (codifies the loom-45i triad filing pattern; skips M3-M5) and `--issue+pr` (full clone + RED/GREEN + PR). Triggers on phrases like "let's work on <upstream-work-bead-id>", "file upstream <owner>/<repo>: ...", "drive <bead> upstream", or right after the session-startup or /working-a-bead router picks an `upstream:work`-labeled bead.
---

# Upstream-a-Bead — Variable Middle for Upstream-Contribution-Shaped Beads

This skill owns ONLY the upstream-specific middle of the bead lifecycle.
The shared lifecycle scaffolding — MemPalace search, claim + worktree,
verification, commit, finish-branch, close + capture — lives in the
`bead-lifecycle-shell` skill. This recipe cites those phases by letter
and supplies the variable middle that runs between phase A (pre-middle)
and phase B (verification).

The conceptual shift from sibling recipes is that the *deliverable lives
outside loom*. Loom-side phase C still commits a drawer + branch on
`frank/<bead-id>`, but the value the user cares about is an upstream
issue (and optionally a PR with RED/GREEN evidence) filed against
someone else's repo. The work-bead closes FAST on PR file; a paired
watch-bead is auto-spawned at M7 and closes SLOW when
`/check-upstream-prs` detects the upstream merge. Get the two-bead
lifecycle wrong and either (a) the work-bead sits in_progress for
weeks waiting on upstream, or (b) the upstream-merge moment is never
captured because nothing was watching.

Invocation: explicit only — either directly (`/upstream-a-bead <bead-id>`)
or via the `/working-a-bead` router that selects an activity recipe by
bead shape (`upstream:work` label or `upstream <owner>/<repo>:` title
prefix). The Skill tool may surface this recipe via auto-discovery
when a message strongly matches the trigger phrases above; if that
happens at the wrong moment (e.g., the issue can be fixed inside the
loom-managed project), decline and switch to the right recipe.

## When to use

Right after `session-startup` (or the `/working-a-bead` router) picks an
`upstream:work`-labeled bead, OR whenever the right fix for a symptom
surfaced in a loom-managed project lives in someone else's repo (a
sibling plugin, a dependency, Claude Code itself). A bead is
upstream-shaped when the symptom reproduces and is well-characterized
locally but the FIX cannot land in the local repo — it has to land
upstream and then be picked up via a version bump or vendored update.

## Skip when

- The fix CAN land locally (a workaround, a pin, a hook bypass) — file
  the local fix as a bug/feature bead and use the matching recipe. The
  upstream contribution is a separate, later bead.
- The bug is in a loom-managed sibling project owned by the same user
  — that's intra-org work; use the normal bugfix/feature recipe with a
  worktree in the sibling project.
- The symptom is reproduced but the upstream fix is intractable (the
  upstream owner has explicitly declined the change category, the bug
  is by-design, etc.) — file as the loom-98x "closed as upstream-
  pending" pattern: drawer captures the analysis, no issue filed, no
  watch-bead spawned. The recipe accommodates this as an M1 choice
  ("intractable" lane), not a separate recipe.
- Mid-task interruption. This recipe is for new upstream-work starts,
  not for context recovery within an in-flight upstream bead.

## Workflow modes (v1.5)

This recipe inherits mode behavior from `bead-lifecycle-shell` (which
checks `<project>/.claude/workflow.json` `.mode` at the start of phase
A). Activity-specific behavior in each mode:

- **full** — run every step of the variable middle as written. Lock
  the lane at M1, clone+RED+GREEN for `--issue+pr`, draft both
  artifacts at M5, user review gate mandatory at M6, auto-file +
  watch-bead at M7.
- **light** — the M5 draft may collapse to a single combined
  issue+PR-body file when the issue body and PR body would be
  near-duplicates; the M6 review gate stays mandatory regardless
  (privacy redaction is the gate's load-bearing job). The `--issue-
  only` lane's M1+M5+M6+M7 sub-sequence is already light by
  construction.
- **off** — the shell refuses; this recipe never runs.

## Stage updates

Phase boundary stages are written by `bead-lifecycle-shell`. This
recipe adds activity-specific intermediate stages between phase A
and phase B:

| Step boundary | Stage to write |
|---|---|
| Entering step M1 (lock contract + lane) | `designing` |
| Entering step M2 (clone upstream into cache) | `cloning` |
| Entering step M3 (RED — pin upstream symptom) | `red` |
| Entering step M4 (GREEN — minimal upstream fix) | `green` |
| Entering step M5 (draft issue + PR bodies) | `draft` |
| Entering step M6 (user review gate) | `review` |
| Entering step M7 (auto-file + spawn watch-bead) | `file` |

Write each via `~/.claude/scripts/workflow-state set stage=<stage>` at
the moment the step starts. The status line surfaces these so future
cold-start sessions can see exactly where work paused. Upstream beads
frequently pause at M6 (waiting for the user to review the drafted
artifacts) — that stage marker is the most load-bearing of the seven.

## The Sequence

### Phase A — pre-middle (delegate to shell)

Follow `bead-lifecycle-shell` phase A:
- **A1.** MemPalace search for the upstream family (sets stage
  `research`). For upstream beads the search has THREE targets:
  1. **Sibling-contribution hunt** — `mempalace_search "upstream
     <owner>/<repo>"` plus `mempalace_kg_query("<owner>/<repo>")` to
     find prior contributions to the same upstream. Privacy
     redactions, canonical-owner findings, and fork-detection results
     from prior work-beads are reusable.
  2. **Symptom-family hunt** — search for prior loom-side beads that
     hit the same upstream surface. If a loom-98x-style "closed as
     upstream-pending" drawer exists for this symptom, the analysis
     may already be done; this bead's job is just the filing.
  3. **CONTRIBUTING.md prior art** — if a prior contribution to this
     upstream exists, its drawer captures the upstream's PR-shape
     conventions (commit format, test command, sign-off requirements).
     Reuse that — the loom-x2q sibling-pattern-grep discipline
     applies upstream-side too.
- **A2.** `bd update <id> --claim`, then worktree on `frank/<bead>`
  from `main`. The loom-side worktree carries the drawer + lineage
  commit; the upstream clone lives separately under
  `~/.loom/upstream/<owner>/<repo>/` (shared central cache, NOT a
  loom-managed worktree).

If A1 surfaces a sibling contribution to the same upstream, restate
the M1 lane decision in light of that lineage BEFORE the brainstorm
goes deep. Diverging from the upstream's established PR convention
without naming the divergence is the most common way upstream
contributions get bounced.

### Variable middle — M1 → M7 (recipe owns)

The variable middle is **worker territory**, per `bead-lifecycle-shell
§ Dispatch discipline — central agent briefs a worker`, BUT with two
central-owned bookends: M1 (lane decision is design-dialogue-shaped)
and M6+M7 (review gate + filing are user-interaction-shaped). Central
designs the contract and picks the lane at M1, then dispatches ONE
worker via `Agent` + `isolation: "worktree"` to own M2-M5 in a single
dispatch. The worker's worktree is the loom-side worktree on
`frank/<bead-id>`; the worker also operates inside the upstream clone
at `~/.loom/upstream/<owner>/<repo>/` for M3-M4. Central retakes
control at M6 to drive the user review gate, then runs the M7 `gh`
calls and spawns the watch-bead.

After the worker returns from M5, apply the re-dispatch decision rule
from the shell: **clean** → advance to M6; **≤3-line polish to a
draft** → central edits in place; **substantive rework needed** →
brief a fresh worker with the corrected M3-M5 scope.

The worker brief follows the template in the shell. Cite the M-steps
below as scope items and instruct the worker to write the stage
markers in the table above at each M-boundary it crosses. Lane is
already locked at M1 — the brief carries the lane verbatim and the
worker does not re-decide it.

#### M1. Lock contract + pick lane (central — pre-dispatch)

The contract is locked BEFORE the worker is dispatched. This step is
user-interaction-shaped (framing the upstream symptom, picking the
lane, optionally consulting prior contributions to the same upstream)
and stays with central. Upstream contributions without an upfront
contract become unfocused issue bodies that the upstream owner can't
triage — the contract must be explicit before the worker is briefed.

The contract has three components:
- **Symptom** — what the user observed (verbatim from the loom-side
  bead that motivated this upstream bead).
- **Diagnosis** — the upstream component + line/function/contract
  that's responsible.
- **Proposed fix** — for `--issue+pr` lane, the shape of the change
  the PR will land; for `--issue-only` lane, the shape of the change
  the upstream owner SHOULD make (without committing to write it).

**Lane decision.** Pick exactly one:
- **`--issue+pr`** — full clone + RED/GREEN + PR draft. Use when the
  fix is small + well-scoped, the upstream accepts external PRs, and
  the loom side has bandwidth to maintain the PR across review
  cycles.
- **`--issue-only`** — file the issue only (no clone, no PR). Use
  when the fix is large, ambiguous, requires upstream-owner-only
  context, or the upstream's CONTRIBUTING.md prefers issue-first
  discussion. This is the codified loom-45i triad pattern: skips M3
  (RED), M4 (GREEN), and the PR half of M5; runs M2 (clone — still
  needed for canonical-owner check) + M5 (issue draft only) + M6 +
  M7.
- **intractable / upstream-pending** — no issue filed; no PR; no
  watch-bead. Drawer captures the analysis per the loom-98x pattern.
  Recipe terminates after M1 with the drawer-only outcome captured
  at phase D3.

If the lane decision reveals the bead is actually local-fixable (a
workaround exists, the upstream behavior is by-design and the local
side should adapt), pause here and switch recipes BEFORE dispatching.
Mis-typed beads waste the worker's entire dispatch.

When the contract is locked and the lane is picked, set stage
`designing` and write the worker brief. The brief carries: the
locked contract, the lane flag, the upstream `<owner>/<repo>`, the
target `gh repo view`-confirmed canonical owner (or the instruction
to run that check at M2), and the M2-M5 scope items below.

#### M2. Clone upstream into ~/.loom/upstream/ (scope item)

Have the worker write stage `cloning`. The clone location is the
central XDG-style cache at `~/.loom/upstream/<owner>/<repo>/`,
shared across all loom-managed projects — don't re-clone mempalace
five times if five projects hit it.

The worker brief should require:
1. **Existence check.** If `~/.loom/upstream/<owner>/<repo>/` exists,
   skip the `git clone` and proceed to the dirty-state check. If
   absent, `git clone https://github.com/<owner>/<repo>.git
   ~/.loom/upstream/<owner>/<repo>/`.
2. **Canonical-owner check.** Run `gh repo view <owner>/<repo>
   --json owner,parent` and confirm the owner matches the brief's
   `<owner>` (and is not a fork pointing at a different canonical).
   Per loom-45i, this catches gastownhall-vs-steveyegge-style
   confusion before the issue gets filed against the wrong repo.
3. **Dirty-state refusal.** Run `git -C ~/.loom/upstream/<owner>/<repo>/
   status --porcelain` and `git -C ~/.loom/upstream/<owner>/<repo>/
   log --branches --not --remotes --oneline`. If either reports
   non-empty (uncommitted changes OR unpushed commits from a prior
   contribution), STOP and surface to central with the conflict
   details. The user resolves manually via `/loom-upstream-gc` or
   direct cleanup. Do NOT auto-stash or auto-discard.
4. **Fork-detect (issue+pr lane only).** Check whether the user has
   a fork: `gh repo view <user-handle>/<repo> --json parent 2>&1`.
   If absent, `gh repo fork <owner>/<repo> --remote=false` (create
   the fork but don't auto-add a remote — the recipe will add `fork`
   as a remote explicitly to avoid stomping on existing remote
   configuration).
5. **gh auth confirmation.** `gh auth status` must pass; if it
   doesn't, stop-and-report — the M7 filing depends on it and
   discovering the auth failure at M7 wastes the M3-M5 work.

The worker proceeds to M3 only if all five checks pass. The
`--issue-only` lane skips fork-detect (step 4) and skips ahead to
M5 after step 3 (it still does the canonical-owner check + dirty-
state refusal — clone hygiene matters even for issue-only filings).

#### M3. RED — pin the upstream symptom (scope item, --issue+pr only)

Skipped in the `--issue-only` lane.

Have the worker invoke `superpowers:test-driven-development` IN THE
UPSTREAM CLONE, write stage `red`, and author a failing test that
reproduces the symptom from the M1 contract. The test must run via
the upstream's native test command (read upstream's CONTRIBUTING.md
or README to discover it: `npm test`, `pytest`, `go test`, `cargo
test`, `make test`, etc.). Loom does NOT impose a test framework on
the upstream — adopt the upstream's convention verbatim.

The worker should:
- Branch from upstream's default branch (typically `main` or
  `master`): `git -C ~/.loom/upstream/<owner>/<repo>/ checkout -b
  loom-<bead-id>`. The branch name carries the loom bead ID for
  lineage; the PR title from M5 will rephrase it for the upstream
  audience.
- Write the failing test under upstream's test layout (NOT a
  loom-side convention). The test must exercise the contract from
  M1 in a way the upstream owner will recognize as a legitimate bug
  reproduction.
- Run the upstream test suite, confirm the new test FAILS with the
  expected error (the symptom from M1, not a setup error), and
  include the failure output verbatim in the return summary.
- Commit the RED test ON THE UPSTREAM CLONE'S BRANCH with a
  loom-discipline message: `test: reproduce <symptom> (loom <bead-
  id>)`. The RED commit must precede the GREEN commit in upstream's
  git log — this is the auditable evidence that the contract drove
  the fix.

If the test fails for an unexpected reason (the symptom doesn't
reproduce, the upstream test harness is unfamiliar, the contract
from M1 assumed something not true), STOP and surface to central
for re-dispatch with a corrected contract. A mis-RED upstream test
becomes a deceptive GREEN that the upstream owner will (rightly)
reject in review.

#### M4. GREEN — minimal upstream fix (scope item, --issue+pr only)

Skipped in the `--issue-only` lane.

Have the worker write stage `green` and add the smallest change to
the upstream clone that makes the M3 test pass. The brief should
explicitly cap scope to what the M3 test exercises — the upstream
owner's review will be MUCH more receptive to a minimal diff than
to a "while I was here" expansion.

The brief should require the worker to:
- Re-run the full upstream test suite (not just the new test) and
  confirm zero regressions. Capture the pass count in the return
  summary.
- Commit the GREEN fix ON THE UPSTREAM CLONE'S BRANCH with a
  loom-discipline message: `fix: <one-line> (loom <bead-id>)`. The
  RED→GREEN order must be visible in `git -C
  ~/.loom/upstream/<owner>/<repo>/ log --oneline` — the upstream
  owner reading the PR diff should see the test-first lineage.
- Read upstream's CONTRIBUTING.md and adapt commit message format
  (conventional commits, sign-off trailers, DCO, etc.) BEFORE
  committing. Per loom-x2q sibling-pattern-grep, this is cheaper to
  do once than to fix in review feedback.

If the GREEN attempt reveals the fix is non-trivial (touches more
files than the M1 contract anticipated, requires a design choice
upstream's maintainers should make), STOP and surface to central
— the lane should likely re-decide as `--issue-only` and let the
upstream owner choose the implementation.

#### M5. Draft issue + PR bodies (scope item)

Have the worker write stage `draft`. Sub-deliverables differ by lane:

**`--issue-only` lane** — single deliverable: `/tmp/issue-<bead-
id>.md`. Body covers:
- **Symptom** — reproducible description (verbatim from M1 contract).
- **Reproduction** — minimal steps a third party can follow.
- **Expected vs actual** — pinpoints the contract violation.
- **Proposed direction** — the M1 contract's "proposed fix" shape,
  framed as "one approach would be ..." (not as a commitment to
  write the PR).
- **Context** — version info, environment notes, related upstream
  issues if A1's sibling-contribution hunt surfaced any.

**`--issue+pr` lane** — two deliverables: `/tmp/issue-<bead-id>.md`
covers the above PLUS a "(PR #<N> drafted)" note, and `/tmp/pr-
<bead-id>.md` covers:
- **Summary** — what the PR changes, in upstream-audience terms.
- **Issue link** — the issue URL from M7 (worker leaves as
  `<ISSUE-URL>` placeholder; central fills in at M7 between the two
  `gh` calls).
- **RED→GREEN evidence** — the M3 test name + M4 fix description
  + the upstream test command + pass count.
- **Adapted-to-CONTRIBUTING notes** — explicit confirmation that
  the PR follows upstream's commit format / sign-off / etc.

**Privacy redaction (BOTH deliverables).** Before writing either
file, the worker must scrub:
- Loom-managed project names that aren't relevant to the upstream
  (e.g., `liza_base`, `tla_puzzles`, internal-codename projects) —
  replace with generic terms (`a project using <upstream>`).
- Internal user IDs, internal URLs, internal hostnames.
- Bead IDs are FINE to include (they're meaningless to upstream but
  invaluable for the watch-bead's future lineage); loom-managed
  project names are NOT.

This is the load-bearing privacy gate per loom-45i — the M6 review
gate exists primarily to let the user catch redaction misses.

The worker writes the file(s) and surfaces them in the return
summary with absolute paths so central can present them at M6.

#### M6. User review gate (central — post-dispatch)

Central writes stage `review` and presents the drafted artifacts
inline to the user (file contents, not just paths — `Read` the
files and quote them so the user can review without leaving the
chat). Ask the user:
- "Issue body: any privacy redactions to add? Any rewording?"
- "(if `--issue+pr`) PR body: same questions."
- "Approve filing?"

Do NOT proceed to M7 without an explicit "yes" / "approved" / "file
it" from the user. The gate is the user-in-the-loop privacy guard;
silently filing on assumed-approval defeats the gate's purpose.

If the user requests edits, apply them to the `/tmp/` files
(central can Edit them in place — no re-dispatch needed for
≤3-line polish; brief a fresh worker only for substantive rework
per the shell's re-dispatch decision rule). Re-present the edited
versions and re-ask for approval.

If the user requests substantial changes that suggest the M1
contract was wrong, STOP and re-enter M1 with the corrected
framing — don't paper over a contract miss with body edits.

#### M7. Auto-file + spawn watch-bead (central — post-approval)

On user approval, central writes stage `file` and:

**For `--issue-only` lane:**
1. `gh issue create --repo <owner>/<repo> --title "<title>" --body-
   file /tmp/issue-<bead-id>.md` — capture the returned issue URL.
2. Spawn the watch-bead (see below).

**For `--issue+pr` lane:**
1. `gh issue create --repo <owner>/<repo> --title "<title>" --body-
   file /tmp/issue-<bead-id>.md` — capture the returned issue URL.
2. Edit `/tmp/pr-<bead-id>.md` to replace the `<ISSUE-URL>`
   placeholder with the issue URL from step 1.
3. Push the upstream branch to the user's fork: `git -C
   ~/.loom/upstream/<owner>/<repo>/ push fork loom-<bead-id>`.
4. `gh pr create --repo <owner>/<repo> --title "<title>" --body-
   file /tmp/pr-<bead-id>.md --base main --head <user-handle>:loom-
   <bead-id>` — capture the returned PR URL.
5. Spawn the watch-bead (see below).

**Watch-bead spawn.** Auto-file via `bd create`:
- Title: `watch upstream <owner>/<repo>#<N>: <one-line from M1
  contract>`
- Type: `task`
- Priority: `P3`
- Labels: `upstream:watch`
- Description: PR URL + issue URL + work-bead ID + one-line of
  what's being watched for (e.g., "merge or rejection of <PR-
  URL>").

Then `bd dep add <watch-bead-id> --blocked-by <work-bead-id>` so
the watch-bead doesn't surface in `bd ready` until the work-bead
closes.

The work-bead now proceeds to phase B for verification before
closing. The watch-bead waits for `/check-upstream-prs` to detect
the upstream merge (auto-close) or upstream rejection (surface to
user for manual close).

### Phase B — verification (delegate to shell, with upstream extension)

Return to `bead-lifecycle-shell` phase B (sets stage `verify`).
Re-run the loom-side verification from a clean shell, confirm
`git diff --stat` on the `frank/<bead-id>` branch matches scope
(typically just the closing drawer + any lineage-capture files).

**extends phase B with:** cross-cutting upstream verification —
- `gh issue view <issue-URL> --json state,number` confirms the
  issue exists and is OPEN (state=OPEN; closed-immediately would
  signal an auth or repo-routing problem).
- (`--issue+pr` only) `gh pr view <pr-URL> --json
  state,headRefName` confirms the PR exists and points at the
  expected fork branch.
- `bd list --label=upstream:watch` shows the watch-bead exists and
  references the correct PR URL in its description.
- `bd dep list <watch-bead-id>` confirms the dependency edge on the
  work-bead resolves.
- (`--issue+pr` only) `git -C ~/.loom/upstream/<owner>/<repo>/ log
  --oneline loom-<bead-id>` shows RED commit before GREEN commit,
  preserving the auditable lineage.

State results with evidence in user-facing output BEFORE moving to
phase C.

### Phase C — integration (delegate to shell)

Follow `bead-lifecycle-shell` phase C:
- **C1.** Code review (loom-side only — the upstream PR's review
  happens in the upstream's normal review process, tracked via the
  watch-bead).
- **C2.** Commit on the `frank/<bead-id>` branch (sets stage
  `commit`). Subject + body should name the upstream contribution
  (one-line: `upstream <owner>/<repo>#<N>: <symptom>`), the lane
  used (`--issue-only` or `--issue+pr`), the PR URL (if
  `--issue+pr`), the watch-bead ID, and the design source (drawer
  slug). Co-author trailer.
- **C3.** `superpowers:finishing-a-development-branch` — pick from
  the four options. Upstream-work beads typically pick "merge to
  main" since the loom-side artifact is just the drawer + lineage
  commit.

### Phase D — closeout (delegate to shell, with upstream extension)

Follow `bead-lifecycle-shell` phase D:
- **D1.** `bd preflight`.
- **D2.** `bd close <id> --reason="<one-line>"` → `bd dolt push`
  (if remote configured) → `git push` (sets stage `close`).
- **D3.** Drawer + KG triples + diary capture (sets stage
  `wrap-up`).

**extends phase D3 with:** the closing decision drawer must name:
- **WHAT LANDED** — upstream PR URL + issue URL + work-bead ID +
  watch-bead ID, all four lines explicit.
- **Privacy redactions made** — verbatim list of what was scrubbed
  at M5, for reuse pattern by future contributions to the same
  upstream.
- **Fork-detection result** (`--issue+pr` only) — whether the user
  had a fork already, whether one was auto-created, the fork's
  remote name. Cached in watch-bead notes too so future PRs to the
  same upstream skip the M2 fork-detect.
- **CONTRIBUTING.md adaptations** — commit format, test command,
  sign-off requirements observed in this upstream. Future
  contributions to the same upstream consult this section before
  M4.

KG triples are load-bearing for upstream beads — they're what
future M1 sibling-contribution hunts surface:
- `<work-bead-id> filed_upstream_at <PR-URL>` (or `<issue-URL>` for
  `--issue-only`)
- `<work-bead-id> spawned_watch_bead <watch-bead-id>`
- `<owner>/<repo>#<N> contributed_by loom`

## Lane decision (--issue-only vs --issue+pr)

(Already covered at M1, but stated here for parity with sibling
recipes that surface this section explicitly.)

- **`--issue-only`** — codifies the loom-45i triad filing pattern.
  Runs M1 + M2 (canonical-owner + dirty-state only) + M5 (issue
  body only) + M6 + M7 (just `gh issue create`). Use when the fix
  is ambiguous, large, requires upstream context, or upstream
  prefers issue-first discussion.
- **`--issue+pr`** — full clone + RED/GREEN + PR draft + filing.
  Runs all seven steps. Use when the fix is small, well-scoped,
  the upstream accepts external PRs, and the loom side will
  maintain the PR across review cycles.
- **intractable / upstream-pending** — terminates after M1 with a
  drawer-only outcome per the loom-98x precedent. No issue, no PR,
  no watch-bead.

If both `--issue-only` and `--issue+pr` are tempting, default to
`--issue-only` and file a follow-up `upstream:work` bead to
upgrade to a PR if the issue conversation converges on a clear
fix. Easier to upgrade an open issue with a PR than to retract a
premature PR.

## Failure modes (concrete)

- **Skip M1 lane decision (start cloning before lane is locked):**
  the worker dispatches with no `--issue-only` / `--issue+pr` flag
  and either over-builds (full clone + RED for a bug the upstream
  owner should fix) or under-delivers (issue body with no
  reproducer because the worker didn't clone). The lane decision
  must precede the dispatch.
- **Skip M2 canonical-owner check:** the issue gets filed against
  the wrong fork — the canonical upstream owner never sees it.
  Surfaced by the loom-45i triad (gastownhall vs steveyegge for
  `beads`). Always `gh repo view --json owner,parent` before
  filing.
- **Skip M5 privacy redaction:** internal project codenames leak
  into the public issue body. Hard to retract (gh issue edits are
  visible in history); some scrubs (account-handle leaks) cannot
  be undone. The M6 review gate exists primarily to catch this;
  skipping or rushing M6 defeats the privacy guard.
- **Skip M6 review gate (auto-file on worker return):** the worker
  drafts, central files immediately, the user discovers the leak
  post-file. The gate is mandatory regardless of workflow mode.
- **Skip M7 watch-bead spawn:** the work-bead closes, the upstream
  PR sits, no `/check-upstream-prs` sweep ever notices it merged
  (or got rejected). The user loses track of N upstream
  contributions over time. The watch-bead is what
  `/check-upstream-prs` queries; without it, the sweep is blind.
- **Confuse upstream-shaped with local-bug-shaped:** the bead is
  filed as "upstream <owner>/<repo>: X" but the symptom can
  actually be worked around locally (a hook bypass, a pin, a
  version override). Pushing through with this recipe produces a
  drafted upstream contribution for a fix nobody upstream-side
  asked for. Switch to `bugfix-a-bead` (or the matching local
  recipe) when M1 reveals the fix can land locally.
- **Push the upstream branch to upstream's main repo instead of
  the fork:** without the M2 fork-detect, the worker may try
  `git push origin loom-<bead-id>` and either fail-noisy (no
  write access) or fail-silent (succeed against a personal fork
  that happens to be `origin`). Always push to the `fork` remote
  explicitly.
- **Re-clone for every contribution:** the worker doesn't check
  `~/.loom/upstream/<owner>/<repo>/` for existence and re-clones
  every time. Wastes bandwidth + loses any local commit history
  from prior contributions. The M2 existence check is mandatory.
- **Skip the dirty-state refusal:** a prior contribution left
  uncommitted changes or an unpushed branch in the clone. The new
  M4 GREEN gets entangled with the prior work; the PR diff
  includes unrelated changes. Always refuse on dirty state;
  surface to user for manual cleanup via `/loom-upstream-gc`.

## Related infrastructure

This recipe is the upstream-contribution-shaped peer to the other
six activity recipes. The cross-activity lifecycle scaffolding
lives in `bead-lifecycle-shell`. Sibling activity recipes:

- `bugfix-a-bead` (loom-lzi) — bug-shaped middle (debug → RED →
  GREEN → bug-class → enshrined-sweep)
- `feature-a-bead` (loom-3z1) — design → plan → RED → GREEN →
  negative-cases + integration
- `refactor-a-bead` (loom-uca) — characterization tests +
  restructure
- `research-a-bead` (loom-0q0) — define → search → synthesize →
  file
- `cleanup-a-bead` (loom-62x) — scope → remove → verify
- `docs-a-bead` (loom-s0n) — gap → draft → review

The `/working-a-bead` slash command (loom-1ab) is the router that
picks among these by `bead.type` + label heuristics (`upstream:work`
→ upstream-a-bead).

Infrastructure that integrates with this recipe (build queue
tracked under loom-k2g):

- `lib/loom-upstream.sh` (loom-k2g.2) — shared clone helpers used
  by M2 (existence check, canonical-owner check, dirty-state
  refusal, fork-detect).
- `/check-upstream-prs` (loom-k2g.3) — periodic-sweep slash command
  that auto-closes watch-beads when their PR merges.
- `/loom-upstream-gc` (loom-k2g.4) — interactive prune of
  `~/.loom/upstream/` clones; refuses on dirty state or open
  watch-bead reference.
- `audit-project` (loom-k2g.6) — surfaces orphan clones + missing
  `gh auth status`.

Subagents that integrate with this recipe:
- `drawer-author` — phase D3 helper; drafts the closing decision
  drawer with the WHAT LANDED + privacy-redactions +
  fork-detection + CONTRIBUTING-adaptations sections.
- `kg-relationship-extractor` — phase D3 helper; proposes the three
  KG triples above.

Full design + locked decisions live in the MemPalace drawer
"loom-k2g — UPSTREAM-PR FLOW: DESIGN LOCKED" (`loom/decisions`,
`drawer_loom_decisions_a6e64f9cfb21a9d16fc47604`, 2026-05-27).
Build queue tracked under loom epic `loom-k2g`.
