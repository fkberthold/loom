# Helper scripts

> A catalogue of the `scripts/` helpers that do NOT have their own
> reference page. Each is a fixture-testable bash wrapper that loom
> primitives (hooks, skills, session-startup) shell out to so the
> deterministic logic lives in one place rather than being re-derived
> in prose.

The helpers below are the ones documented here. Two other `scripts/`
helpers have dedicated pages — cross-link rather than duplicate:

- [`loom-rebase-worktree`](loom-rebase-worktree.md) — WIP-preserving
  rebase of a linked worktree onto a base branch (loom-azt).
- [`loom-worktree-python`](loom-worktree-python.md) — `python3` wrapper
  that forces sys.path to resolve inside the worktree (loom-rsk).

## `loom-doctor` — installed-symlink health check

Health check for loom-installed primitives under `$CLAUDE_HOME`
(`~/.claude` by default). Its primary signal is **dangling symlinks** —
loom-owned symlinks whose target file no longer resolves, the failure
mode that motivated loom-cuk (95 dangling symlinks observed 2026-05-26
after a worktree was cleaned up while it had been the source of the
install).

It walks the loom-owned subdirs (`skills`, `agents`, `commands`,
`hooks`, `lib`, `scripts`), and for each symlink whose target path
contains `loom` (a conservative loom-owned heuristic, so non-loom
symlinks dropped by other tools aren't false-flagged), reports those
that no longer resolve. The healing fix is to re-run `install.sh` from
the main checkout (its prune-then-relink pass removes orphans and
re-creates symlinks against current main).

| Aspect | Value |
|---|---|
| Usage | `loom-doctor` · `loom-doctor --json` · `loom-doctor --claude-home <path>` |
| Exit 0 | no dangling loom-owned symlinks |
| Exit 1 | one or more dangling symlinks reported |
| Exit 2 | wrapper-level error (e.g. `CLAUDE_HOME` not a directory) |

Companion to `install.sh`'s refuse-from-worktree guard (loom-cuk M4):
the guard prevents NEW dangling symlinks; the doctor surfaces ones that
pre-existed the guard or slipped through its bypass.

## `loom-docs-catalogue` — reference-table drift check

Detects drift between the shipped primitives and the
`docs/reference/<category>/index.md` inventory tables (loom-wjuo). The
verbatim `all-<category>.md` dump pages are mkdocs include-globs and stay
complete by construction, but the hand-authored inventory TABLES (which
carry the semantic columns a glob can't derive) drift — a primitive lands
on disk and its row is never added, or a row is pasted twice. This is the
mechanized, gateable engine for the loom-9z1.9 `/audit-project
--check=docs` Check 4 ("inclusion-glob symmetric coverage"); it is wired
into `pre-push-mkdocs-strict.sh` (WARN-only) and pinned by the suite test
`lib/tests/loom-docs-catalogue.test.sh`.

For each of the four categories (skills/commands/subagents/hooks) it
compares the shipped-name set (`skills/*/SKILL.md`, `commands/*.md`,
`agents/*.md`, `hooks/*.sh`) against the first-cell names in the
category's index table, matching boundary-delimited so a name that is a
prefix of another (`loom-upstream-gc` vs `check-loom-upstream`) is never
mis-credited.

| Aspect | Value |
|---|---|
| Usage | `loom-docs-catalogue --check` (`--check` is the default + only mode) |
| Override | `LOOM_DOCS_ROOT=<dir>` points it at a fixture tree (fixture-test shape, mirrors `LOOM_TEST_DIR`) |
| Exit 0 | every shipped primitive listed exactly once across all four index tables |
| Exit 1 | one or more `MISSING` / `DUPLICATE` / `NOINDEX` findings (named per line) |

## `loom-fanout-detect` — parallel-wave proposer (across-bead)

Re-derives bead independence at SELECTION time and proposes a parallel
worker wave (loom-asr, T3 of epic loom-yb5). `bd ready` is popped as a
serial queue and independence is computed only once at bead CREATION, so
central tends to work ready beads one at a time even when several are
trivially parallelizable. This detector re-surfaces that independence so
the session-startup / `/working-a-bead` router can offer
"loom-X/Y/Z are independent — dispatch N parallel workers?" by default.

Two ready beads are wave-compatible **iff**:

1. there is NO dependency edge between them (neither lists the other in
   its `bd show --json` `.dependencies[].id`), AND
2. their declared `Files:` paths are DISJOINT (no shared path).

A bead with **no `Files:` line** is treated as "footprint unknown, not
provably disjoint" and is EXCLUDED from any proposed wave
(conservative-by-default — the loom-asr `Files:` convention). The path
normalizer trims whitespace, strips trailing `(...)` / `[...]`
annotations, and drops a leading `optional ` marker before comparing.

| Aspect | Value |
|---|---|
| Input | `bd ready --json` + `bd show <id> --json` per candidate (`jq`-parsed) |
| Output | one PROPOSED WAVE per line on stdout — space-separated sorted bead IDs, only waves of size ≥ 2; empty stdout means no wave found |
| Exit | always 0 — a DETECTOR, not a gate (loom's nudge-not-block design) |
| Requires | `jq` (degrades silently to "no wave" if absent) |

This owns **across-bead** parallelism. The within-bead test→code split is
owned separately by [`/dispatch-middle`](dispatch-middle.md); the two
compose — the detector proposes a wave of N file-disjoint beads, each of
which runs its middle through dispatch-middle.

## `loom-seam-scan` — claim-phase parallelizability scan

Run at phase A2 of `bead-lifecycle-shell`, right after a bead is claimed
(loom-z3m.5). Scans `bd ready --json` for SIBLING beads (same parent
epic) whose file-path sets are disjoint from the claimed bead's set and
from each other, and emits either `Parallelizable: none.` or
`Parallelizable: N candidates (loom-foo, loom-bar).`.

Bead JSON has no structured `files` field, so it approximates by
regex-extracting path-shaped tokens (matching common code/doc
extensions) from each bead's `design + description + notes` text; two
beads are disjoint when their extracted token sets don't intersect. The
heuristic is deliberately conservative — a bead mentioning no file
extracts an empty set, which is vacuously disjoint with everything; false
positives are absorbed by the agent's own judgment when reading the
candidate list. The value is the ritualized prompt, not a hard gate. It
also writes `parallel_candidates: N` to the project's workflow-state so
the statusline can surface `PAR:N`.

| Aspect | Value |
|---|---|
| Usage | `loom-seam-scan <claimed-bead-id> [project-path]` |
| Test sidedoors | `LOOM_SEAM_SCAN_READY_JSON`, `LOOM_SEAM_SCAN_PROJECT` |
| Exit | 0 always (informational; errors fall through to `Parallelizable: none.`) |
| Requires | `jq` (skips gracefully if absent) |

Note the contrast with `loom-fanout-detect`: seam-scan is a CLAIM-time
sibling scan keyed on regex-extracted path tokens; fanout-detect is a
SELECTION-time wave proposer keyed on explicit `Files:` lines + the
dependency graph.

## State plumbing — `workflow-state` + `statusline.sh`

Two helpers underpin the per-project workflow state surfaced in the
Claude Code TUI:

- **`workflow-state`** — CLI wrapper over the workflow state + config
  libs (`lib/workflow-state.sh`, `lib/workflow-config.sh`). Reads and
  writes `<project>/.claude/workflow-state.json`. Subcommands include
  `get <field>`, `set k=v [k=v …]` (atomic merge), `init`, `path`,
  `mode`, `show`, and the `guest-on` / `guest-off` / `guest-status`
  guest-mode controls. Most commands take an optional trailing project
  PATH (or `--start-dir=PATH` for `set`) to target a project other than
  cwd. `loom-seam-scan` calls it to persist `parallel_candidates`.

- **`statusline.sh`** — the Claude Code `statusLine` command target.
  Reads `<project>/.claude/workflow.json` + `workflow-state.json` from
  the current directory and prints one line:
  `WORKFLOW: <mode> | <activity>:<stage> | bead:<short-id> | <updated-age>`,
  or `WORKFLOW: <mode> | unconfigured` when uninitialized, or nothing
  when outside a beads workspace or when `mode=off`.

## See also

- [Installed files](installed-files.md) — what `install.sh` places in
  `~/.claude/`, including these scripts.
- [loom env vars](loom-env-vars.md) — the bypass/override env variables
  several of these helpers honor.
