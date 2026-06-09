# loom-adopt — reference

> One-shot "make this repo fully loom-standard" orchestrator.
> `/loom-adopt` composes the loom adoption primitives — audit-project,
> scripts-scaffold, [`/docs-scaffold`](../how-to/scaffold-managed-project-docs.md),
> [history-mine](loom-mine-history.md), and the constitution surface —
> into a single dependency-ordered, per-phase-gated pass. It is an
> **orchestrator, not a worker**: every phase is delegated to the
> primitive that owns it. Manual-only — it fires only when you type the
> command.

Adopting loom on a brownfield repo used to mean running five primitives
by hand, in the right order, remembering which depend on which.
`/loom-adopt` collapses that into one gated pass. It is to the adoption
primitives what `/working-a-bead` is to the activity recipes: a router
that sequences them, gates between them, and reports across them. It
doubles as a "refresh to current loom standards" pass — re-running it on
an already-adopted project re-audits the skip-satisfied items and mines
only what is new.

## Governing postures

- **DRY composition.** Every phase delegates **wholesale** to the
  primitive that owns it. `/loom-adopt` never re-enumerates the audit
  checklist, never re-implements the scaffold logic, never re-derives
  the mine's cost gate. When you want to know what a phase does, read
  the owning primitive's skill — not this orchestrator. (Forking those
  lists would re-import the lying-doc failure mode at the orchestration
  layer.)
- **Graceful degradation.** The phase list is enumerated **dynamically
  from what is installed** in the loom checkout. A phase whose primitive
  is not built is **skipped with a logged reason**, never silently
  dropped and never a hard error.
- **Per-phase checkpoint interactivity.** You are in the loop once per
  phase (announce → confirm → run → show → proceed). This is the middle
  path between two rejected extremes: not a one-shot autonomous
  juggernaut, and not a per-file nag (each delegated primitive owns its
  own internal approval granularity).

## The five phases

The phases are **dependency-ordered**. P1 must precede P4 (P4 mines into
the wing P1 resolves) and P5 (P5 files onboarding beads + tunnels that
reference the audited infra). **P2 and P3 are order-independent** — both
are pure scaffolds with no cross-dependency; numeric order is
convention only.

| Phase | Responsibility | Delegates to | Skip condition |
|---|---|---|---|
| **P1** | workflow-infra | `/audit-project --apply` | never (P1 is the floor) |
| **P2** | `scripts/` scaffold | scripts-scaffold (loom-oxs) | skip if loom-oxs not landed |
| **P3** | docs-scaffold | [`/docs-scaffold`](../how-to/scaffold-managed-project-docs.md) | skip if docs-scaffold not installed |
| **P4** | history-mine | [`/loom-mine-history`](loom-mine-history.md) | skip if history-mine not installed |
| **P5** | constitution + onboarding beads + wing tunnels | constitution surface (loom-8jz/ld4) | skip if constitution not landed |

### Dynamic phase enumeration (graceful degradation)

The runnable phase list is **not hardcoded**. Before the run, the
orchestrator probes the loom checkout for each primitive's presence and
builds the phase list from what is actually installed. A phase whose
probe fails is recorded as `SKIP (<reason>)` and surfaced in the closing
report's `skipped-why` section; the run proceeds to the next phase.

This is the degradation contract: a loom checkout that has built three
of the five primitives runs a three-phase adoption and tells you exactly
which two it could not do and why. A future loom version that lands the
missing primitives lights those phases up with no change to the
orchestrator — the enumeration reads the filesystem, not a frozen list.

## The per-phase checkpoint loop

For each phase in the dynamically-enumerated list:

