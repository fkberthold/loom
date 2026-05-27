# DOCS-SCAFFOLD-FIXME sentinels

> A broken-link convention that makes unreplaced placeholders from
> `/docs-scaffold` fail loudly at `mkdocs build --strict` time —
> one targeted error per unreplaced section, with each section
> named in the error message.

## Why this exists

The `/docs-scaffold` skill copies template files into the
consumer's tree with placeholder prose where the project's actual
content belongs ("Replace this step with the project's actual
installation command…"). Without a forcing function, that prose
can ship verbatim to a published site.

In May 2026 the downstream `mforth` project did exactly that — its
`docs/how-to/install.md` shipped with the verbatim "Replace this
step…" placeholder text and the Go / Python / Node / Bash example
menu intact. The fix landed downstream as a single rewrite commit;
the upstream *mechanism* — something that prevents the same failure
mode from recurring in the next project to scaffold — needed to
land in loom itself. This page documents that mechanism.

## The convention

Each placeholder block in `templates/diataxis/` carries a sentinel
line directly above it:

```markdown
[!! DOCS-SCAFFOLD-FIXME: replace this section before publish !!](docs-scaffold-fixme-<token>.md)
```

The link **target** is a relative path that doesn't resolve to any
file on the site. mkdocs detects this at build time and emits a
WARNING (the default severity for `not_found` markdown links).
Running `mkdocs build --strict` promotes the warning to a fatal
error, so the build refuses to publish until every sentinel is
replaced.

The link **text** carries the human-readable instruction. The
`!! !!` flanks supply visual emphasis, and `DOCS-SCAFFOLD-FIXME`
is greppable — consumers can locate every unreplaced sentinel with
one shell line:

```bash
grep -r DOCS-SCAFFOLD-FIXME docs/
```

## Sentinel inventory

Four sentinels ship in three template files:

| Token | Scaffolded file | What needs replacing |
|---|---|---|
| `docs-scaffold-fixme-install-cmd` | `docs/how-to/install.md` | Step 2 — the project's actual install command (and removing the language-menu code block). |
| `docs-scaffold-fixme-install-verify` | `docs/how-to/install.md` | Step 3 — the post-install verification invocation. |
| `docs-scaffold-fixme-quickstart-invocation` | `docs/tutorials/getting-started.md` | Step 2 — the smallest meaningful invocation of the project. |
| `docs-scaffold-fixme-mental-model` | `docs/explanation/mental-model.md` | The entire page — replace the scaffold's structure-only prose with the project's actual load-bearing idea. |

`/docs-scaffold` writes these into the consumer's tree at scaffold
time. The consumer's job is to replace each sentinel — both the
sentinel line and the placeholder prose below it — with real
content before publishing.

## How to replace a sentinel

1. **Find them.** `grep -rn DOCS-SCAFFOLD-FIXME docs/` lists every
   surviving sentinel and the line it sits on.
2. **Open each file.** The sentinel sits directly above the
   placeholder section it guards.
3. **Replace both layers.** Delete the sentinel line AND the
   placeholder prose below it; write the project's actual content
   in their place.
4. **Re-grep.** Confirm the sentinel is gone.
5. **Build.** Run `mkdocs build --strict` locally to confirm the
   build is now clean — or push and watch the Deploy docs CI run.

## What `--strict` will tell you

With sentinels intact, `mkdocs build --strict` fails with one
WARNING-promoted-to-ERROR per unreplaced sentinel. The error
message names the specific token so you know exactly which
placeholder block to address:

```
ERROR    -  Doc file 'how-to/install.md' contains a link
            '...(docs-scaffold-fixme-install-cmd.md)', but the target
            'how-to/docs-scaffold-fixme-install-cmd.md' is not found
            among documentation files.
```

The token suffix (`install-cmd`, `install-verify`,
`quickstart-invocation`, `mental-model`) maps 1:1 to the rows in
the inventory above.

## Why this shape

Three alternatives were considered before settling on the
broken-link mechanism — see drawer
`drawer_loom_decisions_56bfe66ecf7d9db3a3c555b0` in the MemPalace
`loom/decisions` wing for the full design lock:

- **A literal grep-only marker** (e.g. plain `!!UNREPLACED!!`
  text). Greppable, but doesn't fail the build — consumers can
  still publish through it.
- **A dedicated `/docs-doctor` slash command.** New surface area
  for a problem `grep -r` already solves in one line.
- **A custom mkdocs Python plugin.** New runtime dependency for a
  forcing function mkdocs already provides via `--strict`.

The broken-link approach reuses mkdocs' existing link validation
(specifically, the `not_found` severity on `validation.links` —
default `warn`, promoted by `--strict` to fatal). **Zero new
infrastructure, zero new runtime dependency, zero new commands.**
The failure mode is one every mkdocs user already understands.

The original design lock spec'd the target token without a `.md`
suffix; live mkdocs 1.6 routes extension-less unresolved targets
through `unrecognized_links` (default `info`, not promoted by
`--strict`) rather than `not_found` (default `warn`, promoted).
Appending `.md` to each token's link target moves it into the
`not_found` bucket and keeps the contract zero-config for
consumers. The token slug itself is unchanged — `grep -r
DOCS-SCAFFOLD-FIXME docs/` still finds every sentinel, and the
mkdocs error message still names the unsuffixed token via
substring.

## Related pages

- [Slash commands — full text](slash-commands/all-commands.md) — search for
  `/docs-scaffold` for the M6 "Next steps" block that surfaces these
  sentinels at scaffold time.
- [Skills — full text](skills/all-skills.md) — search for `docs-scaffold`
  for the skill the command invokes.
- [Decision tables](decision-tables.md) — the broader convention index.
