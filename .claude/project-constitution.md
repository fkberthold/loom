---
# Project constitution — loom (workflow-infrastructure repo)
#
# Loom is mostly markdown (skills, agent definitions, slash commands)
# + bash (hooks, helpers, scripts) + JSON (settings snippets). There
# is no application runtime, no package manager, and no project shell
# wrapper. Tests are bash fixtures under lib/tests/.
#
# Field reference: docs/reference/project-constitution.md.
# JSON Schema: references/project-constitution.schema.json.

shell:
  enter: ""
  run_prefix: ""

package_manager: none

language:
  runtime: bash
  version: ""

forbidden:
  - "pip install"
  - "poetry install"
  - "uv pip install"
  - "npm install"
  - "pnpm install"
  - "yarn install"

canonical_commands:
  build: ""
  test: "script/test"
  lint: "shellcheck hooks/*.sh lib/*.sh scripts/*"
  gen: ""
  dev: ""
  # No deploy step — loom installs via ./install.sh (symlinks), which
  # is surfaced as the workflow.json deploy HINT, not an automated
  # deploy. Empty here per the canonical_commands.deploy convention.
  deploy: ""

bypass_patterns:
  - "python3 -c"
  - "python3 -m json.tool"

# Project-specific ARCHITECTURAL invariants (loom-z3m.14). Enforced by
# hooks/constitution-enforce.sh across Bash AND the write-class tools
# (Edit/Write/MultiEdit) — distinct from the Bash-only tooling rules
# above. Each entry: {id, applies_to:[Bash|Edit|Write|MultiEdit],
# deny_pattern (regex), message}. The deny_pattern is matched (re.search)
# against the tool's relevant input (Bash → .command; write-class →
# .file_path + body). A match → the hook exits 2 with the message.
#
# Loom has NO live architectural invariant of its own — it is a
# markdown+bash+JSON package with no application runtime to constrain —
# so the section is left commented as a SHAPE EXAMPLE. Uncomment + adapt
# the entry below in a downstream project to enforce a real invariant
# (e.g. "only touch the world through MCP, never direct file I/O").
#
# invariants:
#   - id: no-direct-file-io
#     applies_to:
#       - Write
#       - Edit
#       - MultiEdit
#     deny_pattern: "\\bopen\\("
#     message: "Touch the world only through MCP — direct file I/O (open(...)) is forbidden by this project's architectural invariant. Use the mcp_fs client instead."
---

# loom — project constitution

> TODO: One-paragraph statement of what this constitution is for and
> who reads it. Ground it in loom's role as the workflow-
> infrastructure repo and the meta-project status (CLAUDE.md already
> says "not a code project" — restate here for the constitution's
> readers).

## Tooling choices

TODO: Briefly explain *why* the front-matter values are what they are.
Example structure:

- **Shell**: TODO — loom has no shell wrapper; why that's fine for a
  bash + markdown + JSON repo.
- **Package manager**: TODO — `none` because loom has no application
  runtime. The repo ships symlink-installable primitives, not a
  buildable artifact.
- **Language**: TODO — `bash` is the executable surface; markdown is
  the largest surface but isn't a runtime.
- **Canonical commands**: TODO — point at `lib/tests/*.test.sh` for
  the fixture suite, `shellcheck` for the lint pass, and explain why
  `build`, `gen`, `dev` are empty.

## Forbidden patterns

TODO: For each entry in `forbidden:`, name the failure mode it
guards against. Example: package-manager invocations are forbidden
because loom has no application code that would benefit from
managed dependencies — any `pip install` or `npm install` invocation
is almost certainly a mistaken-cwd dispatched worker.

## Bypass patterns

TODO: For each entry in `bypass_patterns:`, name the legitimate use
case. Example: `python3 -c` is occasionally invoked by loom's own
hooks for JSON parsing and path canonicalization; legitimate even
though `python3` is not a project runtime.

## Lineage

TODO: Beads / decision drawers that informed these choices. Example:
"Locked in loom-vin (decision drawer
`drawer_loom_decisions_76ec9140c47ff768735358c0`) as part of the
loom-6f8 Constitution epic. See `docs/reference/project-constitution.md`
for the field reference."
