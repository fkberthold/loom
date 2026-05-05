# bd CLI

The `bd` (beads) issue tracker is an upstream tool. The list below
covers the surface loom interacts with via hooks, skills, and the
recipe family. For the full bd reference, run `bd --help`, `bd <cmd>
--help`, or `bd prime`, and consult the upstream beads documentation.

## Daily commands

```bash
bd ready                    # unblocked work, ranked
bd ready -n 20              # show more
bd show <id>                # full issue details + dependencies
bd update <id> --claim      # take ownership (fires bd-claim-research hook)
bd close <id> --reason="x"  # close (BLOCKED by bd-close-capture hook by default)
bd close <id1> <id2> ...    # batch close
bd dolt push                # push beads state to Dolt remote
bd dolt pull                # pull beads state from Dolt remote
bd dolt remote list --json  # list configured remotes (use to guard push for solo workspaces — loom-hsb)
```

`bd dolt push` exits 1 with "remote 'origin' not found" on solo
workspaces (no Dolt remote configured); that error is benign because
issues are still versioned locally in `.beads/`. The session-close
protocol guards the push with `bd dolt remote list --json` to avoid
treating it as a failure.

## Bypass and escape hatches

```bash
bd close <id> --force                  # bypass close-capture hook
BD_CLOSE_FORCE=1 bd close <id>         # also bypasses
bd defer <id> --until=2026-07-01       # postpone without blocking
bd defer <id> --until=tomorrow         # accepts: +1h, tomorrow, next monday, ISO date
bd supersede <id> --with=<new-id>      # mark replaced by newer
```

Project-wide bypass (workflow mode in
`<project>/.claude/workflow.json`):

```bash
echo '{"v":1, "mode":"off"}'   > .claude/workflow.json   # disable workflow ceremony entirely
echo '{"v":1, "mode":"light"}' > .claude/workflow.json   # informational; close-capture never blocks
CLAUDE_WORKFLOW_OFF=1 claude                              # session-scoped escape hatch
```

## Memory and lineage

```bash
bd remember "one-line tribal fact"     # auto-injects at next bd prime
bd memories <keyword>                  # search tribal facts
bd memories                            # list all
```

Boundary: `bd remember` for one-line project tribal facts that should
auto-inject; MemPalace drawer for multi-paragraph decisions with
options-considered context. See
[Decision tables](decision-tables.md#bd-remember-vs-mempalace-drawer).

## Lifecycle hygiene

```bash
bd stale --status in_progress --days 7  # zombie tasks
bd orphans --details                    # commits referencing open issues
bd orphans --fix                        # batch close shipped work
bd preflight                            # PR-readiness checks
bd lint                                 # ensure beads have required sections
bd compact --days 30                    # squash old Dolt commits
```

## Dependencies and structure

```bash
bd dep add <issue> <depends-on>                       # generic dep
bd dep add <issue> <parent> --type=parent-child
bd dep add <issue> <blocker> --type=blocks
bd blocked                                            # all blocked issues
bd graph                                              # visualise DAG (if installed)
```

## Workflows (advanced)

```bash
bd formula list                       # available templates
bd mol pour <name>                    # spawn persistent molecule from formula
bd mol spawn <name> --wisp            # ephemeral instance
bd mol distill <epic> --as "Name"     # extract reusable proto from ad-hoc epic
```

## Hooks (one-time install per project)

```bash
bd hooks install        # pre-commit, post-merge, pre-push, post-checkout, prepare-commit-msg
bd hooks list           # verify
bd hooks uninstall      # remove
```

!!! warning "Run an absorbing commit immediately after install"

    The bd pre-commit hook re-exports `.beads/issues.jsonl` on the
    next `git commit` in the workspace, regardless of subject. If
    you go straight from `bd hooks install` to a logical commit,
    the export churn (often +6 to +50 lines of `issues.jsonl`)
    rides along silently — two-things-in-one-commit against intent.

    Mitigation: right after `bd hooks install`, run an empty bd-only
    absorbing commit before any logical work commit:

    ```bash
    bd hooks install
    git add .beads/issues.jsonl
    git commit -m "bd: post-install export sync"
    # now proceed with logical commits cleanly
    ```

    Observed in loom-b6o tla-puzzles trial 2026-05-04 (cardinality
    commit `891d2ae` silently picked up a +6-line `issues.jsonl`
    re-export). Tracked as loom-cka. Out-of-scope follow-up
    (defer-on-mixed-stage detection in bd itself) is loom-cka's
    follow-up bead.

## Health checks (embedded mode)

`bd doctor` returns a note rather than running checks in embedded
mode (loom's default setup).

```bash
ls -la .beads/embeddeddolt/    # confirm DB exists
bd version                     # check version
bd init --force                # reinitialize if needed
```

## Loom-specific surface

| bd surface | Loom integration |
|---|---|
| `bd update <id> --claim` | Triggers `bd-claim-research.sh` PreToolUse hook |
| `bd close <id>` | Triggers `bd-close-capture.sh` PreToolUse hook (blocks in `full` unless bypass) |
| `bd prime` | Loaded at session start; `session-startup` skill consumes its output |
| `bd remember` / `bd memories` | Cited from `bug-family-researcher` subagent recipe and decision tables |

See [Hooks](hooks/index.md) for hook details.
