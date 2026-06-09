---
name: loom-adopt
description: One-shot "make this repo fully loom-standard" orchestrator. Composes the existing loom primitives — audit-project (workflow infra), scripts-scaffold, docs-scaffold, history-mine, constitution — into a dependency-ordered phase machine with per-phase checkpoint interactivity, graceful degradation over unbuilt primitives, and an idempotent + resumable run model. Delegates every phase to the primitive that owns it; never re-implements one. Manual-only — fires when the user invokes `/loom-adopt`.
---

# Loom-Adopt — Full-Treatment Brownfield Onboarding Orchestrator

This skill is the driver behind the `/loom-adopt` slash command. It is
the one-shot "make this repo fully loom-standard" pass: it **composes**
the loom primitives a project would otherwise adopt one at a time —
`audit-project` (workflow infra), scripts-scaffold, `docs-scaffold`,
history-mine, and the constitution surface — into a single
dependency-ordered phase machine.

It is an **orchestrator, not a worker**. Every phase is **delegated**
to the primitive that owns it; this skill writes nothing of its own
except the closing adoption report and the per-phase checkpoint
prompts. The composition discipline is the whole point — `/loom-adopt`
is to the adoption primitives what `/working-a-bead` is to the activity
recipes: a router that sequences them, gates between them, and reports
across them.

It doubles as a "refresh to current loom standards" pass: re-running it
on an already-adopted project re-audits the skip-satisfied items and
incrementally mines only what is new (see the idempotency + resume model
below).

The governing postures, stated up front:

- **DRY composition.** Phase P1 delegates wholesale to
  `/audit-project --apply`. This skill does NOT re-enumerate the audit
  checklist (bd-hooks, workflow.json, MemPalace wing, CLAUDE.md, rules
  dir, …). The audit skill owns that list; duplicating it here would
  fork the source-of-truth. When you want to know what the workflow-infra
  phase does, read `skills/audit-project/SKILL.md`, not this file.
- **Graceful degradation.** The phase list is enumerated **dynamically
  from what is installed** in the loom checkout. A phase whose primitive
  is not built is **skipped with a logged reason**, never silently
  dropped and never a hard error. A brownfield run on a loom checkout
  that predates scripts-scaffold (loom-oxs) or the constitution surface
  (loom-8jz/ld4) simply skips those phases and says so.
- **Per-phase checkpoint interactivity.** The user is in the loop once
  per phase (announce → confirm → run → show → proceed). This is the
  middle path between the two rejected extremes: **NOT one-shot
  autonomous** (the user never sees a five-primitive juggernaut run to
  completion unattended) and **NOT a per-file nag** (each delegated
  primitive owns its own internal approval granularity).

Invocation: explicit only. `/loom-adopt` fires this skill. The slash
command carries `disable-model-invocation: true` — the user has to ask.
Like its sibling write-heavy primitives (`/audit-project`,
`/docs-scaffold`) it is never auto-suggested by session-startup, the
activity recipes, or any hook.

## When to use

- The user types `/loom-adopt` in a repo they want brought up to the
  full loom standard in one pass.