1. **Announce.** A one-line banner: which phase, what it will do, which
   primitive it delegates to. A skipped phase announces its skip +
   reason and continues (no confirm beat — there's nothing to confirm).
2. **Confirm.** `Run phase <Pn> (<name>)? (yes / skip / stop)`, then a
   conversational pause until your next message. `yes` → run; `skip` →
   record `skipped (user)` and move on; `stop` → end cleanly, writing
   the resume state so a later `--resume` picks up here. This is a
   conversational pause, not a tool-permission gate —
   `--dangerously-skip-permissions` removes the permission layer, not
   this per-phase user-approval beat.
3. **Run.** Delegate to the owning primitive. The delegated primitive
   owns its **own** internal interactivity — P1's per-item audit gate,
   P3's per-file scaffold approval, P4's two-pass cost-preview gate.
   `/loom-adopt` does not re-implement or override those.
4. **Show.** Surface the delegated primitive's result summary verbatim.
5. **Proceed.** Move to the next phase's announce/confirm beat.

### The two nested gates at P4

P4 (history-mine) carries **two gates that compose**: the per-phase
`confirm` beat authorizes *entering* P4, and the
[`/loom-mine-history`](loom-mine-history.md) **two-pass cost-preview
gate** inside P4 is a second, finer gate that still requires its own
explicit go-ahead before any spend. `/loom-adopt` does not bypass,
pre-confirm, or re-implement the cost gate — neither gate substitutes
for the other.

## Idempotency + resume model

Run state lives in a small file under the target project
(`<root>/.claude/loom-adopt-state.json`, gitignored), recording per-phase
outcome (`done` / `skipped:<reason>` / `pending`) and, for P4, the mine
watermark.

- **Idempotent re-run.** Re-running on an already-adopted project does
  not redo finished work: P1 re-audits and finds its onboarding items
  skip-satisfied; **P4 mines incrementally via the watermark** (only
  history past the last-mined point — see
  [history-mine](loom-mine-history.md)); P2/P3/P5 re-detect existing
  scaffold/docs/constitution and present only the genuinely-missing
  pieces. This is what makes `/loom-adopt` double as a "refresh"
  pass.
- **Resumable after interruption.** If a run is interrupted (`stop`, or
  a crash), the run-state file records the unfinished phase. A later
  `/loom-adopt --resume` resumes at that phase, treating already-`done`
  phases as skip-satisfied. Without `--resume`, a plain re-run still
  reaches the same end-state (idempotent); `--resume` is the
  unambiguous "pick up where the crash left off" entry.

## Flags

| Flag | Effect |
|---|---|
| `--root <path>` | Project root to adopt (default: cwd's git root, or cwd). Forwarded verbatim to every delegated primitive so the whole pass targets the same root. |
| `--wing <name>` | MemPalace wing for the history-mine + constitution + tunnel phases (default: basename of `--root`, used verbatim). |
| `--resume` | Resume an interrupted run from the unfinished phase recorded in the run state. |
| `--from <Pn>` | Start at phase `Pn` (e.g. `--from P3`), reporting earlier phases as `skipped (--from)`. Useful when the earlier phases were already done by hand. |

## The adoption report

After the last phase (run or skipped), the orchestrator emits a single
**adoption report**. Its five sections are the contract — **installed
/ scaffolded / mined / skipped-why / beads-filed** — and a phase that
did not run contributes a `skipped-why` line and nothing to its own
section:

```markdown
# Loom adoption: <project-short-name> (<YYYY-MM-DD>)

## Phases
P1 workflow-infra   — done   (audit: PASS <n> · WARN <n> · MISS <n>; applied <k>)
P2 scripts/ scaffold — SKIP   (scripts-scaffold (loom-oxs) not landed)
P3 docs-scaffold    — done   (wrote <n> files, skipped <k>)
P4 history-mine     — done   (filed <n> drawers, <k> skipped-dup, <t> triples)
P5 constitution     — SKIP   (constitution (loom-8jz/ld4) not landed)

## Installed   (infra applied by P1)
## Scaffolded  (P2 + P3)
## Mined       (P4)
## Skipped-why (graceful degradation)
## Beads-filed (P5 onboarding follow-ups, if P5 ran)

## Next steps
```

The report is the single artifact you read to know what the adoption
pass did and did not do.

## What it does NOT do

- **Does not re-implement any delegated primitive** — it sequences and
  gates between them.
- **Does not re-enumerate the audit checklist** — P1 delegates wholesale
  to `/audit-project`.
- **Does not bypass the history-mine cost gate** — P4's two-pass gate
  runs in full.
- **Does not run a phase whose primitive is unbuilt** — such phases skip
  with a logged reason.
- **Does not auto-run end-to-end** — the per-phase checkpoint requires a
  typed `yes` / `skip` / `stop`.
- **Does not commit on your behalf** beyond what the delegated
  primitives do — you review and commit the adoption changes.

## Related

| Item | Page |
|---|---|
| P4 primitive — decision-archaeology with the two-pass cost gate | [loom-mine-history](loom-mine-history.md) |
| Walking a brownfield adoption end-to-end (audit → scaffold → mine) | [Adopt a brownfield project](../how-to/adopt-a-brownfield-project.md) |
| P3 primitive — the Diataxis docs scaffold | [Scaffold a managed project's docs](../how-to/scaffold-managed-project-docs.md) |
| Why mined drawers carry `provenance:mined` | [Provenance](../explanation/provenance.md) |
| Command (manual-only entry point) | `commands/loom-adopt.md` |

## Skill source

The full phase machine — dynamic enumeration, the per-phase checkpoint
loop, each phase's delegation contract, the idempotency + resume model,
and the report shape — is included verbatim below from
`skills/loom-adopt/SKILL.md`. Edits go to the primitive, not this page.

{%
  include-markdown "../../skills/loom-adopt/SKILL.md"
  heading-offset=1
%}
