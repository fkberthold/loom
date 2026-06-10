# constitution-enforce hook

> PreToolUse hook (Bash + Edit/Write/MultiEdit matcher) that HARD-BLOCKS
> a tool call when it violates the project's pinned tooling profile or a
> declared architectural `invariants:` entry in
> `.claude/project-constitution.md` — with a helpful suggestion. Fails
> open on every condition where it cannot prove a violation.

## Why this exists

Closes loom-8jz, the hard-enforcement arm of the project-constitution
epic (loom-6f8). The epic has three arms:

1. **Surface** (INFO) — session-startup reads the constitution and
   shows a one-line fingerprint; the dispatched-agent smoke battery's
   step 0 `cat`s it into the worker's context. Never blocks.
2. **Author + audit** — `/audit-project` writes the file; the schema
   in `references/project-constitution.schema.json` shapes it.
3. **Enforce** (BLOCK) — *this hook*. The other two surface the
   profile so the agent *knows* the conventions; this one is the
   backstop for when it slips anyway (the recurring pip-on-uv,
   npm-on-pnpm, bare-`python`-on-a-`devbox`-project mistake).

It is the only constitution arm that returns `exit 2`. Every other
constitution touchpoint is a nudge.

## What it checks

On each `PreToolUse(Bash)`:

1. **`LOOM_CONSTITUTION_SKIP=1`** → exit 0 (always bypass; literal-"1"
   only, per the loom-b1l env-gate convention).
2. Tool is not `Bash`, or the command is empty → exit 0.
3. **Walk up** from `$PWD` for `.claude/project-constitution.md`.
   Absent anywhere up-tree → exit 0 **silent** (most projects have no
   constitution; the hook must be invisible there).
4. **`yq` missing** in PATH → exit 0 with a one-line stderr **warn**
   (the hook cannot parse the profile, so it cannot enforce).
5. Slice the YAML **front-matter** (the block between the first two
   `---` fences) into a temp file and parse it with `yq`. A YAML parse
   error, or an absent/empty front-matter block → exit 0 with a stderr
   **warn**.
6. Match the command against the rules below. A positive match →
   **exit 2** with a suggestion. No match → exit 0.

### Rule order

Within each chained sub-command (the command is split on `;`, `&&`,
`||`, `|`, `&`), the rules are applied in this order:

1. **`bypass_patterns`** (allow-list) — checked first. If a bypass
   pattern's words appear as a contiguous run of argv tokens, the
   sub-command is cleared (e.g. `python --version` on a project that
   otherwise forces `devbox run python`).
2. **`forbidden`** — explicit deny phrases. Blocks when the phrase's
   words appear as adjacent argv tokens. Suggestion points at the
   project's package manager when one is pinned.
3. **`package_manager`** — a *competing* manager (`npm` on a `pnpm`
   project, `pip` on a `uv` project, …) invoked with a mutating verb
   (`install`, `add`, `remove`, `ci`, `run`, …) is blocked; the
   suggestion names the canonical manager's install form.
4. **`shell.run_prefix`** — a bare language runtime (`python`,
   `python3`, `node`, …, keyed off `language.runtime`) invoked
   *without* the `run_prefix` is blocked; the suggestion is the
   prefixed form (e.g. `devbox run python …`).

## Anchored-regex discipline

This hook deliberately does **not** substring-match the raw command
string. That is the loom-9ng / loom-oq0s bug class: a textual scan for
`python` fires on `tipping.py`, and a scan for `npm install` fires on a
quoted commit message that merely mentions it.

Instead the command is tokenized with Python's `shlex` (the same
proven approach as `bd-close-capture.sh`), and rules match against
**argv tokens**:

- A **single-word runtime rule** matches only a token that *is* the
  runtime (after stripping a leading path, so `/usr/bin/python` →
  `python`) — never a token that merely ends in `.py` or contains the
  word.
- A **multi-word rule** (`npm install`, any forbidden phrase) matches
  only when its words appear as **adjacent** argv tokens. Because
  `shlex` keeps a quoted argument a single token, a phrase living
  inside `git commit -m "… npm install …"` never produces the adjacent
  `npm` / `install` pair the rule needs, so it does not fire.

## Fails open

The hook only ever blocks on a positive, argv-anchored match against an
explicit rule. Every uncertainty resolves to allow:

| Condition | Result |
|---|---|
| `LOOM_CONSTITUTION_SKIP=1` | exit 0 (bypass) |
| non-Bash tool / empty command | exit 0 silent |
| no constitution file up-tree | exit 0 **silent** |
| `yq` not in PATH | exit 0 + stderr warn |
| malformed / absent front-matter | exit 0 + stderr warn |
| unbalanced quotes in the command | exit 0 (can't tokenize → can't prove) |

## Cache

The parsed profile is memoized in
`$XDG_RUNTIME_DIR/loom-constitution-<sha256-of-path>.json`
(falling back to `$TMPDIR`/`/tmp`), keyed on the constitution file's
**mtime**. The first call after a change re-invokes `yq`; subsequent
calls against the unchanged file read the cache and skip `yq` entirely.
Cache read/write failures are non-fatal — the hook just re-parses.

The cache record base64-encodes every field and joins them with `:`,
which preserves empty fields positionally (a no-shell repo has
`run_prefix: ""`) and flattens the embedded newlines of the
`forbidden:` / `bypass_patterns:` lists onto a single line.

## Bypass

```bash
LOOM_CONSTITUTION_SKIP=1 <command>
```

Only the literal string `1` bypasses; `yes`, `true`, `0`, and empty do
not (loom-b1l convention). Use sparingly — a bypass widens the agent's
blast radius for that one call.

## Tools matched

- `Bash` — tooling-profile rules (`forbidden` / `package_manager` /
  `run_prefix`) plus any Bash-scoped `invariants:` entry.
- `Edit` / `Write` / `MultiEdit` — `invariants:` entries whose
  `applies_to` includes the write-class tool (loom-z3m.14). Composes
  with `edit-write-pwd-guard`.

Not matched: `Read`, `Glob`, `Grep`, `Skill`, etc.

## Example block

```
[constitution-enforce] BLOCKED: this command violates the project constitution.

  command = npm install lodash

  `npm install` uses a package manager other than the project's pinned
  `pnpm`. Use `pnpm install` (or the matching `pnpm` subcommand) instead.

Source: /home/frank/repos/myproj/.claude/project-constitution.md
Bypass (use sparingly): LOOM_CONSTITUTION_SKIP=1 <command>
```

## Files

- Hook: `hooks/constitution-enforce.sh`
- Tests: `lib/tests/constitution-enforce.test.sh` (fixture-driven;
  exercises both a real `yq` and a stub when none is installed)
- Wiring: `settings.snippet.json` (PreToolUse Bash chain, additive)
- Schema it parses: `references/project-constitution.schema.json`
- Field reference: [`project-constitution.md`](project-constitution.md)

## Lineage

- Closes loom-8jz (feature). Parent epic loom-6f8.
- Depends on loom-vin (schema + dogfooded sample + reference doc).
- Design drawer: `drawer_loom_decisions_76ec9140c47ff768735358c0`.
- Anchored-regex discipline inherited from the loom-9ng / loom-oq0s
  substring-false-positive bug class (shared with
  `bd-close-capture.sh`).
