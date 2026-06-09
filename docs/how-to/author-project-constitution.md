# Author a project constitution

A **project constitution** is a single file at
`<project>/.claude/project-constitution.md` that pins your project's
tooling profile — the shell envelope, the one package manager, the
language runtime, the canonical build/test/lint commands, and the
patterns the agent must refuse or may bypass. Every loom primitive
(dispatched workers, the enforcement hook, the session-start surfacing)
reads it instead of guessing, which kills the recurring pip-on-uv /
npm-on-pnpm / wrong-test-command class of mistake.

This page is the how-to for **owning** that file over time: creating it,
evolving it as conventions shift, deciding when to widen the bypass
list, and keeping the prose body honest. For the field-by-field schema,
see [reference: project constitution](../reference/project-constitution.md).

## Create it the first time

Don't hand-write the front-matter. Run the capture flow and let
`/audit-project` detect your project's fingerprint:

```text
/audit-project --check=constitution
```

This mode:

1. **Detects** the tooling fingerprint (a `devbox.json` → devbox shell,
   a `pnpm-lock.yaml` → pnpm, a `go.mod` → go, etc.) and renders draft
   front-matter.
2. **Confirms each field with you one at a time** — never a lump-sum
   "accept all". You correct a wrong guess before it lands.
3. **Writes `.claude/project-constitution.md` unstaged** so you review
   the diff and commit it yourself.
4. **Mirrors the decision** into your project's `<wing>/decisions`
   MemPalace drawer and emits the tooling KG triples.

The prose body it writes is a **`[HUMAN AUTHOR]` TODO stub** — the agent
never writes the rationale prose for you (see
[What NOT to put in the prose body](#what-not-to-put-in-the-prose-body)
below). Fill the stubs in yourself, then commit.

!!! note "It's part of brownfield adoption"
    If you're bringing a whole repo up to the loom standard,
    [`/loom-adopt`](adopt-a-brownfield-project.md) runs this capture as
    its final phase (P5) — you don't need to run `--check=constitution`
    separately.

## Author the prose body

Below the YAML front-matter, the file has a Markdown prose body. Its job
is to explain **why** the pinned values are what they are, so the next
person (or agent) reading the constitution understands the choices
rather than just inheriting them. The template ships TODO markers for
four sections:

- **Tooling choices** — one line per front-matter value explaining the
  reasoning. Why *this* package manager. Why the shell wrapper exists
  (or why it's empty). Why a verb in `canonical_commands` is blank.
- **Forbidden patterns** — for each entry in `forbidden:`, name the
  failure mode it guards against. "`pip install` is forbidden because
  this is a uv-only project; any pip invocation is almost certainly a
  worker that mistook the manager."
- **Bypass patterns** — for each entry in `bypass_patterns:`, name the
  legitimate use case that justifies the escape hatch.
- **Lineage** — the beads / decision drawers that informed the choices,
  so the rationale is traceable later.

Write these in your own voice. They are the human-readable half of a
machine-readable file.

## Evolve it as conventions change

The constitution is a living file, not a one-time stamp. When your
project's tooling genuinely changes — you migrate pip → uv, you add a
devbox shell, you settle on a new test command — update the file:

1. **Edit the front-matter** to the new reality, and update the matching
   prose-body line so the rationale stays in sync.
2. **Re-run the capture to diff, not overwrite.** Running
   `/audit-project --check=constitution` again detects the current
   fingerprint and surfaces **per-field drift** against the captured
   file — it never clobbers your prose body. Use it to confirm the
   front-matter matches what the repo actually looks like now.
3. **Commit the change** with the rest of the tooling migration, so the
   constitution and the tooling move together in history.

### The staleness nudge

The enforcement hook
([`constitution-enforce`](../reference/constitution-enforce-hook.md))
watches for the case where you *forgot* step 1. On the first Bash
command of a session, if the constitution's mtime is more than 7 days
older than your newest tooling manifest (`devbox.json`, a `*.lock` file,
`.tool-versions`, `flake.nix`), it emits a one-time, non-blocking nudge:

```text
[constitution-enforce] INFO: .../.claude/project-constitution.md is
~12 days older than pnpm-lock.yaml — the project's tooling may have
drifted from the pinned profile. Consider re-running
`/audit-project --check=constitution` to refresh it.
```

It fires once per session and never blocks anything — it's a reminder to
run the diff, not a gate. When you see it, run
`/audit-project --check=constitution`, reconcile any real drift, and
commit. Touching the constitution (the commit) clears the nudge for
future sessions.

## When to add a bypass pattern

`forbidden:` is a hard wall and `bypass_patterns:` is the only door
through it (apart from the session-scoped `LOOM_CONSTITUTION_SKIP=1`
escape hatch for a one-off command). Add a bypass pattern when **a
legitimate, recurring command keeps tripping a `forbidden:` rule or the
package-manager / runtime guard**, and the friction of bypassing it
by hand every time outweighs the safety the rule buys.

Good reasons to add one:

- A diagnostic idiom that names a forbidden runtime but isn't the
  failure mode you're guarding against — e.g. `python3 -c` for a quick
  JSON parse on a `bash`-runtime project, or `python --version` on a
  project that wraps Python behind a shell envelope.
- A canonical command that legitimately invokes a "competing" manager
  for a narrow purpose the constitution otherwise forbids.

Before adding one, prefer the alternatives:

- **A one-off command?** Use `LOOM_CONSTITUTION_SKIP=1 <command>` for
  that single invocation instead of widening the file's standing
  blast radius.
- **The rule is just wrong?** Fix `forbidden:` (or the
  `package_manager` / `run_prefix` value) rather than papering over it
  with a bypass.

Every bypass pattern is a standing hole in the wall. Keep the list
short, and document each entry's justification in the prose body so a
later reader knows it was a deliberate choice, not drift.

## What NOT to put in the prose body

The constitution's prose body is rationale for the **tooling profile** —
nothing else. Keep these out:

- **Project documentation.** Architecture, API descriptions, how-to
  guides, onboarding steps — those belong in `docs/` (or the repo's
  README), not in the constitution. The constitution is read by hooks
  and workers looking for the tooling profile; bury it under prose and
  the signal is lost.
- **Agent instructions.** Behavioral rules for Claude Code live in
  `CLAUDE.md`. The constitution pins tools; `CLAUDE.md` shapes conduct.
  Don't duplicate one into the other.
- **Agent-authored rationale.** The capture flow leaves the body as a
  `[HUMAN AUTHOR]` stub on purpose — the *human* states why the choices
  were made. Letting an agent confabulate the rationale re-imports the
  guessing the constitution exists to eliminate.
- **Secrets, tokens, or machine-specific paths.** The file is committed
  to the repo and read by every worker. Keep it portable and
  non-sensitive.

If you find yourself writing more than a few short paragraphs of prose,
it probably belongs somewhere else.

## Related

- [reference: project constitution](../reference/project-constitution.md)
  — the full front-matter schema, field types, and worked examples.
- [reference: constitution-enforce hook](../reference/constitution-enforce-hook.md)
  — how the enforcement arm matches commands and emits the staleness
  nudge.
- [Adopt a brownfield project](adopt-a-brownfield-project.md) — where
  the first-time constitution capture fits in the full adoption pass.
