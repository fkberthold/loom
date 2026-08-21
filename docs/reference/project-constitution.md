# Project constitution

> Per-project tooling profile that lives at
> `<project>/.claude/project-constitution.md`. Front-matter pins the
> shell, package manager, language runtime, canonical commands,
> forbidden patterns, and bypass patterns; prose body explains the
> rationale.

## Why this exists

Foundation for loom-6f8 (the Constitution epic). Dispatched workers,
hooks, and skills repeatedly guess at a project's tooling profile —
"is this a pnpm or npm repo?", "does `python3` resolve to the
project's interpreter?", "what's the test command?". Each guess is
a recurring source of leaks (pip-on-uv, npm-on-pnpm, wrong python
shadowing the worktree). The constitution captures the agreed
answers once, in a file every primitive can read.

Three child beads build on this schema:

- **loom-1iz** — capture flow (extend `/audit-project` to detect
  and offer to fill the constitution).
- **loom-8jz** — PreToolUse enforcement hook
  (`hooks/constitution-enforce.sh`) that refuses Bash calls matching
  `forbidden:` patterns.
- **loom-ld4** — surfacing at session start, in subagent dispatch
  briefs, and in debugging recipes.

## File location and shape

Each project gets one file at `<project>/.claude/project-constitution.md`.
The file is committed to the project's repo. It has two halves:

1. **YAML front-matter** (the schema below). Machine-read.
2. **Markdown prose body**. Human-read rationale, lineage, escape-
   hatch documentation. No fixed shape beyond TODO markers in the
   template.

The fillable template is `templates/project-constitution.md` in
loom. Loom's own dogfooded copy is `.claude/project-constitution.md`
in this repo — `none` package_manager, `bash` runtime, empty
`shell.enter` (no project shell wrapper).

## Front-matter fields

### `shell`

The project shell envelope. Two sub-fields, both required:

| Field | Type | Meaning |
|---|---|---|
| `shell.enter` | string | Command an interactive operator runs once to enter the project shell. Empty string when there is no wrapper. |
| `shell.run_prefix` | string | Prefix for non-interactive invocations (CI, hooks, scripts). Empty string when no prefix is needed. |

**Example (devbox project):**

```yaml
shell:
  enter: "devbox shell"
  run_prefix: "devbox run"
```

**Example (no shell wrapper):**

```yaml
shell:
  enter: ""
  run_prefix: ""
```

### `package_manager`

The single package manager that owns dependency resolution. Mixing
managers (pnpm + npm, uv + pip) is the canonical failure this
field guards against.

Allowed values: `pnpm`, `npm`, `yarn`, `uv`, `poetry`, `pip`, `go`,
`cargo`, `none`.

**Example (uv-only Python project):**

```yaml
package_manager: uv
```

**Example (loom):**

```yaml
package_manager: none
```

### `language`

Primary language runtime. Two sub-fields, both required:

| Field | Type | Allowed values |
|---|---|---|
| `language.runtime` | string | `python`, `go`, `rust`, `node`, `bash`, `polyglot`, `unknown` |
| `language.version` | string | Semver-ish pin (`"3.13"`, `"1.24"`, `"20.11.0"`) — may be empty for `bash` / `polyglot` / `unknown` |

**Example:**

```yaml
language:
  runtime: python
  version: "3.13"
```

### `wing`

Optional. The project's MemPalace wing, which is the wing every loom
site files decision drawers into and searches for citation drift.

This key is rung 3 of a four-rung chain that lives in one file,
`lib/loom-wing-resolve.sh`. Every site that needs a wing reads it from
there, so no two sites can disagree about the same project:

| Rung | Source |
|---|---|
| 1 | An explicit `--wing` flag |
| 2 | `<root>/mempalace.yaml`, key `wing:` |
| 3 | This key |
| 4 | `basename $root` |

Rung 2 sits above this one because `mempalace.yaml` is MemPalace's own
descriptor and already carries the wing next to its rooms. A project
that has one should declare the wing there and leave this key out,
rather than state the same name in two files.

Set this key when the wing name differs from the directory name and the
project has no `mempalace.yaml`. Leave it out when the directory name
already matches, which is the common case. Rung 4 takes the directory
name verbatim, with no `_`/`-` substitution and no case-folding, so
`liza_base` and `golden-path` both resolve correctly on their own.

