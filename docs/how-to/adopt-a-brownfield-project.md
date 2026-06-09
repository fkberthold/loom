# Adopt a brownfield project

To bring an existing repo — one that predates loom's discipline — up
to the full loom standard in one gated pass, run
[`/loom-adopt`](../reference/loom-adopt.md). It walks the project
through five dependency-ordered phases (audit → scripts → docs → mine →
constitution), pausing for your confirmation once per phase and
delegating each phase to the primitive that owns it.

This page walks a real brownfield adoption end-to-end. The shape that
matters: **workflow-infra first, then scaffolds, then
decision-archaeology** — the audit (P1) resolves the MemPalace wing that
the history-mine (P4) and constitution (P5) phases later consume.

## Precondition

- The target is a **git repo** you intend to bring under loom
  management. `/loom-adopt`'s P1 (audit-project) refuses on a non-loom
  target, and the later phases have no foundation without it.
- You are **not mid-task in another bead.** Adoption is a
  session-spanning ceremony — don't interleave it with claimed work.
- `git status` is reasonably clean in the target. The pass writes infra
  files, scaffolds, and a constitution; you want them in their own
  commit(s) to review.
- You have a **MemPalace** available (the history-mine phase files
  drawers into it). If MemPalace is offline, P4 cannot file — run the
  rest and come back to P4 later.

If you only want **one** of the phases, run that primitive directly
(`/audit-project`, `/docs-scaffold`,
[`/loom-mine-history`](../reference/loom-mine-history.md)). The
orchestrator is for the full treatment, not a single step.

## Steps

1. **Switch to the target project.** `/loom-adopt` resolves the target
   via the same precedence chain as `/audit-project`: explicit
   `--root <path>` flag wins, then cwd's git root, then cwd itself. The
   resolved root is forwarded verbatim to every delegated primitive, so
   the whole pass targets the same repo.

   ```bash
   cd /path/to/brownfield-repo          # implicit cwd
   # or
   /loom-adopt --root /path/to/brownfield-repo   # cross-project from anywhere
   ```

2. **Initialize beads if it isn't already.** A brownfield repo often has
   no `bd` workspace yet. P1 will surface this, but you can run it ahead
   of time:

   ```bash
   bd init      # only if .beads/ does not already exist
   ```

3. **Run the orchestrator.** `/loom-adopt` carries
   `disable-model-invocation: true` — it fires only when you type the
   slash command. No recipe, hook, or subagent triggers it for you.

   ```text
   /loom-adopt
   ```

   Optionally pin the wing the mine + constitution phases use (it
   defaults to the basename of the root, used verbatim):

   ```text
   /loom-adopt --wing my-project
   ```

4. **Watch the dynamic phase enumeration.** Before the run, the
   orchestrator probes which primitives are installed in your loom
   checkout and builds the runnable phase list from what it finds. A
   phase whose primitive isn't built is announced as `SKIP (<reason>)`
   and surfaced in the closing report — never silently dropped. So a
   three-of-five checkout runs a three-phase adoption and tells you which
   two it couldn't do and why.

5. **P1 — workflow-infra (`/audit-project --apply`).** The floor phase,
   always present. It runs the project-onboarder scan, auto-applies the
   onboarding gaps it can (bd-hooks, `workflow.json`, gitignore lines,
   env-block), and leaves the rest in its own per-item queue. **Capture
   the wing it reports** — that's the wing P4 and P5 consume downstream.

   ```text
   Run phase P1 (workflow-infra)? (yes / skip / stop)
   ```

   Answer `yes`. If P1 reveals the project isn't loom-manageable (the
   audit refuses), the whole run stops with that message — the later
   phases have no foundation.

6. **P2 — `scripts/` scaffold.** Scaffolds the GitHub-style `script/`
   convention (`script/setup`, `script/test`, `script/lint`, …) when the
   scripts-scaffold primitive is installed. If it isn't yet (the expected
   state in older loom checkouts), the phase announces
   `SKIP (scripts-scaffold (loom-oxs) not landed)` and continues. The
   skip is correct behavior, not a gap.

