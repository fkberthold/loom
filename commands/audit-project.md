---
description: "Audit the current project's workflow infrastructure (git/branch hygiene, beads init, bd hooks, workflow.json, MemPalace wing, CLAUDE.md, .claude/rules/, .claude/agents/+commands/, bd memories) and offer interactive fixes from templates for each gap. Manual-only — never auto-suggested by session-startup or any other skill."
disable-model-invocation: true
---

Invoke the `audit-project` skill and follow it exactly as presented.

Forward any flags the user passed to the slash command — the skill
parses them. Recognized flags:

- `--check=onboarding|docs|all` — pick which phase runs.
- `--apply-trivial` — auto-apply doc-drift items the skill tagged
  `[DOC FIX][TRIVIAL]`: cardinality count corrections (loom-469
  class) and dead-bead-IDs whose `bd show` returns a unique
  `superseded-by` ID. Larger/ambiguous fixes still require per-item
  approval. (loom-8hg.)
- `--apply-onboarding` — auto-apply onboarding-checklist items the
  `project-onboarder` subagent tagged `[AUTOFIX:<recipe-id>]` on
  the suggested-fix line: `bd-hooks` (item 3 — runs `bd hooks
  install` + the loom-cka absorbing commit), `workflow-json` (item
  4 — writes `{"v":1,"mode":"full"}`), `gitignore-worktrees` (item
  11 — appends `.claude/worktrees/`). Items requiring real human
  choice (`bd init`, MemPalace wing creation, CLAUDE.md authoring)
  are NOT tagged AUTOFIX and remain in the per-item approval
  queue. WARN items are never auto-applied. (loom-a29.)
- `--workflow-mode=full|light|off` — override the mode value the
  `[AUTOFIX:workflow-json]` recipe writes when `--apply-onboarding`
  is set. Default `full`.
- `--root <path>` — project root to audit (default: cwd's git
  root, then cwd). Lets the slash command run against any
  loom-managed project, not just loom itself.
- `--wing <name>` — MemPalace wing for drawer-citation resolution
  (default: basename of `--root`, used **verbatim** — no `_`↔`-`
  substitution, no case-folding; matches `scripts/loom-audit-resolve`
  and the skill).
- `--mine-history` — after the audit report, delegate to the
  `/loom-mine-history` engine to mine the project's git/PR history
  for unmined decisions (behind its own two-pass cost gate). WITHOUT
  this flag, the audit only *flags* the gap informationally (the
  onboarder's decision-history line) and never mines.

Step 1: dispatch the `project-onboarder` subagent with the absolute
path to the resolved project root and the resolved project short
name (the `--wing` value, used as both wing slug and bd-memories
keyword). Wait for its structured checklist report.

Step 2: present the report to the user.

If `--apply-trivial` and/or `--apply-onboarding` was passed, the skill's
Step 3.5 walks the report and applies every `[DOC FIX][TRIVIAL]` /
`[AUTOFIX:<id>]`-tagged item before the per-item loop starts. The
auto-applied items appear in an `## Auto-applied` section; everything
else flows to the per-item approval queue below.

For each remaining `MISS` / `WARN` / `[DOC FIX]` item, offer the
template-based fix from the skill. Do NOT auto-apply any fix outside
the flag scope; require explicit user approval per item — meaning a
user-typed reply in a fresh user message, NOT a tool-permission
acceptance. The per-item gate is a conversational pause: print the
prompt, then STOP and wait for the user's next message.

`--dangerously-skip-permissions` is about TOOL permissions
(Write/Edit/Bash allowed without prompt) and does NOT imply blanket
user approval for AUTOFIX items — every per-item gate still requires
a user-typed yes/skip/edit reply. (loom-xcw.)

Step 3: when the user says "skip" or "no" for an item, move on.
When they approve, generate the fix from the skill's template,
preview it, and only then write to disk.

Auto-applied changes (from `--apply-trivial` / `--apply-onboarding`)
leave git in a dirty state — the user reviews with `git diff` and
commits or reverts themselves. The single exception is the
`[AUTOFIX:bd-hooks]` recipe, which intentionally creates one absorbing
commit (`bd: post-install export sync`) to clear the bd hook's
export-pending queue per loom-cka.

This is strictly a manual workflow. The audit-project skill is
`disable-model-invocation: true` and is never auto-suggested by
session-startup, the activity recipes, or any hook. The user has to
ask.
