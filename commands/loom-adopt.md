---
description: "One-shot 'make this repo fully loom-standard' orchestrator. Loads the loom-adopt skill, which composes the loom adoption primitives — audit-project (workflow infra), scripts-scaffold, docs-scaffold, history-mine, constitution — into a dependency-ordered phase machine that announces each phase as it runs, degrades gracefully over unbuilt primitives, and is idempotent + resumable. Manual-only — never auto-suggested by session-startup, the activity recipes, or any hook. The user has to ask."
disable-model-invocation: true
---

Invoke the `loom-adopt` skill and follow its phase machine exactly as
presented. Forward `--root <path>` / `--wing <name>` if provided so the
whole pass targets that project root + MemPalace wing (parity with
`/audit-project` and `/docs-scaffold`). Forward `--resume` to pick up an
interrupted run at its unfinished phase, and `--from <Pn>` to start at a
specific phase.

Step 0 — guest-mode gate: before adopting, source
`lib/refuse-on-guest.sh` and run `refuse_if_guest loom-adopt`. If it
errors (exit 1), stop immediately and surface the printed message to the
user. Guest mode (loom-guest) intentionally suppresses in-tree writes
from loom primitives; `/loom-adopt` writes infra + scripts + docs +
constitution into the host repo, so it must respect the gate. Run
`/loom-guest off` first if the adoption is genuinely intended.

Step 1 — enumerate the phases DYNAMICALLY. Detect which adoption
primitives are installed in this loom checkout (the skill's presence
probes) and build the runnable phase list from what is present. The five
phases, dependency-ordered:

- **P1 workflow-infra** — DELEGATE to `/audit-project --apply`. Do NOT
  re-enumerate the audit checklist; the audit skill owns it. Capture the
  wing the audit resolves and thread it to P4 + P5.
- **P2 scripts/ scaffold** — delegate to scripts-scaffold (loom-oxs).
  Skip with a logged reason if loom-oxs is not landed.
- **P3 docs-scaffold** — delegate to `/docs-scaffold`. (P2 and P3 are
  order-independent.)
- **P4 history-mine** — delegate to `/loom-mine-history`, mining into the
  wing from P1. P4 nests its OWN two-pass cost-preview gate — do not
  bypass or pre-confirm it.
- **P5 constitution + onboarding beads + wing tunnels** — delegate to the
  constitution surface (loom-8jz/ld4). Skip with a logged reason if the
  constitution surface is not landed.

A phase whose primitive is unbuilt is **skipped with a logged reason**,
never errored and never silently dropped — graceful degradation is the
contract. The skip + reason lands in the closing report's `skipped-why`
section.

Step 2 — run the per-phase loop. For each enumerated phase: announce →
run → show → proceed. Announce is a one-line banner naming the phase,
what it will do, and which primitive it delegates to. Show surfaces the
delegated primitive's result summary verbatim and records the phase
outcome in the run state.

There is NO confirm beat between phases. Step 1's presence probes have
already answered it. A phase whose primitive isn't installed skips
itself, and one whose primitive is installed is a phase the user asked
for when they typed `/loom-adopt`. What they get instead is the banner,
which tells them what's happening either way.

The delegated primitives keep their own gates (P1's per-item audit
queue, P4's cost preview). Dropping the outer beat removes a checkpoint
on *entering* a phase, not any gate inside one. Do not add a second
layer on top.

`--dangerously-skip-permissions` is about TOOL permissions
(Write/Edit/Bash without prompt) and does NOT imply blanket user
approval. P4's cost-preview gate still stops the run until the user
answers it (loom-xcw).

Step 3 — idempotent + resumable. A re-run re-audits skip-satisfied items
(P1's AUTOFIX recipes are idempotent no-ops when already applied) and
mines incrementally via the watermark (P4 only harvests history past the
last-mined point), so `/loom-adopt` doubles as a "refresh to current loom
standards" pass. An interrupted run resumes at the unfinished phase
recorded in `<root>/.claude/loom-adopt-state.json` (use `--resume`).

Step 4 — emit the adoption report. One report with the five sections:
**installed / scaffolded / mined / skipped-why / beads-filed**, plus a
per-phase done/skip line and next-step hints (resume hint if a phase was
stopped; re-run hint for refresh).

This is strictly a manual workflow. The loom-adopt skill is
`disable-model-invocation: true` and is never auto-suggested by
session-startup, the activity recipes, or any hook. The user has to ask.
