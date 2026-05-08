# Use guest mode

To work loom-flavored discipline in a repo you do **not** own — without
leaving loom artifacts in the host's tree or commit history — turn on
guest mode for that repo.

## When to use guest mode

Pick guest mode in either of these scenarios:

- **You're a contributor, not the owner.** The host repo belongs to
  another team or another project. Adding `.claude/workflow.json`,
  `docs/` scaffolds, or per-loom-tag `bd remember` lines to the host's
  history would be social pollution — your tooling is your business,
  not the host's.
- **You're temporarily engaged in someone else's project.** A short
  spike, a PR-sized contribution, a one-off bug investigation. You
  want loom's recipes, capture, and KG plumbing locally; the host
  repo should look exactly as it did before you arrived.

Do **not** use guest mode in your own repos. There the loom artifacts
are *meant* to be committed, and the guardrails will get in your way.

## Precondition

- You're inside a git working tree (`git rev-parse --show-toplevel`
  succeeds).
- The repo is not a loom-managed project of your own. (If
  `.claude/workflow.json` already exists with non-guest content, talk
  to the owner before activating; guest mode rewrites that file.)
- You have decided how `bd` should behave in this repo. See
  [Activate guest mode](#activate-guest-mode) below for the prompt.

## Activate guest mode

1. **From the repo root, run the slash command.**

   ```text
   /loom-guest on
   ```

   The slash command delegates to `scripts/loom-guest on` (or
   `~/.claude/scripts/loom-guest on` if you installed loom globally —
   both resolve to the same script).

2. **Answer the bd-mode prompt if it fires.** If the host has no
   `.beads/` directory, the script refuses to default and asks you to
   pick:

   | Flag | Meaning |
   |---|---|
   | `--personal-bd` | External personal workspace at `~/.loom/guests/<repo-key>/.beads/`. Gitignored from the host. Choose this if you want bd-tracked work that doesn't bleed into the host's repo. |
   | `--no-bd` | Skip bd integration entirely. Recipes that require a bead won't have one to operate on. |

   Re-run with the chosen flag:

   ```bash
   /loom-guest on --personal-bd
   # or
   /loom-guest on --no-bd
   ```

   If the host **does** carry its own `.beads/`, `on` defaults
   silently to `bd_mode=host`. Your `bd` commands then operate on
   the host's tracker (you're a contributor); `bd remember` is
   refused because it would commit a one-liner to the host's
   `issues.jsonl`. To override and use a personal external workspace
   anyway, pass `--personal-bd`.

3. **Confirm activation.**

   ```text
   /loom-guest status
   ```

   The output should report `ACTIVE`, list the resolved `bd_mode` and
   `repo_key`, confirm the `info/exclude` block is `present`, and
   render the live suppression list.

## What changes when guest mode is on

Guest mode flips a `.guest` block inside `.claude/workflow.json` and
appends a `BEGIN LOOM` / `END LOOM` stanza to `.git/info/exclude`. The
exclude file is per-clone and never committed, so the host's
committed `.gitignore` is untouched.

| File | Status with guest mode | Visible to host's git? |
|---|---|---|
| `.claude/workflow.json` | Present in your tree (carries the `.guest` marker) | No — listed in `.git/info/exclude` |
| `.claude/settings.json` | Present in your tree if loom installs one | No — listed in `.git/info/exclude` |
| `.git/info/exclude` | Has a `BEGIN LOOM` block appended | Per-clone; not part of any commit |
| Host source / tests | Untouched | Yes — committed normally |

The `.guest` block records `{active: true, bd_mode, repo_key}`. The
`repo_key` is `<basename>-<sha8-of-toplevel-path>` so two clones of
the same repo at different paths get different keys (and therefore
different personal-bd workspaces, if you chose that mode).

## What's refused when guest mode is on

Loom guardrails proactively decline operations that would write into
the host tree:

- **`/docs-scaffold` refuses.** It would create `docs/` plus
  `mkdocs.yml`, `requirements.txt`, and a GH Pages workflow in the
  host. Refused outright; no per-file approval prompt.
