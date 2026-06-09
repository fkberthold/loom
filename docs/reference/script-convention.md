# The `script/` convention

> The fixed set of normalized entry-point scripts every loom-managed
> repo carries — loom's adaptation of GitHub's "Scripts to Rule Them
> All". A contributor, an automated agent, or CI can run `script/setup`
> and `script/test` against *any* loom-managed project without learning
> its bespoke tooling.

The convention has four moving parts, each documented below:

1. The **8 canonical scripts** — the fixed verb set.
2. **Directory naming** — `script/` singular by default, `scripts/`
   accepted.
3. **No-op exit semantics** — what a present-but-inapplicable or
   present-but-unwired script does.
4. The **resolution contract** — how a loom primitive turns a verb `X`
   into a command to run.

A fifth section covers the **layering** that ties `script/` to the
project constitution and `workflow.json`.

## The 8 canonical scripts

```
script/
├── bootstrap   ← one-time machine prerequisites (toolchains, system pkgs)
├── setup       ← make a fresh checkout ready to run (install deps)
├── update      ← update an existing checkout (re-sync deps, migrate, regen)
├── server      ← start the app locally for development
├── test        ← run the fast unit suite (the canonical test command)
├── lint        ← run static analysis / style checks
├── cibuild     ← the full CI build + test pass (superset of test)
└── deploy      ← ship to the run target (image push, publish, release)
```

The set is GitHub's "Scripts to Rule Them All" faithful — the same eight
verbs, the same intent per verb. Convention pipeline: `bootstrap` →
`setup` → (`update` on later pulls) → `server` / `test` / `lint` during
development → `cibuild` in CI → `deploy` to ship.

| Script | Responsibility |
|---|---|
| `bootstrap` | One-time machine prerequisites a fresh checkout needs before `setup` can run: language toolchains, system packages, container runtimes, credentials. Idempotent. |
| `setup` | Install the project's own dependencies (after `bootstrap` provided the toolchain) and perform first-run wiring: fetch deps, build local binaries, create config, seed a dev DB. Idempotent. |
| `update` | `setup` for an *existing* checkout: re-sync deps to current lockfile versions, run pending migrations, regenerate code. Run after pulling new commits. Idempotent. |
| `server` | Start the app locally in development mode (hot-reload where available). The textbook N/A case — a library or pure-CLI project has nothing to serve. |
| `test` | Run the fast unit suite (the cheap, no-external-deps tier). The canonical test command the activity recipes and `/audit-project` invoke. |
| `lint` | Run linters and formatters in check mode (no mutation). Fails non-zero on any finding so CI and pre-commit gates can rely on it. |
| `cibuild` | The full CI build + test pass — the superset of `test` plus integration tests, the release build, coverage, and slow checks excluded from the fast local `test`. The single entry point CI invokes. |
| `deploy` | Ship a built artifact to where it runs: push an image, apply manifests, publish a package, run a release pipeline. The home for what loom's `workflow.json` `.deploy` hint (loom-0k0) surfaces at wrap-up time. |

### `build` and `gen` are constitution strings, not skeleton files

