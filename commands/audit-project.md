---
description: "Audit the current project's workflow infrastructure (git/branch hygiene, beads init, bd hooks, workflow.json, MemPalace wing, CLAUDE.md, .claude/rules/, .claude/agents/+commands/, bd memories) and offer interactive fixes from templates for each gap. Manual-only — never auto-suggested by session-startup or any other skill."
disable-model-invocation: true
---

Invoke the `audit-project` skill and follow it exactly as presented.

Step 1: dispatch the `project-onboarder` subagent with the absolute
path to the current project root and (if known) the project's short
name. Wait for its structured checklist report.

Step 2: present the report to the user. For each `MISS` or `WARN`
item, offer the template-based fix from the skill. Do NOT auto-apply
any fix; require explicit user approval per item.

Step 3: when the user says "skip" or "no" for an item, move on.
When they approve, generate the fix from the skill's template,
preview it, and only then write to disk.

This is strictly a manual workflow. The audit-project skill is
`disable-model-invocation: true` and is never auto-suggested by
session-startup, working-a-bead, or any hook. The user has to ask.