- **`/audit-project` AUTOFIX in-tree writes skip per-item with a
  warn.** The audit still reports drift; it just doesn't auto-write
  the fix into the host tree.
- **`bd remember` is refused when `bd_mode=host`.** A `bd remember`
  call would append a line to the host's `.beads/issues.jsonl` and
  commit it. Use a MemPalace drawer in your own wing instead.

What does **not** change:

- Activity recipes (`bugfix-a-bead`, `feature-a-bead`, etc.) still
  run.
- MemPalace capture (drawers, KG triples, diary) still runs — those
  live in your palace, not the host repo.
- Code-review skills, brainstorming skills, and parallel-dispatch
  skills work normally.
- The actual work files you write for the host (source, tests,
  docs the host asked for) commit normally — those aren't loom
  artifacts.

## Deactivate guest mode

To restore the host repo to its pre-guest state:

```text
/loom-guest off
```

Both the `.guest` marker and the `BEGIN LOOM` / `END LOOM` block in
`.git/info/exclude` are removed. The underlying lib helpers
(`workflow_config_guest_off`, `info_exclude_remove`) are idempotent,
so re-running `off` against an already-inactive repo is a safe no-op.

After `off`, run `/loom-guest status` again to confirm `INACTIVE`.

## Troubleshooting

**The statusline doesn't show `[GUEST]`.** Statusline integration is
tracked separately (loom-b8z) and was pending at the time of this
guide. If your version of loom hasn't shipped that yet, rely on
`/loom-guest status` to verify activation. Once the statusline
integration lands, an `ACTIVE` state without a `[GUEST]` segment is
a bug — re-run activation and capture `loom-guest status` output for
the report.

**`info/exclude` block isn't picking up.** Check that
`/loom-guest status` reports the block as `present`, then verify
git agrees:

```bash
git check-ignore -v .claude/workflow.json
```

The output should cite `.git/info/exclude:N` for the matching line.
If it cites `.gitignore` or returns nothing, the block didn't
install — re-run `/loom-guest on` and inspect
`.git/info/exclude` directly for the `BEGIN LOOM` marker.

**`/loom-guest on` errors with "not inside a git repo".** You're
running from a non-git directory. `cd` into the host repo's working
tree and retry. The script refuses to operate outside a git working
tree by design.

**The host has no `.beads/` and the script refuses to pick a
default.** Intentional. There is no safe default when the host
doesn't already have bd: defaulting to `host` would create
`.beads/` in the host tree, defaulting to `personal` would silently
create an external workspace you didn't ask for, and defaulting to
`none` would silently disable bd integration. Pass `--personal-bd`
or `--no-bd` to make the choice explicit.

**A clone of the same repo at a different path doesn't share my
personal-bd workspace.** Working as designed. The `repo_key` mixes
the repo basename with an 8-char SHA of the toplevel path, so each
clone gets its own external workspace. Copy or symlink the
workspace under `~/.loom/guests/` if you want to share state
across clones.

**`bd remember` fails in `bd_mode=host` and the error is unclear.**
Refusal is intentional — the guardrail exists precisely so a stray
`bd remember` doesn't sneak a one-liner into the host's commit
history. File the memory in a MemPalace drawer in your own wing
(see the design drawer reference below for the loom-n7x rationale).

## Critical

- **Guest mode is a guardrail, not a sandbox.** It refuses footguns
  but doesn't physically prevent `git add .claude/`. The protection
  is "loom won't *help* you pollute the host tree."
- **Activation is reversible.** `off` cleans up the marker and the
  exclude block. The host repo returns to its pre-guest state.
- **Don't activate guest mode in your own repos.** It's specifically
  for repos where you're a contributor, not the owner.

## Related

- For the slash command's full surface area (subcommands and flags),
  see [reference: slash commands](../reference/slash-commands/index.md).
- For why each guardrail blocks the operations it does, see
  [explanation: workflow modes](../explanation/workflow-modes.md).
- For escape hatches when a guardrail blocks legitimate work, see
  [Bypass workflow ceremony](./bypass-workflow-ceremony.md).
- The locked design lives in MemPalace as drawer
  `drawer_loom_decisions_12d7f8163e8855be037a007c` in the
  `loom/decisions` wing.
