---
description: "Scaffold a Diataxis-shaped MkDocs Material docs/ tree into the current loom-managed project by copying templates/diataxis/ with per-file approval. Manual-only — never auto-suggested by session-startup, the activity recipes, or any hook. The user has to ask."
disable-model-invocation: true
---

Invoke the `docs-scaffold` skill and follow it exactly as presented.

Step 1: confirm the cwd is loom-managed (`.claude/workflow.json`
present). If not, refuse and tell the user to run `/audit-project`
first to onboard the project.

Step 2: walk M1-M6 from the skill — detect target, detect
primitives, detect existing docs (honoring `docs/.no-diataxis`),
gather variables, preview the diff, apply with substitutions.

Step 3: at M5 the user approves PER FILE. Skip declined files; never
overwrite without explicit approval. At M6 emit a summary plus next
steps (install requirements, `mkdocs serve`, push to enable Pages).

This is strictly a manual workflow. The docs-scaffold skill is
`disable-model-invocation: true` and is never auto-suggested by
session-startup, the activity recipes, or any hook. Even the
`project-onboarder` Diataxis-shape check (loom-km8.3) only *reports*
the gap and *names* `/docs-scaffold` as the fix — it never invokes.
