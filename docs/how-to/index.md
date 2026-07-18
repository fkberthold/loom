# How-to guides

How-to guides are the *application + action* quadrant: focused
recipes for the already-competent user who knows what they want to
do. Each guide solves one problem; titles state the task precisely;
steps are executable.

If you are learning loom for the first time, start at the
[Tutorials](../tutorials/index.md) instead. For surface
catalogues, see the [Reference](../reference/index.md). For the
*why* behind the design, see the
[Explanation](../explanation/index.md).

## Install

- [Install loom](./install.md) — symlink loom into `~/.claude/`
  with backups for any pre-existing files loom owns.

## Daily lifecycle

The four pages below cover one lifecycle phase each. Read them in
order on a first pass; afterward, jump straight to the page that
matches what you are about to do.

- [Open a session](./open-a-session.md) — prime context, surface
  ready work.
- [Claim a bead](./claim-a-bead.md) — engage the matching activity
  recipe.
- [Finish a bead](./finish-a-bead.md) — wrap-up, capture, close,
  push.
- [Stop a session](./stop-a-session.md) — clean session-end with
  diary + drawer + push.

## Within a bead

- [Run the dispatch-middle pipeline](./run-dispatch-middle.md) — work
  a bead's RED→GREEN middle as a test-author → separate implementer
  pipeline so central writes nothing.

## Above a bead

- [Open a design cycle](./open-a-design-cycle.md) — drive an
  above-bead Plan→Research→Architect design cycle that grounds open
  questions and spawns the implementation epic.

## When the default ceremony does not fit

- [Bypass workflow ceremony](./bypass-workflow-ceremony.md) —
  per-call bypass, project-mode lowering, recipe skipping.

## Where to make a change

- [Where to update what](./where-to-update-what.md) — the canonical
  edit surface for each piece of loom's behavior.

## Adopt loom's docs convention in another project

- [Scaffold a managed project's docs](./scaffold-managed-project-docs.md)
  — copy loom's Diataxis skeleton into a managed project with
  per-file approval; opt-out marker; post-scaffold audit.
- [Author a project constitution](./author-project-constitution.md) —
  pin the project's tooling profile so hooks and dispatched workers
  stop guessing package manager, shell, and canonical commands.

## Keep a managed project's conventions in sync

- [Resync a managed project's conventions](./resync-managed-project.md)
  — see exactly which of loom's shipped templates moved since your
  last sync, and review each drifted file into a local mirror one at
  a time.

## Drive a fix into someone else's repo

- [Contribute a fix upstream](./contribute-upstream.md) — the
  two-bead lifecycle (work-bead closes fast on PR file; watch-bead
  closes slow on upstream merge) via the `upstream-a-bead` recipe.

## Recover from a crash

- [Recover from a dispatch crash](./recover-from-dispatch-crash.md) —
  the API-health-pause heuristic, probe-before-resume backoff, and the
  resume-from-WIP recipe for a dispatched worker that died mid-flight.

## Common scenarios

Recipes for recurring situations that span multiple lifecycle
steps:

- [I just got assigned a new bug](./common-scenarios/new-bug.md)
- [I have several unrelated bugs to fix](./common-scenarios/parallel-bugs.md)
- [I want to do exploratory work](./common-scenarios/exploratory-work.md)
- [I think I have seen this bug before](./common-scenarios/find-prior-art.md)
- [Something about the workflow feels broken](./common-scenarios/debug-workflow.md)
- [I need to tweak a hook](./common-scenarios/tweak-a-hook.md)
- [I need to add a path-scoped rule](./common-scenarios/add-path-rule.md)
