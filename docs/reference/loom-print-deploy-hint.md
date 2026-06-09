# `loom-print-deploy-hint`

> Wrapper script that prints a project's deploy hint — the
> `.deploy` command from [`workflow.json`](workflow-json.md) — as a
> surface-only reminder. Renders nothing when no hint is set.
> Always exits 0.

## What it does

`loom-print-deploy-hint` reads the project's
`.claude/workflow.json` `.deploy` field (via
`workflow_resolve_deploy`) and:

- If `.deploy` resolves to a **non-empty string**, prints:

  ```
  Next step (project deploy): <command>
  ```

- If `.deploy` is **absent, null, empty, or `workflow.json` is
  missing**, prints **nothing** and skips silently.

It **always exits 0** — whether the hint fired, was skipped, or the
resolver lib could not be found. This is deliberate: it runs from
`/wrap-up` after the bead has already been closed, and a non-zero
exit there must never make the wrap-up appear to fail. It is
surface-only — it prints the command but never runs it. The user
decides when (and whether) to execute the deploy step.

## Sample output

**`.deploy` set** (e.g. loom itself, with `"deploy": "./install.sh"`):

```console
$ loom-print-deploy-hint
Next step (project deploy): ./install.sh
```

**`.deploy` absent / empty / no `workflow.json`:**

```console
$ loom-print-deploy-hint
$
```

(no output; exit 0).

## Why a wrapper script, not a sourced lib snippet

The resolver lib `lib/workflow-config.sh` detects its own path with
`BASH_SOURCE[0]` (`__WFC_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`).
`BASH_SOURCE` is a **bash-only** array — it does not exist in zsh,
which is the shell Claude Code's Bash tool runs under. If `/wrap-up`
tried to `source` the lib directly, the path detection would break
in the calling shell.

A bash-shebanged wrapper script (`#!/usr/bin/env bash`) isolates
that constraint: the wrapper always runs under bash regardless of
the invoking shell, so `BASH_SOURCE` is available where the lib
needs it, and `/wrap-up` just invokes the script as an executable.
The bash-only-ness of the lib is contained inside the wrapper rather
than leaking out to every caller.

## Where it is invoked

[`/wrap-up`](https://github.com/fkberthold/loom/blob/main/commands/wrap-up.md)
**section 6 — "Surface project deploy hint (if configured)"** —
runs it after the bead is closed:

```bash
# Print "Next step (project deploy): <cmd>" if .deploy is set;
# silent no-op otherwise. Always exits 0; safe in any project.
~/.claude/scripts/loom-print-deploy-hint
```

`/wrap-up` surfaces the hint and **stops** — it does not auto-run
the command. Configuring a project means adding a `.deploy` string
to its [`workflow.json`](workflow-json.md); see that page for the
schema and the three-state lifecycle.

This generic surface-only shape replaced an earlier section that
detect-and-ran loom's own `install.sh` by literal header match,
which leaked loom-specific guidance into unrelated projects
(`loom-0k0`, 2026-05-26).

## Lib resolution

The script resolves its sibling lib **self-relative** to its own
directory, not by an absolute path:

```bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lib="$script_dir/../lib/workflow-config.sh"
[ -f "$lib" ] || exit 0   # lib missing (script moved?) → silent skip
```

So the worktree's copy of the script always sources the worktree's
lib, and the installed copy always sources the installed lib — both
symlink chains stay consistent, and a moved/orphaned script degrades
to a silent exit-0 rather than an error.

## Installed location

```
~/.claude/scripts/loom-print-deploy-hint
```

Symlinked there by `install.sh` from the repo's
`scripts/loom-print-deploy-hint`, alongside the other `loom-*`
helper scripts.

## Lineage

- Shipped in `loom-0k0` (2026-05-26) together with the
  [`.deploy`](workflow-json.md#deploy) schema field.
- Three-state `.deploy` lifecycle (`absent`/`empty`/`set`) added in
  `loom-1tq`.
- Sibling helper-script reference pages:
  [`loom-rebase-worktree`](loom-rebase-worktree.md),
  [`loom-worktree-python`](loom-worktree-python.md).
