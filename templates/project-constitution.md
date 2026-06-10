---
# Project constitution — YAML front-matter
#
# This block is the authoritative profile for this project's tooling.
# Dispatched workers, hooks, and skills read it to stay aligned with
# the chosen shell, package manager, language runtime, canonical
# commands, forbidden patterns, and bypass patterns. See
# docs/reference/project-constitution.md (in the loom repo) for the
# full field reference, and references/project-constitution.schema.json
# for the JSON Schema if your editor supports YAML validation.
#
# Replace every <angle-bracketed> placeholder. Leave keys as empty
# strings ("") when they don't apply — don't delete keys.

shell:
  # Command an interactive operator runs once to enter the project
  # shell (e.g. "devbox shell", "nix-shell", "poetry shell").
  # Empty string when the project has no shell wrapper.
  enter: "<devbox shell | nix-shell | poetry shell | '' >"
  # Prefix for non-interactive invocations of commands (CI, hooks,
  # scripts). Examples: "devbox run", "poetry run", "nix-shell --run".
  # Empty string when no prefix is needed.
  run_prefix: "<devbox run | poetry run | '' >"

# The single package manager that owns dependency resolution.
# One of: pnpm | npm | yarn | uv | poetry | pip | go | cargo | none
package_manager: <pnpm | npm | yarn | uv | poetry | pip | go | cargo | none>

language:
  # One of: python | go | rust | node | bash | polyglot | unknown
  runtime: <python | go | rust | node | bash | polyglot | unknown>
  # Semver-ish pin. May be empty for bash / polyglot / unknown.
  version: "<3.13 | 1.24 | 20.11.0 | '' >"

# Bash command patterns the agent must NEVER run in this project.
# Typically used to lock in the package_manager choice (e.g. on a
# uv-only project, forbid `pip install` and `poetry install`).
forbidden:
  - "<e.g. npm install>"
  - "<e.g. pip install>"

canonical_commands:
  # The agreed command for each workflow verb. Skills, hooks, and
  # dispatched workers read these instead of guessing. Empty string
  # means the verb is not applicable to this project.
  build: "<e.g. pnpm build | go build ./... | '' >"
  test: "<e.g. pnpm test | pytest | go test ./... | '' >"
  lint: "<e.g. pnpm lint | ruff check | golangci-lint run | '' >"
  gen: "<e.g. ./scripts/gen | '' >"
  dev: "<e.g. pnpm dev | uvicorn main:app --reload | '' >"
  # Deploy command. Default impl is `script/deploy` under the
  # GitHub-style script/ convention. This is the canonical home for
  # the deploy step and DEPRECATES the legacy `workflow.json .deploy`
  # hint — migrate any existing `workflow.json .deploy` value here.
  # Empty string when the project has no deploy step.
  deploy: "<e.g. script/deploy | make deploy | '' >"

# Bash patterns that bypass constitution enforcement (escape hatches
# for legitimate edge cases). Use sparingly.
bypass_patterns:
  - "<e.g. python3 -c (one-off diagnostics on a uv project)>"

# Project-specific ARCHITECTURAL invariants. Unlike the tooling rules
# above (forbidden/package_manager/run_prefix, which are Bash-only and
# argv-shaped), invariants are enforced across Bash AND the write-class
# tools (Edit/Write/MultiEdit) via a regex. Each entry:
#   {id, applies_to:[Bash|Edit|Write|MultiEdit], deny_pattern, message}
# deny_pattern is a regex (re.search) matched against the tool's relevant
# input (Bash → .command; write-class → .file_path + body). A match makes
# the constitution-enforce hook exit 2 with the message; non-matches and
# any uncertainty fail open. Leave commented out when the project has no
# architectural invariant to enforce. Example (uncomment + adapt):
#
# invariants:
#   - id: <e.g. no-direct-file-io>
#     applies_to:
#       - Write
#       - Edit
#       - MultiEdit
#     deny_pattern: "<e.g. \\bopen\\( >"
#     message: "<e.g. Touch the world only through MCP — direct file I/O is forbidden.>"
---

# <Project name> — project constitution

> TODO: One-paragraph statement of what this constitution is for and
> who reads it. Reference the parent project's mission so the file
> grounds itself rather than floating.

## Tooling choices

TODO: Briefly explain *why* the front-matter values are what they are.
Example structure:

- **Shell**: TODO — why this shell wrapper (or none)?
- **Package manager**: TODO — why this manager? Lock-in story?
- **Language**: TODO — runtime + version pin rationale.
- **Canonical commands**: TODO — which scripts/Makefile targets these
  point at, and why those over alternatives.

## Forbidden patterns

TODO: For each entry in `forbidden:`, name the failure mode it
guards against. Example: "`npm install` would create a parallel
node_modules tree and break the pnpm lockfile."

## Bypass patterns

TODO: For each entry in `bypass_patterns:`, name the legitimate use
case. Example: "ad-hoc `python3 -c ...` for diagnostics; we accept
the lookup-precedence risk for one-liners that don't import project
modules."

## Lineage

TODO: Beads / decision drawers that informed these choices. Example:
"Locked in `<your-project>-N1` (decision drawer
`drawer_<wing>_decisions_<hash>`)."
