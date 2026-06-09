---
description: "One-shot 'make this repo fully loom-standard' orchestrator. Loads the loom-adopt skill, which composes the loom adoption primitives — audit-project (workflow infra), scripts-scaffold, docs-scaffold, history-mine, constitution — into a dependency-ordered phase machine with per-phase checkpoint interactivity, graceful degradation over unbuilt primitives, and an idempotent + resumable run model. Manual-only — never auto-suggested by session-startup, the activity recipes, or any hook. The user has to ask."
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

Step 2 — run the per-phase checkpoint loop. For each enumerated phase:
announce → confirm → run → show → proceed. The confirm beat (`yes / skip
/ stop`) is a conversational pause: print it, then STOP and wait for the
user's next message before delegating. This is per-PHASE, not per-file —
each delegated primitive owns its own internal approval granularity
(audit per-item, docs per-file, mine cost-gate). Do not add a second nag
layer. `stop` writes the resume state and ends cleanly.

`--dangerously-skip-permissions` is about TOOL permissions
(Write/Edit/Bash without prompt) and does NOT imply blanket user
approval — every per-phase gate still requires a user-typed reply
(loom-xcw).

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
