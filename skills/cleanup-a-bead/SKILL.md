---
name: cleanup-a-bead
description: Activity recipe for working a cleanup-shaped beads issue. Owns the cleanup-specific variable middle — identify scope → hunt orphan references → remove → verify nothing broke. Defers to the bead-lifecycle-shell skill for claim/isolate/verify/close/capture. Triggers on phrases like "remove <X>", "delete <Y>", "drop <Z> dep", "rip out <W>", "retire <thing>", or right after the session-startup or /working-a-bead router picks a cleanup bead.
---

# Cleanup-a-Bead — Variable Middle for Cleanup-Shaped Beads

This skill owns ONLY the cleanup-specific middle of the bead lifecycle.
The shared lifecycle scaffolding — MemPalace search, claim + worktree,
verification, commit, finish-branch, close + capture — lives in the
`bead-lifecycle-shell` skill. This recipe cites those phases by letter
and supplies the variable middle that runs between phase A (pre-middle)
and phase B (verification).

Cleanup is **removal**, not restructure. Code, files, deps, configs, or
hooks go away; nothing takes their place. That's the cleanest version
of "diff goes negative" work, and it's why this recipe is naturally
shorter than bugfix or feature: there's no new test scaffolding to
build (the deleted thing's tests are deleted with it), and verification
leans on the existing suite plus targeted smoke.

The distinguishing risk vs. refactor: cleanups are vulnerable to
**orphan references** — pointers to the removed thing that compile
clean and lint clean but break at runtime. Broken symlinks, stale
config keys, dead doc links, dangling settings, hooks that fire on a
removed script. The variable middle below is built around hunting
those *before* the delete lands, not after.

This recipe formalizes the shape that the HAW deploy-day cleanup
bead (80v) shipped via the trimmed `working-a-bead` recipe before this
skill existed. Future cleanups should use this recipe; the 80v
lineage is the prior art.

Invocation: explicit only — either directly (`/cleanup-a-bead <bead-id>`)
or via the `/working-a-bead` router that selects an activity recipe by
bead shape. The Skill tool may surface this recipe via auto-discovery
when a message strongly matches the trigger phrases above; if that
happens at the wrong moment (e.g., the bead isn't cleanup-shaped),
decline and switch to the right recipe.

## When to use

Right after `session-startup` (or the `/working-a-bead` router) picks
a cleanup-shaped bead, OR whenever you start implementation on a
claimed cleanup. A bead is cleanup-shaped when the deliverable is
`git rm`-shaped: code, file, dep, config, or hook goes away, and
nothing takes its place.

Cleanup beads are usually pre-scoped — they fall out of a prior
feature or refactor that obsoleted something. If the scope isn't
already crisp, run `bd orphans` and `bd stale` before M1 to surface
candidates, and search MemPalace for the originating bead/drawer that
flagged this thing as dead.

## Skip when

- The bead is bug/feature/refactor/research/docs-shaped — use the
  matching activity recipe instead.
- **The change is restructure, not removal.** Use `refactor-a-bead`.
  If code is moving, being renamed, or being reshaped while remaining
  in the codebase, the recipe shape is wrong here.
- **The removal is also a user-visible behavior change** (deprecation
  removal that breaks a public contract). That's feature-shaped first
  (announce, deprecate, migrate consumers) and cleanup-shaped second
  (delete the deprecated path). Split into two beads if so; don't try
  to land both shapes under one cleanup recipe.
- Mid-task interruption. This recipe is for new cleanup starts, not
  for context recovery within an in-flight bead.

## Workflow modes (v1.5)

This recipe inherits mode behavior from `bead-lifecycle-shell` (which
checks `<project>/.claude/workflow.json` `.mode` at the start of phase
A). Activity-specific behavior in each mode:

- **full** — run every step of the variable middle as written. Orphan
  hunt mandatory, full-suite verification mandatory, smoke-test
  mandatory if integration surfaces are touched.
- **light** — natural fit for cleanups; the recipe is already lighter.
  Orphan hunt at M2 stays mandatory regardless of mode (it's the step
  that prevents broken symlinks and stale config keys; not optional).
  Smoke-test scope can compress when only obviously-pure code is
  removed. Drawer-capture remains recommended.
- **off** — the shell refuses; this recipe never runs.

## Stage updates

Phase boundary stages are written by `bead-lifecycle-shell`. This
recipe adds activity-specific intermediate stages between phase A
and phase B:

| Step boundary | Stage to write |
|---|---|
| Entering step M1 (identify scope) | `scoping` |
| Entering step M2 (hunt orphan references) | `hunting-orphans` |
| Entering step M3 (remove) | `removing` |
| Entering step M4 (verify nothing broke) | `verifying` |

Write each via `~/.claude/scripts/workflow-state set stage=<stage>` at
the moment the step starts. The status line surfaces these so future
cold-start sessions can see exactly where work paused.

## The Sequence

### Phase A — pre-middle (delegate to shell)

Follow `bead-lifecycle-shell` phase A:
- **A1.** MemPalace search for the cleanup family (sets stage
  `research`). For cleanups the queries are:
  - `mempalace_search "<name-of-thing-being-removed>"` — does a
    decision drawer mention this thing? Often the originating
    feature/refactor drawer flagged it as dead-after-cutover.
  - `mempalace_search "cleanup <area>"` — prior cleanup conventions
    in this area (kill-list shape, smoke-test pattern, what surfaces
    typically need re-scanning).
  - `mempalace_kg_query("<entity-name>")` — surfaces dependents the
    KG knows about. Anything pointing AT the entity is potentially
    an orphan reference once it's removed.
  - `bd memories <keyword>` — tribal one-liners (e.g., "X was kept
    only because Y still calls it" — that note is gold for M1).
- **A2.** `bd update <id> --claim`, then optional worktree on
  `frank/<bead>` from `main`. Cleanups are commonly worktree-worthy
  even when small, because the orphan-hunt diff sometimes spans many
  files even though the removal itself is focused.

If the search surfaces the bead/drawer that pre-scoped this removal,
read it before M1 — the originating context usually names what's
being removed AND what stays. Don't redo that scoping from scratch.

### Variable middle — M1 → M4 (recipe owns)

#### M1. Identify scope

Set stage `scoping`. Write down two lists, in your own words:

1. **What gets removed.** The exact set of files, functions, configs,
   deps, hooks, symlinks, doc sections. Be specific to path or symbol
   level — "the foo helper" is not specific; `lib/foo.sh` and
   `lib/tests/foo.bats` is specific.
2. **What's NOT being removed.** The adjacent things you might
   *think* are also dead but aren't. This is the bounding fence
   around the diff. State it explicitly so the diff stays focused
   and so a reviewer can quickly verify scope.

Sources for this scope, in order of authority:

- The originating bead/drawer (if A1 surfaced one).
- `bd orphans` and `bd stale` output if the scope wasn't pre-defined.
- A targeted `Grep` against the project for the names you intend to
  remove — if the count of references is much higher than expected,
  the thing is more alive than the bead assumed; pause and check.

State both lists to the user before moving to M2. Cleanup scope
disagreements are cheap to resolve at M1 and expensive at M3.

#### M2. Hunt orphan references — BEFORE removing

Set stage `hunting-orphans`. This is the step that earns this recipe
its keep. For every name, path, symbol, or config key on the
"removed" list from M1, grep the entire repo (and adjacent repos if
cross-project) and build a **kill-list** of every other file that
references it.

Surfaces to scan that aren't covered by the test suite:

- **Docs** — README, manual, walkthrough, in-tree `docs/` files. Dead
  doc links don't break tests; they break readers.
- **Configs** — `settings.json`, `workflow.json`, `kustomize`
  overlays, `*_VERSION` files, generated configs. Stale keys
  silently noop or, worse, log warnings nobody sees.
- **Hooks and scripts** — `~/.claude/settings.json` hook entries,
  `scripts/*.sh`, CI `.github/workflows/`, pre-commit. A hook that
  fires on a removed script is a runtime trap.
- **Symlinks** — `install.sh`-created symlinks under `~/.claude/`
  pointing at repo files. Removing the target without removing the
  symlink leaves a dangling pointer that next install reproduces.
- **Generated files** — Goa output, mocks, `gen/` directories.
  Regenerate after the delete; orphan generated artifacts mask
  source-of-truth removals.
- **Slash commands** — `~/.claude/commands/*.md` that invoke a
  removed skill or script.
- **Adjacent project repos** — if the removed thing is consumed by
  another project (e.g., loom skills consumed by HAW workflows),
  grep there too. The cd-chain hook discipline applies: cleanup at
  the source can ricochet into consumers.

Write the kill-list as a plain bullet list. Each entry is a file +
the change needed (delete the line / delete the file / regenerate /
update the link). The kill-list is what M3 actually executes; M2 is
the planning step.

If the kill-list is much larger than expected, surface it before
proceeding. Sometimes a "small cleanup" is actually a cross-cutting
deprecation that wants its own bead.

#### M3. Remove

Set stage `removing`. Execute the kill-list in one focused commit.
Include both the deletions and the kill-list updates (doc edits,
config edits, symlink removals) in the same commit so the repo stays
**consistent at every commit boundary** — never land a commit where
the removed thing is gone but the references aren't, or vice versa.

Use `git rm` for tracked files; for files outside the repo (e.g.,
`~/.claude/...` symlinks created by install.sh), note the manual
cleanup in the commit body and update install.sh in a separate,
explicit commit if the install logic itself needs to change. The
install.sh discipline from CLAUDE.md applies: this repo is
canonical, symlinks are per-installation.

Keep the diff focused. Resist `while I'm here` adjacent fixes; if
something else looks wrong, file a separate bead and move on. The
cleanup commit's value is partly that future bisect can land on it
cleanly when an orphan reference is found later.

#### M4. Verify nothing broke

Set stage `verifying`. Three layers, in order:

1. **Full test suite** — run from a clean shell. Pass count should
   match baseline minus the deleted tests; no new failures.
2. **Targeted smoke** — for cleanups touching integration surfaces,
   exercise the surface directly. Examples:
   - settings.json hot-reload: trigger a hook and confirm it fires
     (or correctly no-ops) post-removal.
   - install.sh: re-run a clean install and confirm symlinks land
     correctly with no dangling targets.
   - statusline: render once with `bash ~/.claude/scripts/statusline.sh
     < /dev/null` and confirm output is sane.
   - service start: `./scripts/server` (or equivalent) starts
     without the removed component logged as missing.
3. **Non-test surface check** — `Grep` for any name from the M1
   removal list. The expected result is *zero hits* outside the
   commit's own diff. Hits are evidence M2 missed something.

Cleanups can compile clean and lint clean and still break at runtime
via orphan references. M4.3 is the runtime-trap canary; treat hits
seriously even when they look benign.

### Phase B — verification (delegate to shell, with cleanup extension)

Return to `bead-lifecycle-shell` phase B (sets stage `verify`).
Re-run the full suite from a clean shell, confirm exact pass/fail
counts, check `git diff --stat` matches the kill-list scope. State
results with evidence in user-facing output BEFORE moving to phase C.

**extends phase B with: post-removal `bd orphans` and `bd stale`
re-scan.** The output should be cleaner than before the cleanup, not
dirtier. New orphans/stale entries surfaced by the re-scan are
evidence the removal opened up follow-up work — file as new beads,
don't expand this one.

### Phase C — integration (delegate to shell)

Follow `bead-lifecycle-shell` phase C:
- **C1.** Code review. For cleanups the review focus is "scope
  matches the M1 lists" and "kill-list looks complete" — reviewers
  catch orphan references the M2 grep missed.
- **C2.** Commit on the branch (sets stage `commit`). Subject + body
  should name what was removed, why it was dead, the kill-list size,
  and the smoke surfaces exercised at M4. Co-author trailer.
- **C3.** `superpowers:finishing-a-development-branch` — pick from
  the four options.

### Phase D — closeout (delegate to shell)

Follow `bead-lifecycle-shell` phase D:
- **D1.** `bd preflight`.
- **D2.** `bd close <id> --reason="<one-line>"` → `bd dolt push` →
  `git push` (sets stage `close`).
- **D3.** Drawer + KG triples + diary capture (sets stage `wrap-up`).
  The closing drawer should name:
  - **What was removed** (the M1 list, in final form).
  - **Why it was dead** (the originating bead/drawer; cutover that
    obsoleted it; deprecation that completed).
  - **Kill-list size** (count of files touched outside the deleted
    set; useful for future cleanups estimating their orphan-hunt
    blast radius).
  - **Orphan-hunt method used** (which surfaces were scanned, which
    tools, which adjacent repos). This is the part that future
    cleanups copy.

  Skip KG triples in light mode unless the cleanup encoded a
  convention ("X was kept only for Y; once Y went away, X went
  away") — those triples are durable design knowledge.

## When cleanup surfaces a refactor or bug

If M2's orphan hunt reveals that the "removal" actually requires
restructuring something else first — e.g., the dependent consumer
needs its shape changed before the dep can be dropped — file a
sibling refactor bead and either:

- **Block** this cleanup on the refactor bead via `bd dep`, OR
- **Split** the work: file the refactor bead, close this cleanup as
  not-yet-actionable with a pointer to the refactor, re-open after.

Resist mid-cleanup scope creep. The whole shape of cleanup-a-bead is
"remove without restructuring"; the moment that's no longer true,
the bead's recipe is wrong, not the work. Same applies if M2
surfaces a bug in the consumer — file a bugfix bead, don't fold it
into this commit.

## Failure modes (concrete)

- **Skip M2 (orphan hunt):** the removal lands, tests pass, lint
  passes — and three days later a hook fires on a removed script,
  or a doc link 404s, or a symlink dangles. The 80v deploy-day
  cleanup caught two such orphans (one stale settings.json key, one
  doc reference) only because the manual hunt was done *before*
  the delete commit. Skipping M2 means hoping luck covers what
  discipline should have.
- **Partial removal — kill-list executed inconsistently:** the
  source file is deleted but its symlink still exists, or the dep
  is removed from `package.json` but still imported in one file.
  Compile may pass under lazy resolution; runtime fails on the
  unused-but-still-loaded path. Always commit the full kill-list
  atomically; never split into "delete the thing now, fix the
  references later."
- **"While I'm here" scope creep:** mid-cleanup you spot two other
  things that look dead and pull them into the same commit. Now
  the diff is unreviewable, the kill-list doesn't match the bead
  scope, and a rollback later loses unrelated work. File new beads
  for new candidates; close this one on its original scope.
- **Removing a thing still in use via dynamic dispatch:** the grep
  at M2 finds zero references because the consumer reaches the
  removed thing through reflection, a string-named hook entry, a
  generated config, or runtime path resolution. M4.2 smoke testing
  catches some of this; M4.3 doesn't. The mitigation: when removing
  something that *could* be reached dynamically (skills, hooks,
  scripts, config-driven dispatch tables), exercise the dispatch
  path directly during smoke, don't trust grep alone.
- **Missing the docs/config surface:** test suite passes, lint
  passes, runtime smoke passes — but the manual still tells users
  to run the removed script, or the example config still lists the
  removed key. The thing is broken for new readers even though
  existing flows work. M2 must include docs and configs explicitly;
  the test suite does not cover prose.
- **Skip phase D3 capture:** the next cleanup re-derives the
  orphan-hunt method from scratch. The whole point of capturing
  "kill-list size" and "surfaces scanned" is that the next cleanup
  has a starting checklist instead of figuring it out cold.

## Related infrastructure

This recipe is the cleanup-shaped peer to `bugfix-a-bead`. The
cross-activity lifecycle scaffolding lives in `bead-lifecycle-shell`.
Sibling activity recipes:

- `bugfix-a-bead` (loom-lzi) — bug-shaped middle (debug → RED →
  GREEN → bug-class → enshrined-sweep)
- `feature-a-bead` (loom-5rf) — feature-shaped middle
- `refactor-a-bead` (loom-uca) — characterization tests + restructure
- `research-a-bead` (loom-0q0) — define → search → synthesize → file
- `docs-a-bead` (loom-s0n) — gap → draft → review

The `/working-a-bead` slash command (loom-1ab) is the router that
picks among these by `bead.type` + description heuristics.

Subagents that integrate with this recipe:
- `drawer-author` — phase D3 helper; drafts the closing decision
  drawer with the removed-set, kill-list size, and orphan-hunt
  method recorded for future cleanups.
- `kg-relationship-extractor` — phase D3 helper; useful when the
  cleanup encoded a convention ("X depended on Y; X removed when
  Y removed") that should be discoverable on future searches.

Prior art: the HAW deploy-day cleanup bead `80v` shipped via the
trimmed `working-a-bead` recipe before this skill existed. Its
shape — pre-scoped removal, manual orphan hunt before the delete
commit, full-suite verification — is what this recipe formalizes.

Full design + locked decisions live in the MemPalace drawer
"RECIPE SHAPES — ACTIVITY MATRIX" (`hundred_acre_woods/decisions`,
2026-05-02). Build queue tracked under loom epic `loom-0y6`.