The skeleton ships **eight** files — `build` and `gen` are deliberately
NOT among them. They live instead as
[`canonical_commands`](project-constitution.md#canonical_commands)
*strings* in the project constitution. They are real workflow verbs, but
they do not get a dedicated `script/build` / `script/gen` stub: many
projects fold build into `cibuild` and have no code-generation step at
all, so a default stub would be noise more often than signal. A project
that wants `script/build` or `script/gen` is free to add one — the
[resolution contract](#the-resolution-contract) below will pick it up —
but the canonical skeleton does not ship them.

`dev` is a near-synonym of `server`: `canonical_commands.dev` and
`script/server` name the same "run the app locally" verb. There is no
`script/dev`; `dev` resolves through `canonical_commands.dev` (or maps
to `server`).

## Directory naming

The directory is **`script/` (singular)** by convention — the GitHub
"Scripts to Rule Them All" spelling, and the loom default for a new
project.

The convention is **graceful about existing repos**: the loom recognizer
also accepts **`scripts/` (plural)** for projects that already use that
name. Adoption never forces a rename — a repo with a populated
`scripts/` directory keeps it. Recognizers and the resolver match
**either** directory; when both happen to exist, the singular `script/`
wins (it is the convention's default home).

New projects should prefer the singular `script/`.

## No-op exit semantics

The scripts are **always present and uniform** — every loom-managed repo
carries all eight, so a caller never has to first discover *which*
scripts a project has. Uniformity is the point: `script/test` exists in
every repo, even one with no tests yet.

That uniformity forces a question for any script that is present but does
not actually do its verb. The convention answers it with two distinct
no-op forms, and **a no-op ALWAYS echoes a clear message** explaining
which form it is:

| Situation | Behaviour | Exit code |
|---|---|---|
| **Genuinely not-applicable** — the verb does not apply to this project type (e.g. `script/server` in a library: there is nothing to serve). | Echo an `… : N/A for this project type` message. | **`exit 0`** |
| **Unimplemented gap** — the verb applies but is not wired yet (e.g. `script/test` before any tests are wired). | Echo a `… : not implemented for this project — wire it up or mark N/A` message **on stderr**. | **`exit non-zero` (code `2`)** |

The distinction is load-bearing: an N/A script reporting success (`0`)
is *correct* — there is legitimately nothing to do — whereas an unwired
script reporting success would let a green `script/test` falsely mean
"tests ran and passed" when in fact no tests ran.

### Skeleton stubs ship in the non-zero "not implemented" form

The canonical skeleton (`templates/scripts/`) ships every script as an
**unedited stub in the unimplemented-gap form** — message on stderr,
`exit 2`. **Fresh adoption fails LOUD until the adopter wires each
script.** This is deliberate: a half-wired project must fail noisily
rather than let placeholders masquerade as a working pipeline.

The N/A downgrade to `exit 0` is the **adopter's edit, never the shipped
default**. Shipping `exit 0` by default would let an unconfigured project
look healthy; shipping `exit 2` forces a conscious choice per script —
wire it up, or explicitly declare it N/A:

```bash
# Wire it up — replace the stub body with the real command:
bash lib/tests/*.test.sh

# …or mark it genuinely N/A — downgrade the body to:
echo "server: N/A for this project type"
exit 0
```

The stub keeps **stdout clean** (the "not implemented" message goes to
stderr only), so any adopter or CI step parsing a script's stdout is not
polluted by placeholder text. Each stub also carries **per-type comment
hints** — a commented line each for Go, Python, Node, and bash — that the
adopter uncomments and adapts. See
[`templates/scripts/`](installed-files.md) and its `README.md` for the
skeleton's full shape; the invariant is pinned by
`lib/tests/scripts-template.test.sh`.

## The resolution contract

When a loom primitive needs to run workflow verb `X` against a project,
it resolves `X` to a command through a strict three-rung priority order,
implemented by `loom_resolve_command` in
[`lib/loom-script-resolve.sh`](https://github.com/fkberthold/loom/blob/main/lib/loom-script-resolve.sh):

1. **`script/X` exists and is executable → run it.** Its **exit code is
   authoritative** and is surfaced verbatim — the resolver never masks
   it. Under the [no-op semantics](#no-op-exit-semantics) above, a `2`
   means "not-wired stub" and an `exit 0` from an N/A script means
   "genuinely not applicable, nothing to do". (`scripts/X` is accepted
   as the fallback directory; `script/` wins when both exist.)
2. **Else `canonical_commands.X` is set in the constitution → run that
   string** through the shell. Its exit code is likewise authoritative.
3. **Else → emit a warning to stderr and return non-zero. Never a silent
   pass.** A missing command is a *refusal*, not a success — the
   no-false-green guard. The resolver never quietly returns `0` for a
   verb no one defined.

The first two rungs both run a command and propagate its real exit code;
the third is the explicit refusal that keeps an undefined verb from
looking like a passing one. The contract carries no external-tool
dependency — the constitution front-matter is parsed with pure `awk`
(jq-free and yq-free), since loom has no application runtime to lean on.

## Layering: two layers plus one state file

The convention sits in a small layered model — **two command layers plus
one state file** — so that "what command runs `X`" and "where workflow
state lives" never get conflated:

| Layer | What it is | Role |
|---|---|---|
| `script/X` | An **executable** script on disk | The **executable impl layer** — the actual command. |
| `canonical_commands.X` (in [`project-constitution.md`](project-constitution.md)) | A **declarative** string | The **declarative pointer**. `script/X` is the *default impl* of `canonical_commands.X`. |
| [`workflow.json`](workflow-json.md) | Per-project workflow **state/config** | Pure workflow state (mode, guest block). **Holds no commands.** |

The relationship between the first two layers is the heart of the
[resolution contract](#the-resolution-contract): **`script/X` is the
default implementation of `canonical_commands.X`.** When the script is
present, it *is* the command; when it is absent, the
`canonical_commands.X` string stands in; when both are absent, the
resolver warns rather than passing.

`workflow.json` is the odd one out on purpose: it carries **no
commands**. It is pure workflow state — the mode, the guest-mode block —
read by hooks and recipes, never a place a runnable command lives.

### The `.deploy` migration

`deploy` is the verb that makes the layering concrete. It **migrated
out** of `workflow.json` and **into** `canonical_commands.deploy` in the
constitution. The rationale is exactly the separation above: a deploy
*command* is a command, so it belongs in the command layer
(`canonical_commands`), not in the pure-state file (`workflow.json`).
`script/deploy` is then the default executable impl of
`canonical_commands.deploy`, and loom's `/wrap-up` surfaces it as a hint
(never auto-running it — loom-0k0).

## Cross-references

- **Skeleton:** `templates/scripts/` (the eight canonical stubs +
  `README.md`)
- **Resolver:** `lib/loom-script-resolve.sh` (`loom_resolve_command`)
- **Skeleton test:** `lib/tests/scripts-template.test.sh`
- **Constitution field reference:** [Project constitution](project-constitution.md)
  (`canonical_commands`)
- **Workflow state file:** [`workflow.json` schema](workflow-json.md)
  (the `.deploy` migration source)
- **Recognizer + scaffold:** `/audit-project` recognizes a project's
  `script/` directory and offers to scaffold the skeleton when missing
- **Design:** the `loom/decisions` `script/`-convention drawer (loom-adm)
- **Epic:** loom-oxs (standardize the `script/` convention for
  loom-managed repos)
