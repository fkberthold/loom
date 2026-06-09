# `workflow.json`

> The per-project workflow CONFIG file. Holds the workflow mode,
> the guest-mode block, and the deploy hint — the small set of
> per-project knobs that loom's hooks, recipes, and `/wrap-up`
> read.

## File location

```
<project>/.claude/workflow.json
```

One per loom-managed project, sitting next to the project's other
`.claude/` config. It is committed to the project's repo (the
guest-mode case is the exception — see [`.guest`](#guest) below).

It is distinct from the per-session `workflow-state.json`: this
file is **configuration** (stable, project-scoped, hand-edited or
slash-command-edited), whereas `workflow-state.json` is
**ephemera** (per-session stage/dispatch bookkeeping, rewritten
constantly by hooks). Don't conflate the two.

The authoritative schema lives in the header comment of
[`lib/workflow-config.sh`](https://github.com/fkberthold/loom/blob/main/lib/workflow-config.sh)
(the `.guest` / `.deploy` accessors) and
[`lib/workflow-mode.sh`](https://github.com/fkberthold/loom/blob/main/lib/workflow-mode.sh)
(the `.mode` resolver). This page is the human-facing projection of
those two libs.

## Schema

| Field | Type | Default | Read by |
|---|---|---|---|
| [`.v`](#v) | integer | `1` | (reserved — version marker) |
| [`.mode`](#mode) | `"full"` \| `"light"` \| `"off"` | `"full"` | `workflow_resolve_mode`, every blocking hook, the recipes, the status line |
| [`.guest`](#guest) | object | absent | `workflow_config_guest_*`, `/loom-guest`, session-startup |
| [`.deploy`](#deploy) | string | absent | `workflow_resolve_deploy`, `loom-print-deploy-hint`, `/wrap-up` §6, `/audit-project` |

All fields are optional. A minimal valid file is just
`{"v": 1, "mode": "full"}`; an entirely-absent `workflow.json`
resolves to all defaults (mode `full`, no guest block, no deploy
hint).

### `.v`

The schema version. Currently always `1`. Reserved as a migration
marker — loom writes it on every self-bootstrapped file so a future
schema change can detect and upgrade old configs. Nothing keys off
its value today; leave it at `1`.

### `.mode`

The workflow mode for the project. One of:

| Value | Behaviour |
|---|---|
| `"full"` | Everything on: hooks fire, the activity recipes run, the status line is populated. |
| `"light"` | Informational only: blocking hooks pass through, the recipe is still available but warns when invoked. |
| `"off"` | Workflow disabled: hooks silent, the recipe refuses, the status line is empty. |

**Resolution priority** (from `workflow_resolve_mode` in
`lib/workflow-mode.sh`):

1. **`CLAUDE_WORKFLOW_OFF=1`** environment variable → `"off"`. The
   hard escape hatch — it overrides the file unconditionally. Any
   other value (unset, `0`, empty) is ignored. See
   [Bypass workflow ceremony](../how-to/bypass-workflow-ceremony.md).
2. The `.mode` field in `<project>/.claude/workflow.json`, when it
   is one of `full` / `light` / `off`. An unrecognised value falls
   through.
3. Default → `"full"`.

### `.guest`

The guest-mode block, written when you activate loom inside a repo
you don't own so loom's artifacts don't bleed into the host's git.
Shape:

```json
"guest": {
  "active": true,
  "bd_mode": "host",
  "repo_key": "someproject-1a2b3c4d"
}
```

| Sub-field | Type | Meaning |
|---|---|---|
| `active` | bool | Whether guest mode is on. `workflow_config_guest_off` removes the whole block rather than setting this `false`, so a present block with `active: true` is the live state. |
| `bd_mode` | `"host"` \| `"personal"` \| `"none"` | Where bead-tracked work lands: the host's own `.beads/`, an external personal workspace under `~/.loom/guests/<repo-key>/.beads/`, or no bd tracking. |
| `repo_key` | string | `<basename>-<sha8>` identifier for the host repo; namespaces the personal bd workspace and guest state. |

Don't hand-edit this block — toggle it through the
[`/loom-guest`](../how-to/guest-mode.md) slash command, which calls
`workflow_config_guest_on` / `workflow_config_guest_off`. Activating
guest mode also adds `.claude/workflow.json` to the host's
`.git/info/exclude` so the `.guest` marker stays invisible to the
host's git.

See the how-to: [Use guest mode](../how-to/guest-mode.md). Lineage:
guest mode was specified in `loom-4re`.

### `.deploy`

A surface-only deploy hint: a shell command that `/wrap-up` surfaces
(but never runs) after a bead is closed, as a reminder of the
follow-up step a project needs. Loom itself sets this to
`./install.sh` (the command that symlinks loom's primitives into
`~/.claude/`); a service repo might set `./scripts/build`,
`make deploy`, `kubectl apply -k ...`, or whatever its deploy step
is.

It is a plain string command, and it is **surface-only**: `/wrap-up`
prints the hint and stops. The user decides when (and whether) to
run it — loom never auto-executes it (`loom-0k0`).

The field has a three-state lifecycle (`absent` / `empty` / `set`)
that `/audit-project` keys off to decide whether to re-prompt a
project that has never made a deploy decision while staying quiet
about a project that explicitly opted out (set `.deploy` to `""`).

The hint is rendered by the
[`loom-print-deploy-hint`](loom-print-deploy-hint.md) wrapper script,
invoked from [`/wrap-up`](https://github.com/fkberthold/loom/blob/main/commands/wrap-up.md)
section 6. See that page for the rendered output and the
why-a-wrapper rationale.

## How to set fields

### Via slash commands (preferred)

- **`.guest`** — `/loom-guest on` / `/loom-guest off` (with
  `--personal-bd` / `--no-bd` variants). Never hand-edit the guest
  block.
- **`.deploy`** — `/audit-project --check=deploy` walks you through
  the deploy hint with the absent-vs-empty distinction preserved
  (so an explicit opt-out is recorded as `""` rather than left
  undecided). Under the hood it calls `workflow_config_deploy_set`.
- **`.mode`** — there is no dedicated command; set it by hand (see
  below) or rely on the `CLAUDE_WORKFLOW_OFF` env override for a
  one-off off-switch.

### Manually

The file is plain JSON. Edit it directly, or call the lib accessors:

```bash
# Set the deploy hint (preserves .mode / .v / .guest)
. lib/workflow-config.sh
workflow_config_deploy_set './install.sh'

# Opt out explicitly (records "empty", suppresses audit re-prompt)
workflow_config_deploy_set ''
```

The `workflow_config_deploy_set` and `workflow_config_guest_on`
helpers self-bootstrap `.claude/workflow.json` (and `.claude/`) when
absent, writing `{"v": 1, "mode": "full"}` first, so you never have
to create the file by hand.

## Full example

A project in `full` mode with a deploy hint and no guest block (the
common case for a repo you own):

```json
{
  "v": 1,
  "mode": "full",
  "deploy": "./install.sh"
}
```

A guest-mode checkout of a repo you don't own, tracking beads in a
personal workspace, with no deploy hint:

```json
{
  "v": 1,
  "mode": "full",
  "guest": {
    "active": true,
    "bd_mode": "personal",
    "repo_key": "acme-widgets-9f8e7d6c"
  }
}
```

## What reads each field

| Field | Consumer | What it does with it |
|---|---|---|
| `.mode` | `workflow_resolve_mode` (`lib/workflow-mode.sh`) | resolves `full`/`light`/`off`; gates every blocking hook, the recipes, and the status line |
| `.guest.active` | `workflow_config_guest_active`, session-startup, `/loom-guest status` | detects whether guest mode is live |
| `.guest.bd_mode` | `/loom-guest`, bd routing | picks the bead workspace (`host`/`personal`/`none`) |
| `.guest.repo_key` | guest state namespacing | keys the personal bd workspace + guest exclude entries |
| `.deploy` | `workflow_resolve_deploy`, [`loom-print-deploy-hint`](loom-print-deploy-hint.md), `/wrap-up` §6 | renders the surface-only deploy hint |
| `.deploy` | `workflow_config_deploy_state`, `/audit-project` | three-state lifecycle drives the audit re-prompt decision |

## Lineage

- `.deploy` field + `loom-print-deploy-hint` shipped in `loom-0k0`
  (2026-05-26); the `absent`/`empty`/`set` lifecycle in `loom-1tq`.
- `.guest` block specified in `loom-4re`.
- `.mode` resolution + `CLAUDE_WORKFLOW_OFF` escape hatch predate
  this page; see [Workflow modes](../explanation/workflow-modes.md)
  for the design rationale.
