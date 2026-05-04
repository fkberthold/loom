# Getting started: your first bead

> A guided first session. You will install loom, open a Claude Code
> session in a beads workspace, claim a small bead, ship it, and watch
> the workflow primitives fire along the way. By the end you will have
> closed one real bead with a decision drawer captured in MemPalace.
>
> Time: about 3 minutes to read; about 10–20 minutes to do.
>
> Honesty caveat: loom assumes you already use beads (`bd`) and
> MemPalace day-to-day. If you do not, work through their own
> getting-started material first — loom is the connective tissue,
> not the foundation. The first session described below also assumes
> you have a real, small, low-stakes bead in your queue. If you do
> not, file one with `bd create` ("update a typo in the README" is
> fine) before starting.

---

## What you will do

You will:

1. Install loom into `~/.claude/`.
2. Open Claude Code in a project that has a beads workspace.
3. Pick a workflow mode for that project (the first session prompts).
4. Run `/session-startup` and let it surface a ready bead.
5. Claim the bead via `/working-a-bead <id>`.
6. Follow the recipe through to a clean commit + push.
7. Close the bead with `/wrap-up` and watch a decision drawer get filed.

Stop after step 7. That is your first shipped bead.

---

## 1. Install

You install loom by symlinking its files into `~/.claude/`. The repo
holds the canonical files; your home directory holds pointers.

```bash
git clone https://github.com/<your-org>/loom.git ~/repos/loom
cd ~/repos/loom
./install.sh
```

You will see backup files appear (suffixed `.pre-loom.bak`) for any
existing `~/.claude/skills/`, `agents/`, `commands/`, `hooks/`, or
`scripts/` files that loom now owns. That is expected. The installer
also merges `settings.snippet.json` into your `~/.claude/settings.json`
without touching keys it does not own.

If you need the deeper install reference — prerequisites, manual
verification, or the uninstall path — see
[How-to: install loom](../how-to/install.md).

## 2. Open a session

Change into a project that uses beads, and launch Claude Code:

```bash
cd ~/path/to/your/beads-project
claude
```

Claude Code starts. You will see the welcome banner. At the bottom of
the TUI, the status line reads something like:

```
WORKFLOW: full | idle | <some duration>
```

That is the loom status line. It is empty for the first instant, then
populates from the workflow state file once the session warms up.

## 3. Pick a workflow mode (first time only)

If this is the first time loom has seen this project, the
SessionStart onboarding hook fires and asks you to pick a mode. You
will see Claude prompt you with three options:

- `full` — every hook fires, every recipe runs, drawer capture is
  enforced. Pick this if you want all the discipline.
- `light` — hooks are informational only, recipes run with reduced
  ceremony, the close-capture hook never blocks. Pick this if the
  full ceremony is overkill for the project.
- `off` — hooks stay silent, recipes refuse to run. Pick this for
  exploratory spikes or projects that should not use the workflow.

For your first session, type `full`. Claude writes the answer to
`<project>/.claude/workflow.json` and remembers it. Future sessions
in this project will skip the prompt.

If you want the rationale behind these three modes, see
[Explanation: workflow modes](../explanation/workflow-modes.md).

## 4. Prime the session

Type:

```
let's pick up where we left off
```

Claude invokes `/session-startup` and walks the cold-start ritual. It
runs `bd prime`, surveys the ready queue, checks for in-progress
beads, peeks at MemPalace, and reads the most recent diary entries.
After about 5–10 seconds, Claude reports back with something like:

> Cold-start primed. `bd ready` leads with `<your-bead-id>` (P3,
> "<your bead's title>"). No in-progress beads. Recommendation:
> proceed with `<your-bead-id>`.

Pick the smallest, lowest-stakes bead you have. Reply:

```
yes, let's work on <your-bead-id>
```

## 5. Claim and route

Now you invoke the router. Type:

```
/working-a-bead <your-bead-id>
```

The router inspects the bead with `bd show`, scores it against the
six activity recipes (bugfix, feature, refactor, research, cleanup,
docs), and picks one. You will see Claude announce its pick:

> Engaging `bugfix-a-bead` for `<your-bead-id>`.

Honesty caveat: the router (`/working-a-bead`) is the v2 dispatch
shape. If it has not yet shipped on your install, invoke the recipe
directly — for example, `/bugfix-a-bead <id>` — or describe the work
in plain English and Claude will match the right recipe by
description.

Claude then runs the recipe's first phase: a MemPalace search for
prior art on this bead's family. The `bd-claim-research` hook also
fires, reminding Claude to do exactly that. After 5–15 seconds, you
see a "Prior art for `<your-bead-id>`" report with a recommended
approach.

Reply:

```
proceed
```

Claude runs `bd update <your-bead-id> --claim`, optionally creates a
worktree, and starts the variable middle of the recipe (RED test →
GREEN fix → bug-class coverage for bug-shaped beads; brainstorm →
RED contract → GREEN implementation for feature-shaped beads; and so
on for the other shapes).

## 6. Follow the recipe

You will not need to remember the steps. Each recipe walks itself
and asks for your approval at the right moments. Watch the status
line shift through stages:

```
WORKFLOW: full | task:claim | bead:<id> | <Ns>
WORKFLOW: full | task:tdd-red | bead:<id> | <Ns>
WORKFLOW: full | task:verify | bead:<id> | <Ns>
```

For your first bead, follow Claude's lead. When it presents a test,
read it. When it asks for approval to commit, approve. When it asks
which finishing option you prefer, pick option 1 (merge locally + push
— the simplest path for a small bead).

Two things to expect:

1. The recipe will run a test cycle even on a tiny change. That is
   the discipline holding. Trust it.
2. Verification will print exact pass/skip/fail counts before
   declaring done. If those counts surprise you, stop and look —
   that is the recipe doing its job.

For full reference on each recipe's phases, see
[Reference: skills](../reference/skills/index.md).

## 7. Close + capture

When the merge is done, type:

```
/wrap-up
```

`/wrap-up` runs preflight checks, dispatches the `drawer-author` and
`kg-relationship-extractor` subagents in parallel, and presents you
with a draft decision drawer for review. Read it. If the summary
matches reality, approve. Claude then files the drawer in MemPalace,
adds a few KG triples, writes a diary entry, closes the bead with
`bd close`, and pushes.

When the dust settles, you will see:

```
On branch main
Your branch is up to date with 'origin/main'.
nothing to commit, working tree clean
```

That is your first shipped bead. The decision is now searchable in
MemPalace; the bead is closed; the commit is on origin.

---

## What you noticed

You did not have to remember to:

- Search for prior art before designing — the recipe's phase A1 did it.
- Write a test before the fix — the recipe enforced it.
- File a decision drawer before closing — `/wrap-up` orchestrated it.
- Push the branch — the recipe walked you through finishing the
  development branch.

You did have to:

- Pick the bead.
- Approve drafts (the drawer body, the KG triples, the merge option).
- Write the actual code change. Loom does not do the work for you;
  it makes sure you do not skip the discipline around the work.

---

## Where to go next

- For a deeper, fully-narrated bug session, read
  [the bug walkthrough](./bug-walkthrough.md).
- For a feature-shaped bead from claim to close, read
  [the feature walkthrough](./feature-walkthrough.md).
- When you want to do something specific (claim a bead, finish a
  branch, configure modes), browse the
  [How-to guides](../how-to/index.md).
- For the conceptual model behind loom — what the four-axis memory
  model is, why the recipes are shaped this way — see
  [Explanation](../explanation/index.md).
