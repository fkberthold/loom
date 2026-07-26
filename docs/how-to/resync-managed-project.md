# Resync a managed project's conventions

When loom's shipped conventions (its `templates/` tree — Diataxis
docs scaffolding, design-doc drawers, exploration drawers, the
`.claude/project-constitution.md` template) move on since your project
last synced, use `/audit-project --check=drift` to see exactly what
changed and `/audit-project --apply-drift` to review it file by file.
For the mechanism underneath this flow, see
[reference: downstream convention-drift detector](../reference/convention-drift-detector.md).

## Precondition

- The project is **loom-managed** — it carries a
  `<root>/.claude/workflow.json`, or it has been audited against loom at
  least once via `install.sh` (loom's own bootstrap) or a prior
  `/audit-project` run of any kind. Every `/audit-project` invocation,
  regardless of `--check=` mode, writes a `last_checked` record into
  `<root>/.claude/.loom-sync`. A loom-managed project that has **never**
  been synced — no stamp at all, or a stamp carrying only
  `last_checked` — gets the *never-synced* variant of the nudge below,
  pointing at this same procedure (`loom-oktm`, `loom-uh4i`). Only a
  project that is loom-managed by **neither** signal stays silent.
- You're working from the loom-managed project's root (or pass
  `--root <path>` / `--wing <wing>` explicitly, same precedence chain
  as every other `/audit-project` mode).

## Steps

1. **Notice the nudge (optional).** At the start of a session in a
   drifted project, a SessionStart hook may have already printed:

   ```text
   [loom-drift-nudge] INFO: this project's loom-convention stamp
   (hash=abc123456789..., synced 2026-06-01) is behind loom's current
   conventions (hash=def987654321...) — run `/audit-project
   --apply-drift` to resync.
   ```

   This is purely informational and fires at most once per session.
   You don't need to see it to run the steps below — it's just the
   trigger most people follow this guide from.

2. **See exactly what changed.**

   ```text
   /audit-project --check=drift
   ```

   This compares your project's stamped hash against loom's current
   one and, on a mismatch, lists every `templates/<relpath>` file that
   changed since your last sync date:

   ```text
   ## Convention drift detection
   [DRIFT] templates/diataxis-README.md changed since 2026-06-01
   [DRIFT] templates/design-doc/DESIGN-DOC-TEMPLATE.md changed since 2026-06-01
   ```

   If your project has never synced before, every file in
   `scripts/loom-convention-manifest --list` is reported as drifted
   (there's nothing to diff against). If the hashes already match,
   you'll see `no convention drift detected` and there is nothing
   further to do.

   This run also records a **check** in `.claude/.loom-sync`
   (`last_checked` + today's date) — that happens on every
   `/audit-project` invocation, not just this one. It does **not**
   record a sync, and it does **not** silence the nudge: looking at a
   project is not the same as remediating it (`loom-uh4i`). Only step 3
   can write the `last_synced` record.

3. **Queue the drifted files for review.**

   ```text
   /audit-project --apply-drift
   ```

   (`--apply-drift` implies `--check=drift`, so you can run this
   directly and skip step 2 if you don't need the standalone report.)

4. **Approve, skip, or quit — per file.** For each drifted item you'll
   see a diff preview followed by a prompt:

   ```text
       --- a/.claude/loom-templates/diataxis-README.md
       +++ b/templates/diataxis-README.md
       @@ ...
   Item: <root>/.claude/loom-templates/diataxis-README.md (queued from
   <loom>/templates/diataxis-README.md). Apply? (approve/skip/quit):
   ```

   Nothing is written without an explicit `approve`. `skip` leaves
   that one file untouched; `quit` stops the queue immediately and
   leaves every remaining item — even ones later in the list — unresolved.
   This is enforced by the underlying `scripts/loom-drift-resolve`
   engine itself, not just by the skill's prose, so it holds even if
   you drive the script by hand outside an agent session.

## The one file that IS applied live

Most items resolve into a mirror (next section). **One does not.**

`.claude/rules/loom-conventions.md` is a file **loom owns outright** —
loom's project-agnostic working conventions (dispatch defaults, the
`Files:` / `RED:` / `AUTOFAN-EXCLUDE:` bead lines, the splitting
heuristic, drawer-first capture, gate-don't-advise, the
explore → design → build ladder). It carries no variable
substitutions, it says "do not edit" in its own header, and you are
never expected to hand-edit it. So `--apply-drift` queues it at its
**real path** and an `approve` writes it there:

```text
Item: <root>/.claude/rules/loom-conventions.md (queued from
<loom>/templates/rules/loom-conventions.md). Apply? (approve/skip/quit):
```

This is also how the file gets **seeded** the first time. A project
that has never carried it reports:

```text
[DRIFT] <root>/.claude/rules/loom-conventions.md (absent — never seeded from templates/rules/loom-conventions.md)
```

— and the same `approve` creates it, parent directories included. Your
own `CLAUDE.md` gets a one-line pointer to it from
`/audit-project --apply-onboarding` (the
`[AUTOFIX:loom-conventions-pointer]` item), and stays 100%
project-owned otherwise: loom appends that pointer and touches nothing
else in it, ever.

If you disagree with something in the conventions file, **do not patch
your copy** — the next resync overwrites it and takes your
disagreement with it. Raise it against loom instead. If you want none
of it, decline the item; declining is remembered by nothing, so the
nudge keeps offering, which is deliberate (an opt-out should be
explicit — set `LOOM_DRIFT_NUDGE_SKIP=1` — never silently inferred
from a skip).

Note this check does **not** consult the sync stamp. It compares the
bytes on disk against loom's current copy, so a project whose stamp
says "in sync" is still reported as drifted when its actual file
trails. That combination is not hypothetical — it is exactly the
failure this check was added for.

## The mirror, not a live resync

**For every OTHER item, `--apply-drift` does not touch your project's
real files.** An `approve` writes loom's current template content to a
project-local **mirror** path:

```text
<root>/.claude/loom-templates/<relpath>
```

— never to `docs/<relpath-under-diataxis>`,
`.claude/project-constitution.md`, or wherever your project's live
scaffolded copy actually lives. Those files may carry per-project
variable substitution (`{{ project_name }}`, `{{ repo_url }}`, …) or
your own hand edits that this engine makes no attempt to reconcile —
folding loom's raw template back over a customized file would clobber
work this detector has no way to distinguish from drift.

Once the mirror is populated, the reconciliation is yours:

```bash
diff .claude/loom-templates/diataxis-README.md docs/index.md
```

Review the diff, fold in whichever hunks genuinely apply to your
project, and commit the result the same way you'd commit any other
doc change. This composes with, rather than fights,
[`/docs-scaffold`'s](scaffold-managed-project-docs.md) own per-file
substitution-and-approval flow and `/audit-project --check=constitution`'s
dedicated field-level diff — both already have their own reconciliation
paths; the drift detector's job stops at "here's what changed and
here's a local copy to diff against."

A general, live, cross-project template-reconciliation engine was
explicitly ruled out of scope for v1 (YAGNI) — see
[reference: downstream convention-drift detector](../reference/convention-drift-detector.md#scope-note-v1-intentional)
for the design rationale.

## Confirm you're back in sync

Re-run the check:

```text
/audit-project --check=drift
```

The stamp shows "in sync" only if step 3 actually **applied** at least
one item. A run where you `skip`ped every item applies nothing, leaves
the project byte-identical, and therefore leaves the nudge firing —
zero applied is a *check*, not a sync (`loom-uh4i`). This is
deliberate: before that fix, merely *looking* at a project marked it
synced, so the detector could be quieted without a single file
changing.

If you applied **some** items and skipped others, the run does count as
a sync: you were shown loom's current convention set and acted on it.
The stamp records loom's whole current hash, so the files you
deliberately skipped won't resurface as `[DRIFT]` lines next time —
track any skipped work the ordinary way, e.g. a follow-up bead, if you
intend to come back to it.

If you've decided you don't want loom's conventions in this project at
all, opt out explicitly with `LOOM_DRIFT_NUDGE_SKIP=1` in the
project's environment rather than by skipping items — an opt-out
inferred from a skip is exactly the silent-silencing behavior
`loom-uh4i` removed.

## Related

- [reference: downstream convention-drift detector](../reference/convention-drift-detector.md)
  — the manifest hash, the stamp file, the SessionStart nudge, and the
  two correctness gates that back this flow.
- [Author a project constitution](author-project-constitution.md) —
  `--check=constitution`'s own dedicated per-field diff, a sibling
  flow that this detector's scope note explicitly defers to.
- [Scaffold a managed project's docs](scaffold-managed-project-docs.md)
  — `/docs-scaffold`'s per-file substitution-and-approval flow, the
  other reconciliation path this detector composes with.
- [explanation: gate, don't advise](../explanation/gate-dont-advise.md)
  — why the SessionStart nudge never blocks while the drift-detector's
  own internal correctness gates do.