7. **P3 — docs-scaffold (`/docs-scaffold`).** Scaffolds the
   Diataxis-shaped MkDocs docs tree. This phase delegates wholesale to
   the docs-scaffold skill, which owns its own per-file approval gate —
   see [Scaffold a managed project's docs](scaffold-managed-project-docs.md)
   for the full M1–M6 walkthrough. `/loom-adopt` hands off and relays the
   summary. A refusal (non-loom target, a `docs/.no-diataxis` opt-out
   marker, or an existing generated `docs/` tree) is relayed as the P3
   outcome, not treated as an orchestrator error — it's a
   docs-convention choice the orchestrator respects.

8. **P4 — history-mine (`/loom-mine-history`).** This is the
   decision-archaeology phase: it mines the project's git/PR history into
   `provenance:mined` decision drawers in the wing P1 resolved.
   **P4 carries a second gate inside the per-phase confirm.** Entering P4
   only authorizes the phase; before any spend you see the mine's
   own **two-pass cost preview**:

   - The mine runs a **zero-spend dry-run** first and shows you a
     cost-preview line:

     ```text
     cost-preview: 142 harvested -> 38 gated -> ~38 LLM reads, est <= 40 model calls
     (wing for filing: my-project)
     ```

   - It then **stops and waits** for your explicit go-ahead. Only after
     you confirm does the paid LLM salience+draft pass run and file the
     drawers. `/loom-adopt` does not pre-confirm or bypass this gate —
     the two gates compose; neither substitutes for the other.

   If the preview is too expensive, decline and re-run with
   `--max-units` or `--since` to tighten the scope (the mine's flags are
   documented on the
   [loom-mine-history reference](../reference/loom-mine-history.md#flags)).
   On a **re-run** of `/loom-adopt`, P4 mines **incrementally via the
   watermark** — only history past the last-mined point — so re-adoption
   never re-files an already-captured decision.

9. **P5 — constitution + onboarding beads + wing tunnels.** The final
   phase generates the project's `.claude/project-constitution.md`, files
   the standard onboarding follow-up beads (author the constitution body,
   backfill the docs `DOCS-SCAFFOLD-FIXME` sentinels, review the mined
   drawers), and tunnels the project's `decisions` wing to related wings
   (e.g. `<project>/decisions ↔ loom/decisions` when the adoption was
   loom-driven). If the constitution surface isn't landed in your loom
   checkout, the phase announces
   `SKIP (constitution (loom-8jz/ld4) not landed)` and continues to the
   report.

10. **Read the adoption report.** After the last phase, the orchestrator
    emits a single report with five fixed sections — **installed /
    scaffolded / mined / skipped-why / beads-filed**:

    ```markdown
    # Loom adoption: my-project (2026-06-08)

    ## Phases
    P1 workflow-infra   — done   (audit: PASS 9 · WARN 2 · MISS 1; applied 6)
    P2 scripts/ scaffold — SKIP   (scripts-scaffold (loom-oxs) not landed)
    P3 docs-scaffold    — done   (wrote 17 files, skipped 0)
    P4 history-mine     — done   (filed 31 drawers, 7 skipped-dup, 93 triples)
    P5 constitution     — SKIP   (constitution (loom-8jz/ld4) not landed)
    ...
    ```

    A phase that didn't run contributes a `skipped-why` line and nothing
    to its own section. This report is the single artifact you read to
    know what the pass did and did not do.

11. **Review and commit.** `/loom-adopt` does not commit on your behalf
    beyond what the delegated primitives' own hooks do. Review the infra
    files, the scaffolds, and the constitution; commit them in coherent
    chunks. Then verify the docs build before pushing:

    ```bash
    pip install -r requirements.txt
    mkdocs build --strict
    git push
    ```

## Verify the mined decisions landed

The history-mine phase files into the project's **own** wing, in the
**same `decisions` room** as native captures, tagged
`provenance:mined`. To see what landed:

```text
/mempalace search "<a decision topic you expect>" --wing my-project
```

Or filter by the tag to review the whole mined set. With `--synthesize`,
the mine also files narrative-arc drawers tagged `synthesis:arc` — narrow
to those to read the higher-level story it stitched together. Because
mined drawers share the `decisions` room (rather than a separate `mined`
room), **bug-family search reaches them** the same way it reaches native
decisions; the tag is what carries provenance. See
[Provenance](../explanation/provenance.md) for why the tag-not-room
choice was made.

## Outcome

The brownfield repo carries the full loom standard: workflow infra
(bd-hooks, `workflow.json`, the rules dir, the MemPalace wing), the
scaffolds the loom checkout could build, a decision record mined out of
its own git history into `provenance:mined` drawers, and onboarding beads
for the follow-up work. The closing report records exactly which phases
ran, which skipped, and why.

## Refresh an already-adopted project

`/loom-adopt` is **idempotent** — re-running it on an already-adopted
project is the supported "refresh to current loom standards" path:

- **P1** re-audits and finds its onboarding items skip-satisfied (the
  audit's AUTOFIX recipes report no-op).
- **P4** mines **incrementally via the watermark** — only commits/PRs
  after the last-mined point are harvested, so it never re-files an
  already-mined decision.
- **P2/P3/P5** re-detect existing scaffold/docs/constitution and present
  only the genuinely-missing pieces.

Re-run after upgrading loom to pick up newly-landed phases without
re-walking the completed ones.

## Resume an interrupted adoption

If a run is interrupted — you answered `stop`, or the session crashed
mid-phase — the run-state file
(`<root>/.claude/loom-adopt-state.json`, gitignored) records the
unfinished phase. Pick up where it left off with:

```text
/loom-adopt --resume
```

`--resume` jumps straight to the unfinished phase, treating the
already-`done` phases as skip-satisfied. (A plain re-run reaches the same
end-state via idempotency, but `--resume` is the unambiguous "continue
the interrupted run" entry.) You can also start partway through a fresh
run with `--from <Pn>` when the earlier phases were already done by hand.

## Related

- For the orchestrator itself — the phase machine, the per-phase
  checkpoint loop, and the full report contract — see
  [reference: loom-adopt](../reference/loom-adopt.md).
- For the P4 decision-archaeology primitive — the two-pass cost gate,
  the `provenance:mined` tag, and the watermark incremental model — see
  [reference: loom-mine-history](../reference/loom-mine-history.md).
- For the P3 docs scaffold's per-file walkthrough, see
  [Scaffold a managed project's docs](scaffold-managed-project-docs.md).
- For why mined drawers share the `decisions` room under a tag rather
  than a separate room, see [Provenance](../explanation/provenance.md).
