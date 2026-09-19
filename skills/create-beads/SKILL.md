---
name: create-beads
description: Use when you have a design or requirements and need to create beads (epics/tasks) for implementation
---

# Creating beads

Turn a design into beads. Check that `bd` is on PATH first, and **STOP**
if it is not.

## Split before you file

When two or more candidate items arrive together, ask whether they're
independent. No shared files, no sequential dependency.

- Independent: sibling beads under an umbrella epic.
- Not independent: one bead.

Siblings are what the ready query surfaces together, so a wave of
workers can take them in parallel. Two beads that share a file, or that
wait on each other's outcome, can't go out that way, and filing them
apart buys a merge conflict instead of a speedup. Deciding this at
filing time is cheap. The within-bead parallel nudge in the lifecycle
shell only picks up what gets through.

## Structure

**Multi-task features:** epic + child tasks

```bash
bd create "Feature Name" --type epic -d "Goal and design summary"
bd create "Task 1" --parent <epic-id> -d "What to do, files to touch"
```

**Small features:** standalone tasks

```bash
bd create "Task title" -d "Description"
```

## Task guidelines

- Bite-sized: 2-5 minutes each
- Exact file paths
- Specific commands, not "add validation"
- TDD: test first, implement, commit

## Task description format

```
Goal: What this accomplishes
Files: exact/paths/here
RED: <the decision's executable spec, verbatim>
Steps: 1. Write test 2. Implement 3. Verify
Acceptance: Tests pass, no regressions
```

Three of those lines are read by something downstream, not just by the
person picking the bead up.

**`Files:`** is a comma-separated list of repo-relative paths on one
line. The fan-out detector reads it to decide which ready beads can go
out as a single parallel wave. Two beads are wave-compatible only when
no dependency edge joins them and their `Files:` sets are disjoint. A
bead with no `Files:` line counts as footprint unknown, so it's dropped
from every wave and quietly never gets parallelized. That's why the
line goes on every bead rather than on the ones that look parallel.

**`RED:`** carries the executable spec of the design decision the bead
came from, word for word. Either a behavioral Given-When-Then scenario
or a structural `INVARIANT: ...`. The bead inherits its RED test from
this line, so the RED-to-GREEN middle starts from the text instead of
re-deriving the acceptance criterion. It's optional by construction. A
decision with no testable altitude omits it, and that's expected rather
than a gap.

**`AUTOFAN-EXCLUDE: <reason>`** keeps a bead out of every wave the
detector proposes. Reach for it on attended, upstream, needs-decision
or design work that must not be auto-dispatched. The marker has to lead
the line to count, and `<reason>` is free text.

## After creating

```bash
bd list --parent <epic-id> --limit 0   # show tasks
bd ready --limit 0                     # find unblocked work
```

Both commands truncate by default, and the notice that says so doesn't
survive a pipe. `--limit 0` is the unbounded form, and any invocation
whose output you're about to read as a set needs it.
