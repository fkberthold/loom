---
description: "Audit the current project's workflow infrastructure (git/branch hygiene, beads init, bd hooks, workflow.json, MemPalace wing, CLAUDE.md, .claude/rules/, .claude/agents/+commands/, bd memories) and offer interactive fixes from templates for each gap. Manual-only — never auto-suggested by session-startup or any other skill."
disable-model-invocation: true
---

Invoke the `audit-project` skill and follow it exactly as presented.

Forward any flags the user passed to the slash command — the skill
parses them. Recognized flags:

- `--check=onboarding|docs|all` — pick which phase runs.
- `--apply-trivial` — auto-apply trivial doc fixes (count
  corrections + dead-bead-ID supersedes-chain replacement).
- `--root <path>` — project root to audit (default: cwd's git
  root, then cwd). Lets the slash command run against any
  loom-managed project, not just loom itself.
- `--wing <name>` — MemPalace wing for drawer-citation resolution
  (default: basename of `--root`, lowercased, `_`→`-`).

Step 1: dispatch the `project-onboarder` subagent with the absolute
path to the resolved project root and the resolved project short
name (the `--wing` value, used as both wing slug and bd-memories
keyword). Wait for its structured checklist report.

Step 2: present the report to the user. For each `MISS` or `WARN`
item, offer the template-based fix from the skill. Do NOT auto-apply
any fix; require explicit user approval per item.

Step 3: when the user says "skip" or "no" for an item, move on.
When they approve, generate the fix from the skill's template,
preview it, and only then write to disk.

This is strictly a manual workflow. The audit-project skill is
`disable-model-invocation: true` and is never auto-suggested by
session-startup, the activity recipes, or any hook. The user has to
ask.
