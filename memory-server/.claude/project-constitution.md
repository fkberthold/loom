---
# Project constitution — YAML front-matter (memory-server carve-out)
#
# This is a NESTED constitution, scoped to the memory-server/
# subdirectory of the loom repo. Loom's top-level constitution
# (../../.claude/project-constitution.md) is bash-only,
# package_manager: none, and forbids pip/npm/etc — loom itself has no
# application runtime. memory-server/ is the one exception: a real
# Python service (the Dolt-backed replacement for MemPalace, loom-40ec)
# that needs pip-installed dependencies (pymysql, pytest, ruff).
#
# hooks/constitution-enforce.sh walks UP from $PWD looking for the
# NEAREST .claude/project-constitution.md — so any command run with
# cwd inside memory-server/ finds THIS file first and the loom-level
# forbidden-pip-install rule never applies. See the "Nested
# constitution shadowing" section in the body below for the verification
# record.
#
# See docs/reference/project-constitution.md (in the loom repo) for the
# full field reference, and references/project-constitution.schema.json
# for the JSON Schema.

shell:
  # No shell wrapper (no devbox/nix/poetry-shell) — a plain venv at
  # .venv/ is activated by sourcing it directly.
  enter: "source .venv/bin/activate"
  # Canonical commands below reference .venv/bin/<tool> directly by
  # relative path, so no separate non-interactive prefix is needed.
  run_prefix: ""

package_manager: pip

language:
  runtime: python
  version: "3.12"

# Bash command patterns the agent must NEVER run in memory-server/.
# Locks in pip as the ONE package manager for this subdirectory — a
# competing python manager (poetry/uv) would create a second
# dependency-resolution source of truth alongside .venv's pip-installed
# packages. pip itself is intentionally NOT forbidden here (unlike the
# parent loom constitution) — this subdirectory's whole reason for
# existing is to run pip.
forbidden:
  - "poetry install"
  - "uv pip install"
  - "npm install"
  - "pnpm install"
  - "yarn install"

canonical_commands:
  # No compiled build step for a python service.
  build: ""
  test: ".venv/bin/pytest tests/ -v"
  lint: ".venv/bin/ruff check ."
  # No code-generation step (no Goa/protobuf/etc in this subdirectory).
  gen: ""
  # This subdirectory's "dev" verb IS the server bring-up script — the
  # deliverable is a running dolt sql-server, not a watch/reload loop.
  dev: "scripts/start-server.sh"
  # No automated deploy yet — production Dolt-server deployment is a
  # later bead in the loom-40ec epic, not this one (loom-40ec.3 is
  # schema + local bring-up only).
  deploy: ""

# Bash patterns that bypass constitution enforcement. Mirrors the
# parent loom constitution's ad-hoc-diagnostics allowance; harmless
# here since run_prefix is empty (the bare-runtime-without-prefix rule
# only fires when run_prefix is non-empty), but kept for consistency
# and as a forward guard if run_prefix ever becomes non-empty.
bypass_patterns:
  - "python3 -c"
---

# memory-server — project constitution

> This constitution governs the `memory-server/` subdirectory of the
> loom repo: the shared, concurrent, Dolt-backed memory server that is
> replacing MemPalace (epic loom-40ec). It is a real Python service
> with its own dependency set, carved out from loom's top-level
> bash-only, `package_manager: none` constitution via this NESTED
> file. `hooks/constitution-enforce.sh`'s walk-up-from-$PWD lookup
> means any command run with cwd inside `memory-server/` reads THIS
> file instead of the parent — no bypass env var required.

## Tooling choices

- **Shell**: no wrapper (no devbox/nix/poetry-shell). A plain venv at
  `memory-server/.venv/` is the isolation boundary. `shell.enter`
  documents the interactive `source .venv/bin/activate`; `run_prefix`
  is empty because every canonical command below already spells out
  `.venv/bin/<tool>` by relative path, so no additional wrapping is
  needed for non-interactive (CI/hook/script) invocations.
- **Package manager**: `pip`, chosen because the SPIKE-1 benchmark
  prototype (`~/loom-spike1-benchmark/`, throwaway scratch, not
  committed) already validated the Dolt + `pymysql` +
  `sentence-transformers` stack with plain pip into a venv — continuing
  in pip avoids re-deriving a working dependency set under a different
  manager for no benefit. No lockfile tooling (uv/poetry) is justified
  yet at this service's size.
- **Language**: Python 3.12 (the version already present on this
  machine's `python3`, matching what the SPIKE-1 prototype used).
- **Canonical commands**: `test` and `lint` point at the venv's
  `pytest`/`ruff` directly. `dev` points at
  `scripts/start-server.sh` — for this subdirectory, "run the dev
  loop" and "bring up the server" are the same action, since the
  deliverable of loom-40ec.3 is a locally-running `dolt sql-server`,
  not a watch/reload command. `build`, `gen`, and `deploy` are all
  empty: no compile step, no code generation, and production
  deployment is explicitly out of scope for this bead (later beads in
  the loom-40ec epic own it).

## Forbidden patterns

- `poetry install`, `uv pip install` — a second Python
  dependency-resolution tool running against the same `.venv`/
  `requirements.txt` would silently diverge from what `pip install`
  last put there. pip is the single source of truth for this
  subdirectory's dependencies.
- `npm install`, `pnpm install`, `yarn install` — memory-server has no
  Node/JS component; these would only ever be a mistake (e.g. an agent
  defaulting to a Node habit) rather than a legitimate need.
- `pip install` itself is deliberately **not** forbidden here (unlike
  loom's top-level constitution) — this subdirectory exists precisely
  to run pip-managed Python dependencies.

## Bypass patterns

- `python3 -c` — ad-hoc one-off diagnostics (checking a package
  version, a quick REPL-style sanity check). Carried over from the
  parent constitution for consistency; currently a no-op in practice
  since `run_prefix` is empty (the constitution-enforce hook's
  bare-runtime rule only engages when `run_prefix` is non-empty), but
  kept as a forward guard.

## Nested-constitution shadowing — verification record (loom-40ec.3)

Verified 2026-07-09 by running `cd memory-server && .venv/bin/pip
install <small-package>` with this file in place: the command was
**allowed**, confirming `hooks/constitution-enforce.sh`'s walk-up-from-
`$PWD` logic picks up THIS nested file (which does not forbid `pip
install`) rather than the parent loom constitution (which does), when
the shell's cwd resolves inside `memory-server/`. No
`LOOM_CONSTITUTION_SKIP` bypass was used or needed. See the bead's
closing report for the exact command and hook output.

## Lineage

- Parent epic: **loom-40ec** (Shared Dolt memory server for loom,
  replace MemPalace).
- This bead: **loom-40ec.3** (Production schema + dolt sql-server
  bring-up).
- Locked design: MemPalace drawer
  `drawer_loom_decisions_521e654693797b4f169b4cbd` — D5 (substrate =
  Dolt sql-server), D6 (no branch-per-session), D7 (kg_triples
  relational schema).
- Sibling constitution: `../../.claude/project-constitution.md` (loom
  top-level, bash-only, `package_manager: none`).