The bd id prefix is not a rung, and the reason is worth stating because
it was one twice. It is the worse guess: across the 8 repos under
`~/repos` that carry a bd tracker, the prefix and the directory name
disagree three times, and the directory name is right all three times.
`dreamer-engine` tracks beads as `dream`, `sharedvoice` as `sv`, and
neither `dream` nor `sv` is a wing that holds anything. That put it
under the directory name (loom-pc3x). Rung 4 always answers, though,
because a root is always in hand, so a rung under rung 4 can never fire.
loom-6fyj dropped it, along with the flag that fed it.

A caller that wants the prefix anyway calls
`loom_wing_from_bd_prefix` and joins the answer to its own candidate
set. That is the shape `bd-close-capture.sh` needs, since it holds
a bead id and no project root and never wanted a ranked answer.

**Example:**

```yaml
wing: tla_puzzles
```

The gap this fills is a silent one. Before the chain existed,
`~/.claude/scripts/loom-audit-resolve` and
`~/.claude/scripts/loom-mine-history` each took the directory basename
on their own, and both resolved `tla-puzzles` to a wing of that name. No wing of that name exists. The project's 932
drawers live in `tla_puzzles`. Nothing errored, and a mine run would
have filed 144 new drawers into the empty spelling and split the
project's memory in two (loom-kpke).

### `forbidden`

List of bash command patterns the agent must never run. Patterns
match as substrings of the bash invocation. Typically used to lock
in the `package_manager` choice (e.g. forbid `npm install` on a
pnpm-only project) or to forbid known-destructive operations.

**Example:**

```yaml
forbidden:
  - "npm install"
  - "yarn add"
  - "pip install"
```

Empty list when the project has no patterns to forbid.

### `canonical_commands`

The agreed command for each workflow verb. Five sub-fields, all
required (use empty string when the verb is not applicable):

| Field | Meaning |
|---|---|
| `canonical_commands.build` | Build command. |
| `canonical_commands.test` | Test command (unit suite at minimum). |
| `canonical_commands.lint` | Lint command. |
| `canonical_commands.gen` | Code-generation command (e.g. Goa). |
| `canonical_commands.dev` | Dev-server / watch command. |

**Example (Go service):**

```yaml
canonical_commands:
  build: "./scripts/build"
  test: "./scripts/test"
  lint: "./scripts/lint"
  gen: "./scripts/gen"
  dev: "./scripts/server"
```

**Example (loom):**

```yaml
canonical_commands:
  build: ""
  test: "bash lib/tests/*.test.sh"
  lint: "shellcheck hooks/*.sh lib/*.sh scripts/*"
  gen: ""
  dev: ""
```

### `bypass_patterns`

List of bash command patterns that bypass constitution enforcement.
Escape hatches for legitimate edge cases. Use sparingly — every
bypass widens the agent's blast radius.

**Example:**

```yaml
bypass_patterns:
  - "python3 -c"
  - "python3 -m json.tool"
```

Empty list when there are no escape hatches.

## Worked example: devbox + pnpm + Python project

A hypothetical project that uses devbox for the shell envelope,
pnpm for Node dependencies, and Python 3.13 for application code
fills the schema like this:

```yaml
shell:
  enter: "devbox shell"
  run_prefix: "devbox run"
package_manager: pnpm
language:
  runtime: python
  version: "3.13"
forbidden:
  - "npm install"
  - "yarn add"
  - "pip install"
  - "poetry install"
canonical_commands:
  build: "devbox run pnpm build"
  test: "devbox run pytest"
  lint: "devbox run ruff check ."
  gen: ""
  dev: "devbox run pnpm dev"
bypass_patterns:
  - "python3 -c"
```

The agent reads this and knows: enter via `devbox shell`, prefix
non-interactive commands with `devbox run`, refuse `pip install`
even if a worker is sure it wants pip, allow ad-hoc `python3 -c`
diagnostics.

## JSON Schema

Editor tooling can validate the front-matter against
`references/project-constitution.schema.json` (draft 2020-12).
Most YAML LSPs accept a `# yaml-language-server: $schema=...`
header pointing at the schema URL.

## Cross-references

- **Template:** `templates/project-constitution.md`
- **JSON Schema:** `references/project-constitution.schema.json`
- **Dogfood:** `.claude/project-constitution.md` (loom's own)
- **Parent epic:** loom-6f8
- **Foundation bead:** loom-vin
- **Child beads:** loom-1iz (capture flow), loom-8jz (enforcement
  hook), loom-ld4 (surfacing)
- **Provenance drawer:** `drawer_loom_decisions_76ec9140c47ff768735358c0`