- A brownfield repo (one that predates loom's discipline) just had
  `bd init` run and the user wants the whole treatment — infra + scripts
  + docs + decision-archaeology + constitution — rather than running the
  five primitives by hand.
- An already-adopted project has drifted from current loom standards and
  the user wants a "refresh" pass (the idempotent re-run path).

## Skip when

- The user wants exactly one of the phases. Run that primitive directly
  (`/audit-project`, `/docs-scaffold`, `/loom-mine-history`) — the
  orchestrator is for the full treatment, not a single step.
- Mid-task in another bead. Adoption is a session-spanning ceremony;
  don't interleave it with claimed work.
- The repo is not a git repo and not intended to be loom-managed. P1
  (audit-project) will refuse on a non-loom target; there is nothing for
  the later phases to build on.

## Flags

- `--root <path>` — project root to adopt (default: current working
  directory's git root, or cwd if not in a git repo). Forwarded verbatim
  to every delegated primitive, so the whole pass targets the same root.
  Mirrors the precedence chain used by `/audit-project` and
  `/docs-scaffold`.
- `--wing <name>` — MemPalace wing for the history-mine + constitution +
  tunnel phases (default: basename of `--root`, used **verbatim** — no
  `_`↔`-` substitution, matching `scripts/loom-audit-resolve`). The wing
  resolved here is the one P4 mines into and P5 tunnels from; P1 also
  reports against it.
- `--resume` — explicitly resume an interrupted run from the unfinished
  phase recorded in the run state (see "Resume model"). Without the
  flag, a re-run still behaves idempotently (skip-satisfied + incremental
  mine), but `--resume` is the unambiguous "pick up where the crash left
  off" entry.
- `--from <Pn>` — start at phase `Pn` (e.g. `--from P3`), skipping the
  earlier phases. Useful when the earlier phases were already done by
  hand. Phases before `Pn` are reported as `skipped (--from)`.

## The phase machine

Five phases, **dependency-ordered**. P1 must precede P4 (P4 mines into
the wing P1 resolves) and P5 (P5 files onboarding beads + tunnels that
reference the audited infra). **P2 and P3 are order-independent** — both
are pure scaffolds with no cross-dependency, so either order is correct;
the machine runs them in numeric order by convention only.

| Phase | Responsibility | Delegates to | Skip condition |
|---|---|---|---|
| **P1** | workflow-infra | `/audit-project --apply` | never (P1 is the floor) |
| **P2** | `scripts/` scaffold | scripts-scaffold (loom-oxs) | skip if loom-oxs not landed |
| **P3** | docs-scaffold | `/docs-scaffold` | skip if docs-scaffold not installed |
| **P4** | history-mine | `/loom-mine-history` | skip if history-mine not installed |
| **P5** | constitution + onboarding beads + wing tunnels | constitution surface (loom-8jz/ld4) | skip if constitution not landed |

### Dynamic phase enumeration (graceful degradation)

**Do NOT hardcode the five-phase list as runnable.** Before the run,
**detect which primitives are installed** in this loom checkout and
build the phase list dynamically. Each phase has a one-line presence
probe against the loom checkout (`<loom>`):

- **P1 audit-project** — `<loom>/skills/audit-project/SKILL.md` AND
  `<loom>/commands/audit-project.md` exist. (Always present in any loom
  checkout new enough to ship this skill; P1 is the floor and is not
  expected to be skippable.)
- **P2 scripts-scaffold** — `<loom>/templates/scripts/` exists OR
  `<loom>/skills/scripts-scaffold/SKILL.md` exists. This is the
  **loom-oxs** deliverable. If neither is present, **P2 is skipped with
  reason `scripts-scaffold (loom-oxs) not landed`**.
- **P3 docs-scaffold** — `<loom>/skills/docs-scaffold/SKILL.md` exists.
- **P4 history-mine** — `<loom>/scripts/loom-mine-history` AND
  `<loom>/skills/loom-mine-history/SKILL.md` exist.
- **P5 constitution** — `<loom>/hooks/constitution-enforce.sh` exists
  (the **loom-8jz** enforce hook) — the signal that the constitution
  surface is actually wired, not just schematized. The schema/template
  alone (`templates/project-constitution.md`, loom-vin) is **not
  sufficient**; without the enforcement + surfacing half (loom-8jz/ld4)
  there is no onboarding flow to run, so **P5 is skipped with reason
  `constitution (loom-8jz/ld4) not landed`**.

A phase whose probe fails is **not run, not errored** — it is recorded
in the phase list as `SKIP (<reason>)` and surfaced in the closing
report's `skipped-why` section. The run proceeds to the next phase. This
is the graceful-degradation contract: a loom checkout that has built
three of the five primitives runs a three-phase adoption and tells the
user exactly which two it could not do and why.

The dynamically-built phase list is what the run iterates. A future loom
version that lands loom-oxs and loom-8jz/ld4 will, without any change to
this skill, light those phases up — the enumeration reads the filesystem,
not a frozen list.

## Per-phase checkpoint loop

For **each phase in the dynamically-enumerated list**, run this loop.
The checkpoint is per-phase — once around this loop per phase, NOT once
per file the delegated primitive touches.

1. **Announce.** Print a one-line banner: which phase, what it will do,
   and which primitive it delegates to. For a skipped phase, announce the
   skip + reason and continue to the next phase (no confirm beat for a
   skip — there is nothing to confirm).
2. **Confirm.** Ask the user `Run phase <Pn> (<name>)? (yes / skip /
   stop)`. Then **STOP and wait for the user's next message** — this is a
   conversational pause, not a tool-permission gate (same invariant as
   `/audit-project` Step 4, loom-xcw). `yes` → run; `skip` → record
   `skipped (user)` and move on; `stop` → end the run cleanly, writing
   the resume state so a later `--resume` picks up here.
3. **Run.** Delegate to the owning primitive (see each phase below).
   The delegated primitive owns its OWN internal interactivity — P1's
   per-item audit gate, P3's per-file scaffold approval, P4's two-pass
   cost-preview gate. `/loom-adopt` does NOT re-implement or override
   those; it hands control to the primitive and waits for it to return.
4. **Show.** Surface the delegated primitive's result summary verbatim
   (audit PASS/WARN/MISS counts; scaffold wrote/skipped counts; mine
   adoption summary; etc.), then record the phase outcome in the run
   state.
5. **Proceed.** Move to the next phase. The user is back in the loop at
   that phase's announce/confirm beat.

The loop is deliberately the middle of two rejected extremes:

- **NOT one-shot autonomous.** There is a confirm beat per phase; the
  user can `skip` or `stop` between any two phases. A five-primitive run
  never executes start-to-finish without the user seeing each boundary.
- **NOT a per-file nag.** The checkpoint is per *phase*. Each delegated
  primitive owns its own finer-grained approval (per-file, per-item,
  per-cost-gate). `/loom-adopt` does not add a second nag layer on top.

## The phases

### P1 — workflow-infra (delegate to `/audit-project --apply`)

The floor phase, always present. **DELEGATE wholesale** to the
`audit-project` skill with `--apply-onboarding` (and `--apply-trivial`
where the user opted into doc-fix auto-apply), forwarding the resolved
`--root` / `--wing`. The audit skill runs the project-onboarder scan,
auto-applies its AUTOFIX-tagged onboarding gaps (bd-hooks, workflow.json,
gitignore, env-block, …), and leaves the rest in its own per-item queue.

**Do NOT re-enumerate the audit checklist here.** The list of
onboarding checks, their AUTOFIX recipes, and their per-item gates live
in `skills/audit-project/SKILL.md` and nowhere else. P1's whole job is to
invoke that skill and relay its report. The wing the audit resolves is
the wing P4 + P5 consume downstream — capture it from the audit's output
(it reports the resolved wing) and thread it forward.

If P1 reveals the project is not loom-manageable (audit refuses), stop
the whole run with that message — the later phases have no foundation.

### P2 — `scripts/` scaffold (loom-oxs; skip if not landed)

Scaffold the canonical GitHub-style `script/` convention (the loom-oxs
deliverable: `script/setup`, `script/test`, `script/lint`, …) into the
project. **Delegate** to the scripts-scaffold primitive when installed
(presence probe above). The scaffold is project-type-aware and per-file
approval-gated, mirroring `docs-scaffold`'s shape.

**If loom-oxs is not landed** (no `templates/scripts/` and no
`skills/scripts-scaffold/SKILL.md`), **skip P2 with reason
`scripts-scaffold (loom-oxs) not landed`** and continue. This is the
expected state today; the skip is correct behavior, not a gap.

P2 and P3 are order-independent; running P2 before P3 is convention, not
a dependency.

### P3 — docs-scaffold (delegate to `/docs-scaffold`)

Scaffold the Diataxis-shaped MkDocs docs tree. **Delegate** to the
`docs-scaffold` skill, forwarding `--root`. That skill owns its own M1–M6
sequence (detect target, detect primitives, detect existing docs +
opt-out, gather variables, per-file preview, apply). `/loom-adopt` does
not re-implement the scaffold; it hands off and relays the summary.

`docs-scaffold` refuses on a non-loom-managed project, an opt-out marker
(`docs/.no-diataxis`), or a generated `docs/` tree. Those refusals are
relayed as the P3 outcome, not treated as orchestrator errors — the user
made a docs-convention choice the orchestrator respects.

### P4 — history-mine (delegate to `/loom-mine-history`; needs the wing from P1)

Mine the project's git/PR history into `provenance:mined` decision
drawers. **Delegate** to the `loom-mine-history` skill, forwarding the
resolved `--root` and the **wing resolved in P1** (P4 mines into that
wing — this is the P1→P4 dependency edge).

P4 **nests its own cost-preview gate.** The `loom-mine-history` skill
owns the mandatory two-pass cost gate: a zero-spend `--dry-run` preview →
explicit user go-ahead → the paid LLM salience pass → MCP filing.
`/loom-adopt` does NOT bypass, pre-confirm, or re-implement that gate —
the per-phase `confirm` beat authorizes *entering* P4; the cost-preview
gate inside P4 is a SECOND, finer gate that still requires its own
explicit go-ahead before any spend. The two gates compose; neither
substitutes for the other.

On a re-run, P4 mines **incrementally via watermark** (only history past
the last-mined point), so re-adoption does not re-mine and re-file
already-captured decisions. See the resume + idempotency model.

### P5 — constitution + onboarding beads + wing tunnels (loom-8jz/ld4; skip if not landed)

The final phase wires the project's constitution surface and the
cross-project connective tissue:

- **constitution** — generate the project's `.claude/project-constitution.md`
  from the template (filling shell/package-manager/language/canonical-commands
  for the project's detected shape) and confirm the enforcement hook is
  wired.
- **onboarding beads** — file the standard follow-up beads a freshly
  adopted project owes (e.g. author the prose body of the constitution,
  backfill the docs FIXME sentinels, review the mined drawers).
- **wing tunnels** — connect the project's MemPalace `decisions` wing to
  related wings via tunnels (e.g. `<project>/decisions ↔ loom/decisions`
  when the adoption was loom-driven).

**Delegate** the constitution generation to the constitution surface
(loom-8jz/ld4) when installed. **If the constitution surface is not
landed** (no `hooks/constitution-enforce.sh`), **skip P5 with reason
`constitution (loom-8jz/ld4) not landed`** and continue to the report.
The schema/template alone (loom-vin) is not enough to run an onboarding
flow, so the skip is the correct degradation today.

## Idempotency + resume model

The run is **idempotent** and **resumable**. State lives in a small
run-state file under the target project
(`<root>/.claude/loom-adopt-state.json`, gitignored), recording per-phase
outcome (`done` / `skipped:<reason>` / `pending`) and, for P4, the mine
watermark.

- **Idempotent re-run.** Re-running `/loom-adopt` on an already-adopted
  project does NOT redo finished work:
  - **P1** re-audits and finds its onboarding items **skip-satisfied** —
    the audit's own idempotent AUTOFIX recipes (workflow.json present,
    gitignore lines present, env-block canonical) report no-op, so the
    re-audit surfaces a clean PASS rather than re-writing.
  - **P4** mines **incrementally via the watermark** — only commits/PRs
    after the last-mined point are harvested, so re-adoption never
    re-files an already-mined decision. (The dedup check inside
    `loom-mine-history` is the second line of defense; the watermark is
    the first.)
  - **P2 / P3 / P5** re-detect existing scaffold/docs/constitution and
    present only the genuinely-missing pieces (each delegated primitive's
    "exists — identical / would-overwrite" logic handles this per-file).
  This is what makes `/loom-adopt` double as a "refresh to current loom
  standards" pass.

- **Resumable after interruption.** If a run is interrupted (the user
  said `stop`, or the session crashed mid-phase), the run-state file
  records the **unfinished phase**. A later `/loom-adopt --resume`
  reads that state and **resumes at the unfinished phase**, treating
  the already-`done` phases as skip-satisfied. The user does not re-walk
  the completed phases. Without `--resume`, a plain re-run still reaches
  the same end-state (idempotent), but `--resume` is the explicit
  "continue the interrupted run" entry that jumps straight to the
  unfinished phase.

## Output — the adoption report

After the last phase (run or skipped), emit a single **adoption report**:

```markdown
# Loom adoption: <project-short-name> (<YYYY-MM-DD>)

## Phases
P1 workflow-infra   — done   (audit: PASS <n> · WARN <n> · MISS <n>; applied <k>)
P2 scripts/ scaffold — SKIP   (scripts-scaffold (loom-oxs) not landed)
P3 docs-scaffold    — done   (wrote <n> files, skipped <k>)
P4 history-mine     — done   (filed <n> drawers, <k> skipped-dup, <t> triples)
P5 constitution     — SKIP   (constitution (loom-8jz/ld4) not landed)

## Installed   (infra applied by P1)
<the AUTOFIX recipes audit-project applied: bd-hooks, workflow.json, …>

## Scaffolded  (P2 + P3)
<scripts/ files written; docs/ tree written>

## Mined       (P4)
<drawers filed into <wing>/decisions, tagged provenance:mined>

## Skipped-why (graceful degradation)
P2 — scripts-scaffold (loom-oxs) not landed
P5 — constitution (loom-8jz/ld4) not landed

## Beads-filed (P5 onboarding follow-ups, if P5 ran)
<bead IDs filed for constitution-body authoring, docs FIXME backfill, …>

## Next steps
<resume hint if a phase was stopped; re-run hint for refresh>
```

The five report sections — **installed / scaffolded / mined /
skipped-why / beads-filed** — are the contract; a phase that did not run
contributes a `skipped-why` line and nothing to its own section. The
report is the single artifact the user reads to know what the adoption
pass did and did not do.

## What this skill does NOT do

- **Does not re-implement any delegated primitive.** P1 is
  `audit-project`, P2 is scripts-scaffold, P3 is `docs-scaffold`, P4 is
  `loom-mine-history`, P5 is the constitution surface. This skill
  sequences and gates between them; it does not duplicate their logic.
- **Does not re-enumerate the audit checklist.** P1 delegates wholesale.
  The onboarding-check list lives in `skills/audit-project/SKILL.md`.
- **Does not bypass the history-mine cost gate.** P4's two-pass
  cost-preview gate is the `loom-mine-history` skill's, run in full —
  the per-phase confirm beat authorizes entering P4, not spending in it.
- **Does not run a phase whose primitive is unbuilt.** Such phases are
  skipped with a logged reason and surfaced in `skipped-why`; an unbuilt
  primitive is never a hard error.
- **Does not auto-run end-to-end.** The per-phase checkpoint requires a
  user-typed `yes` / `skip` / `stop` per phase. `--dangerously-skip-permissions`
  removes the tool-permission layer, not the per-phase user-approval beat
  (loom-xcw).
- **Does not commit on the user's behalf** beyond what the delegated
  primitives do (e.g. the audit's bd-hooks absorbing commit). The user
  reviews and commits the adoption changes.

## Why this exists

A greenfield loom project accretes the loom standard naturally — infra,
docs, constitution, MemPalace memory all grow as the project does. A
brownfield repo starts the opposite way: an empty palace but a rich
decision record already sitting in git, and none of the five surfaces
wired. Adopting loom on a brownfield repo meant running five primitives
by hand, in the right order, remembering which depend on which.

`/loom-adopt` collapses that into one gated pass. The value is the same
as the design-cycle's value over ad-hoc design: predictability. A user
adopting loom on a new repo runs one command, answers one confirm per
phase, and gets a report of exactly what landed and what was skipped and
why — no archaeology, no five-step checklist to remember, no silent gaps.

The composition-not-reimplementation discipline is load-bearing. If
`/loom-adopt` forked the audit checklist or the scaffold logic, those
forks would drift from the primitives they copied — the exact lying-doc
failure mode loom-qj3 diagnosed, re-imported at the orchestration layer.
By delegating wholesale and only sequencing + gating + reporting, the
orchestrator stays correct as long as the primitives it composes stay
correct.

## Related infrastructure

- Slash command: `commands/loom-adopt.md` — manual-only entry point with
  `disable-model-invocation: true`.
- P1 primitive: `skills/audit-project/SKILL.md` + `commands/audit-project.md`
  (the delegated workflow-infra checklist + `--apply` recipes).
- P2 primitive: scripts-scaffold (loom-oxs; `templates/scripts/`) — the
  GitHub-style `script/` convention; degrades-skip until landed.
- P3 primitive: `skills/docs-scaffold/SKILL.md` + `commands/docs-scaffold.md`.
- P4 primitive: `skills/loom-mine-history/SKILL.md` +
  `scripts/loom-mine-history` — the two-pass cost-gated decision-archaeology
  pass P4 nests.
- P5 primitive: the constitution surface (loom-8jz enforce hook +
  loom-ld4 surfacing; `templates/project-constitution.md` schema is
  loom-vin) — degrades-skip until the enforce/surface half lands.
- Epic: loom-bn7 (brownfield adoption). This skill is loom-bn7.6.
- Contract test: `lib/tests/loom-adopt.test.sh`.
