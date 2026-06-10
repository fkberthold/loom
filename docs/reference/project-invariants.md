# Project architectural invariants

> The `invariants:` section of `.claude/project-constitution.md` lets a
> project enforce its own ARCHITECTURAL rules — "only touch the world
> through MCP, never direct file I/O", "no raw network egress outside the
> gateway" — across `Bash` **and** the write-class tools (`Edit`,
> `Write`, `MultiEdit`). The `constitution-enforce` hook reads them and
> hard-blocks (`exit 2`) a tool call that violates one. Fails open on any
> uncertainty.

## Why this is separate from the tooling rules

The constitution's original enforcement arm — `forbidden`,
`package_manager`, `shell.run_prefix` — guards **tooling** choices
(pip-on-uv, npm-on-pnpm, bare-`python` on a `devbox` project). Those
rules are **argv-shaped** (they match parsed command tokens) and so apply
to `Bash` only; a file write has no argv.

Architectural invariants are a different shape. They are **regex-shaped**
project rules, and the thing they most often need to constrain is what
gets *written into source files* — which is an `Edit`/`Write`/`MultiEdit`
event, not a `Bash` one. So the `invariants:` section:

- extends the **same** hook (`hooks/constitution-enforce.sh`) rather than
  introducing a new mechanism, and
- fires across **all four** tools (`Bash`, `Edit`, `Write`, `MultiEdit`),
  with each invariant declaring which of them it applies to.

Tooling rules stay Bash-only; invariants opt in per-tool.

## Shape

`invariants:` is a YAML sequence of maps in the constitution's
front-matter. Each entry has four keys:

```yaml
invariants:
  - id: no-direct-file-io
    applies_to:
      - Write
      - Edit
      - MultiEdit
    deny_pattern: "\\bopen\\("
    message: "Touch the world only through MCP — direct file I/O (open(...)) is forbidden. Use the mcp_fs client instead."
  - id: no-curl-egress
    applies_to:
      - Bash
    deny_pattern: "\\bcurl\\b"
    message: "Network egress must go through the MCP gateway — raw curl is forbidden."
```

| Key | Type | Meaning |
|---|---|---|
| `id` | string | Short stable identifier, shown in the block message so the operator can find the rule. |
| `applies_to` | array of `Bash` / `Edit` / `Write` / `MultiEdit` | Which tool calls this invariant is checked against. An invariant only fires for a tool listed here. |
| `deny_pattern` | string (regex) | A Python-flavored regex (`re.search`). A search hit blocks the call. |
| `message` | string | Human-readable explanation shown on a block. State the rule **and** the sanctioned alternative. |

The section is **optional** — a constitution with no `invariants:` key
enforces nothing new (the tooling rules behave exactly as before). The
JSON Schema (`references/project-constitution.schema.json`) defines the
shape with `additionalProperties: false` per entry and all four keys
`required`.

## What each tool's input is matched against

`deny_pattern` is matched (with `re.search`) against the **relevant
input** for the tool that fired:

| Tool | Input the deny_pattern sees |
|---|---|
| `Bash` | `.command` (the shell command string) |
| `Write` | `.file_path` + `.content` (newline-joined) |
| `Edit` | `.file_path` + `.new_string` |
| `MultiEdit` | `.file_path` + every `.edits[].new_string` |

So a `deny_pattern` of `\bopen\(` on a `Write`-scoped invariant fires when
the file body being written contains `open(` — and the path is part of
the scanned text too, so a pattern can also key off the target file.

Note this is a **regex `re.search`**, not the argv-token matching the
tooling rules use. Invariants are project-authored and may legitimately
need to match substrings of a file body, so they intentionally do not
inherit the anchored-argv discipline of the `forbidden:` rules.

## Behavior

On each `PreToolUse(Bash | Edit | Write | MultiEdit)`:

1. **`LOOM_CONSTITUTION_SKIP=1`** → exit 0 (always bypass; literal-`1`
   only, per the loom-b1l env-gate convention).
2. Tool is not one of the four → exit 0.
3. **Walk up** from `$PWD` for `.claude/project-constitution.md`. Absent
   → exit 0 **silent**.
4. **`yq` missing** / **malformed front-matter** → exit 0 (with a stderr
   warn). The invariant check cannot run, so it fails open.
5. For each invariant whose `applies_to` includes the current tool, test
   its `deny_pattern` against the tool's input. The first match → **exit
   2** with that invariant's `message`. No match → fall through.
6. For `Edit`/`Write`/`MultiEdit` the invariant check is the *only* arm —
   having cleared it, the hook exits 0. For `Bash` the hook continues to
   the tooling rules (`forbidden`/`package_manager`/`run_prefix`).

### Example block

```
[constitution-enforce] BLOCKED: this Write call violates a project architectural invariant (no-direct-file-io).

  Touch the world only through MCP — direct file I/O (open(...)) is forbidden. Use the mcp_fs client instead.

Source: /home/frank/repos/myproj/.claude/project-constitution.md
Bypass (use sparingly): LOOM_CONSTITUTION_SKIP=1 <command>
```

## Fails open

Like the rest of the constitution-enforce hook, the invariant arm only
ever blocks on a positive regex match against a declared invariant. Every
uncertainty resolves to allow:

| Condition | Result |
|---|---|
| `LOOM_CONSTITUTION_SKIP=1` | exit 0 (bypass) |
| tool not in `Bash`/`Edit`/`Write`/`MultiEdit` | exit 0 |
| no constitution file up-tree | exit 0 **silent** |
| no `invariants:` section | exit 0 (nothing to enforce) |
| `yq` not in PATH / malformed front-matter | exit 0 + stderr warn |
| an invariant's `deny_pattern` is not a compilable regex | that invariant is skipped (no match) |

## Caching

The parsed invariants ride the **same** mtime-keyed cache as the tooling
profile (a sixth field in the cache record, base64-encoded). The first
call after a constitution change re-invokes `yq` to re-extract them;
subsequent calls against the unchanged file read the cache and skip `yq`
entirely. Cache failures are non-fatal — the hook just re-parses.

## Bypass

```bash
LOOM_CONSTITUTION_SKIP=1 <command>
```

Only the literal string `1` bypasses; `yes`, `true`, `0`, and empty do
not (loom-b1l convention). The bypass clears **both** the invariant arm
and the tooling-rules arm. Use sparingly.

## Authoring

Add or evolve the `invariants:` section by hand in
`.claude/project-constitution.md`, or via
`/audit-project --check=constitution`. Leave the section commented out
(as loom's own dogfooded constitution does) when the project has no
architectural invariant to enforce — loom itself is a markdown + bash +
JSON package with no application runtime to constrain, so it ships the
section as a commented shape example.

## Files

- Hook: `hooks/constitution-enforce.sh` (the same hook that enforces the
  tooling rules)
- Tests: `lib/tests/constitution-invariants.test.sh`
- Wiring: `settings.snippet.json` (registered under the `Bash` chain
  **and** the `Edit|Write|MultiEdit` chain)
- Schema: `references/project-constitution.schema.json` (`invariants`
  property)
- Field reference for the rest of the file:
  [`project-constitution.md`](project-constitution.md)
- Sibling hook reference:
  [`constitution-enforce-hook.md`](constitution-enforce-hook.md)

## Lineage

- loom-z3m.14 — extends the constitution (loom-6f8 / loom-8jz) with the
  `invariants:` arm rather than building a standalone mechanism.
