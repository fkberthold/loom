---
name: docs-scaffold
description: Scaffold a Diataxis-shaped MkDocs Material docs/ tree into the current loom-managed project by copying templates/diataxis/ with variable substitution, writing only the files the project doesn't already have. Refuses against non-loom-managed projects and against projects carrying the docs/.no-diataxis opt-out marker. Manual-only — never auto-suggested by session-startup or any activity recipe; only fires when the user invokes `/docs-scaffold`.
---

# Docs-Scaffold — Diataxis Skeleton Copier

This skill is the driver behind the `/docs-scaffold` slash command.
It copies the canonical Diataxis skeleton from `templates/diataxis/`
(the loom repo) into the **current loom-managed project**, customising
it with project-local variables and surfacing only the include-markdown
catalog pages for primitives the project actually has.

The discipline this skill codifies, restated:
**loom recommends Diataxis; the project decides.** The scaffold is
opt-in (manual slash command), non-destructive (it writes the files the
project is missing and never overwrites one it has), and explicitly
opt-out-respecting (a `docs/.no-diataxis` marker terminates the skill
with an explanation). Loom ships the bones; the project owns the voice.

Invocation: explicit only. `/docs-scaffold` fires this skill. The
slash command and this skill both carry `disable-model-invocation:
true` in spirit — the user has to ask. The `project-onboarder`
Diataxis-shape check (loom-km8.3) reports the gap and names this
skill as the fix, but never invokes.

## When to use

- The user types `/docs-scaffold` in a loom-managed project.
- The user asks to "scaffold the docs," "set up Diataxis," or "put a
  MkDocs skeleton in this repo," and the project is loom-managed.
- A new loom-managed project just finished `/audit-project` and the
  user wants the recommended docs surface.

## Skip when

- The project is not loom-managed (no `.claude/workflow.json`).
  Refuse and tell the user to run `/audit-project` first.
- `docs/.no-diataxis` is present at the project root. The project has
  explicitly opted out; respect the marker and refuse with explanation.
- `<root>/docs/` is generated (gitignored or written by a build
  script — detected by `lib/docs-generated.sh`). Refuse with
  `[SCAFFOLD SKIP][GENERATED]`; scaffolding into a generated tree
  silently breaks on the next build cycle. (loom-3hb.)
- The user wants a non-MkDocs SSG (Hugo, Docusaurus, Jekyll). Out of
  scope for v1; the opt-out marker is the supported escape hatch.
- The user wants to scaffold a single page rather than the whole tree.
  This skill is whole-tree only; targeted edits are out of scope.

## Flags

- `--root <path>` — project root to scaffold into (default: current
  working directory's git root, or cwd if not in a git repo). All
  filesystem checks (`.claude/workflow.json` detection, primitive
  scan, `docs/.no-diataxis` opt-out, existing-docs inventory),
  `git config` lookups for variable defaults, and the M6 file copy
  resolve against this root. Lets the skill scaffold any
  loom-managed project, not just the one matching cwd. Mirrors the
  precedence chain used by `/audit-project`.

## The Sequence

### M1 — Detect target

Resolve the target project root in this precedence order:

1. Explicit `--root <path>` flag (absolute or relative; resolved to
   absolute).
2. Current working directory's git root (`git -C $PWD rev-parse
   --show-toplevel`).
3. Current working directory itself (fallback when not in a git repo).

Call this `<root>` for the rest of the sequence. Every subsequent
filesystem path is rooted at `<root>` (e.g. `<root>/docs/`,
`<root>/.claude/workflow.json`).

Verify the project is loom-managed by checking for
`<root>/.claude/workflow.json`.

If `<root>/.claude/workflow.json` is absent: **refuse** with this message:

> This project is not loom-managed (no `.claude/workflow.json`).
> Run `/audit-project` first to onboard the workflow infrastructure,
> then `/docs-scaffold` to add the docs surface.

Stop. Do not proceed.

### M2 — Detect primitives

Scan `<root>` for these primitive directories:

| Directory | Reference catalog page |
|---|---|
| `skills/` (containing `*/SKILL.md`) | `docs/reference/skills/index.md` |
| `commands/` (containing `*.md`) | `docs/reference/commands/index.md` |
| `agents/` (containing `*.md`) | `docs/reference/agents/index.md` |
| `hooks/` (containing `*.sh`) | `docs/reference/hooks/index.md` |

Record which primitive directories exist and are non-empty. The
include-markdown catalog pages (`docs/reference/<thing>/index.md`)
should land in the scaffold output **only for primitive types the
project has**. For absent primitive types, drop the corresponding
catalog page from the scaffold and remove the page from the generated
`mkdocs.yml` nav.

This honors R1 F3 ("don't scaffold empty quadrants") at the catalog
sub-page level: an empty `docs/reference/agents/index.md` whose glob
matches nothing is just as much an empty stub as an empty quadrant
index.

### M3 — Detect existing docs

Four cases, each handled differently:

1. **`<root>/docs/.no-diataxis` present.** The project has explicitly
   opted out. **Refuse** with this message:

   > This project carries `docs/.no-diataxis` (opt-out marker). The
   > project has chosen a non-Diataxis docs convention. Remove the
   > marker and re-run if you want to switch; otherwise this skill
   > respects the opt-out.

   Stop.

2. **`<root>/docs/` is generated** (per the shared detector at
   `lib/docs-generated.sh` in this loom checkout — exit 0 means
   generated). **Refuse** with this message, parameterised on the
   detector's reason and the build-source it identified:

   > [SCAFFOLD SKIP][GENERATED] `<root>/docs/` is generated, not
   > hand-written.
   >
   > Detector: <one-line reason from `lib/docs-generated.sh`>
   >
   > Scaffolding into a generated tree would write template files
   > that the next build cycle erases — silent breakage. The
   > scaffold is whole-tree only; there is no per-file mode that
   > would survive a `rm -rf docs/ && rebuild` cycle.
   >
   > If you want a Diataxis surface for this project, edit the
   > build script to copy from a Diataxis-shaped source tree (e.g.
   > `docs-src/`), then re-run `/docs-scaffold --root <docs-src>`
   > against the source. Or remove the build pipeline that
   > generates `docs/` and let the scaffold own the directory.

   Stop. Do not proceed. (loom-3hb.)

3. **`<root>/docs/` absent or empty.** Clean scaffold path. Proceed to M4.

4. **`<root>/docs/` exists with content** (and is NOT detected as
   generated). Proceed to M4. Write the bones the project is missing
   and leave every file it already has alone.

   Don't put the disposition to the user first. The two cases with
   real stakes already stopped the run above: an opted-out project
   refuses at case 1, and a generated tree refuses at case 2. What
   reaches case 4 is a project with hand-written docs and no marker
   saying to stay out, and adding the files it doesn't have takes
   nothing away from it.

   Overwriting is off the table entirely (M5), so there's no per-file
   stake left to weigh either. A user who wanted a clean scaffold
   instead moves `docs/` aside (`mv docs docs.bak`) and re-runs, which
   is one command and keeps the old tree in their hands.

   This makes a re-scaffold idempotent by construction. A project that
   already has the four quadrant subdirs (`tutorials/`, `how-to/`,
   `reference/`, `explanation/`) with an `index.md` in each gets only
   the skeleton bones it's missing (mkdocs.yml, workflow,
   requirements.txt, catalog index pages), and its quadrant content is
   untouched.

### M4 — Gather variables

Three variables drive the substitution:

| Variable | Source | Example |
|---|---|---|
| `{{ project_name }}` | `git -C <root> config --get remote.origin.url` basename, falling back to `basename "<root>"` | `acme-widgets` |
| `{{ repo_url }}` | `git -C <root> config --get remote.origin.url`, normalized to https form | `https://github.com/acme/widgets` |
| `{{ short_description }}` | the user (no mechanical source) | `Widget orchestration for the Acme platform.` |

Use the detected values for the first two. Don't show them for
confirmation first. Both read straight out of `git config`, so
confirming them asks the user to check a lookup they'd have to run the
same command to check. The M5 report names both, which is where a wrong
detection actually gets caught, and by then it's a one-line edit rather
than a question standing between the user and the scaffold.

Ask for `short_description`. It's the one input with no mechanical
source in the repo, and a sentence saying what the project is for is
something the user knows and `git config` doesn't. That difference is
the whole reason it's worth a question where the other two aren't.

Ask for `repo_url` too when the project has no git remote, for the same
reason. With no remote there's nothing to read, and the GH Pages
workflow needs a real URL to do anything useful. Don't proceed with a
placeholder.

### M5 — Sort the file list

Build the full list of files the scaffold will create.
The list is the contents of `templates/diataxis/` (the loom repo's
canonical skeleton — see `templates/diataxis-README.md` for the
inventory) **minus** any `docs/reference/<thing>/index.md` pages
whose primitive type was absent at M2, **with** every `*.template`
file renamed to drop the suffix (the substituted content lands at
the suffixless path).

Tag each file (existence checked under `<root>`):

- `[NEW]` — file does not exist at `<root>/<path>`. Write it.
- `[EXISTS — differs]` — the project has its own version. Leave it.
- `[EXISTS — identical]` — already byte-identical to the template.
  No-op.

Write every `[NEW]` file. Leave both `[EXISTS]` classes alone. There's
no per-file question because there's no per-file decision left: a
`[NEW]` file displaces nothing, and an existing file is never
overwritten, so neither outcome turns on something the user knows and
the skill doesn't.

That's a change from an earlier contract, where a `merge` disposition
could overwrite an existing file given per-file approval. Overwriting
is gone rather than automated. The approval beat existed to make sure
nobody lost hand-written docs to a template stub, and not writing over
them gets the same property without asking N times for the same answer.

If a `[EXISTS — differs]` file is `mkdocs.yml` or
`.github/workflows/docs.yml`, say so in the M6 report and name the
consequence: the tree won't build or won't publish on the scaffold's
terms until the project's own copy carries the same wiring. Report it,
don't refuse. The project may well have its own and be right to.

### M6 — Apply

For each `[NEW]` file:

1. Copy the file from `templates/diataxis/<path>` into `<root>` at
   the corresponding path (creating directories as needed).
2. If the source path ends in `.template`, perform variable
   substitution on the copied content (replace `{{ project_name }}`,
   `{{ repo_url }}`, `{{ short_description }}`) and rename the
   destination to drop the `.template` suffix.
3. If the destination is a `docs/reference/<thing>/index.md` for a
   primitive type detected at M2, leave the include-markdown glob
   intact. (No substitution needed; the glob is project-agnostic.)
4. For the generated `mkdocs.yml`, remove nav entries for any
   catalog pages dropped at M2.

Substitution mechanism: use the same four-line `sed` pass documented
in `templates/diataxis-README.md` — `cp -r` the staged subset, then
`find ... -exec sed -i ...` for the three placeholders, then
`find ... -name '*.template' -exec mv ...` to rename. Substitution
is plain `sed`; no Python, no envsubst, no external scaffold tool
(loom is mostly markdown + bash + JSON per `CLAUDE.md`).

After writes complete, emit a summary:

```markdown
## Scaffold complete

Wrote: <N> files
Left alone: <K> existing files (listed below)
Variables substituted: project_name=<...>, repo_url=<...>,
  short_description=<...>

## Next steps

1. Install dependencies:
   pip install -r requirements.txt
2. Replace the DOCS-SCAFFOLD-FIXME sentinels with real content:
   grep -r DOCS-SCAFFOLD-FIXME docs/  # lists every unreplaced placeholder
   `mkdocs build --strict` will refuse to build until every sentinel is replaced;
   see `docs/reference/docs-scaffold-fixme.md` for the convention and inventory.
3. Preview locally:
   mkdocs serve
4. Splice the README pointer:
   cat README.docs-pointer.md  # then paste into your project README
5. Push to publish (GH Pages workflow will deploy on push to main):
   git add . && git commit -m "scaffold Diataxis docs" && git push
6. Enable GitHub Pages in repo settings: Source = "Deploy from a branch" → `gh-pages` (one-time setup; the workflow auto-creates the branch on first run).
7. Run `/audit-project --check=docs` periodically to catch drift
   between docs/ and the system / beads / MemPalace.
```

List the files left alone by name. Two detected variables and a set of
untouched files are the whole of what the user needs to check, and a
count on its own doesn't let them check anything.

If any catalog pages were dropped at M2, surface that in the summary
so the user knows: "Note: skipped `docs/reference/agents/index.md`
because no `agents/` directory was detected. Re-run after adding
agents to surface them."

## What this skill does NOT do

- **Does not overwrite a file the project already has.** Every write
  goes to a path that was empty. An existing file is reported and left,
  whatever its contents.
- **Does not run `mkdocs build` or `mkdocs serve`.** The summary
  *names* the next steps; the user runs them. The skill is a copier,
  not a builder.
- **Does not modify project beads or MemPalace state.** Read-only
  against `git config`, `git remote`, and the filesystem. The KG /
  drawer / diary capture for the work that produced THIS scaffold
  belongs to the activity recipe driving the bead, not to this
  skill.
- **Does not edit the source templates.** `templates/diataxis/` is
  the source-of-truth canonical skeleton; this skill only reads
  from it.
- **Does not generate tutorials, how-tos, or explanation content.**
  The `.template` files carry placeholder copy that the project
  must own. Auto-generating Tutorials from Reference content
  violates Diataxis F1 (mixing types) by construction — see the D1
  drawer §D rejection.
- **Does not support non-MkDocs SSGs.** Hugo / Jekyll / Docusaurus
  scaffolds are out of scope; the `docs/.no-diataxis` marker is the
  supported escape hatch for projects that need a different stack.

## Why this exists

Phase 1 of the Diataxis epic (loom-9z1) shipped loom's *own* docs
in the four-quadrant shape, dogfooding the discipline before
asking other projects to adopt it. Phase 2 (loom-km8) packages the
result so an already-loom-managed project can adopt the same shape
trivially.

The slash command + skill triple (rather than a one-shot `loom
configure-project --diataxis` mega-command) is deliberate: scaffold
is **write-heavy and project-permanent**, so it stays a surface the
user invokes on purpose rather than one that fires as a side effect of
something else. Per the D1 drawer §D, conflating detect + scaffold +
audit into one pass would violate that discipline. Keep the surfaces
separate.

The opt-out marker (`docs/.no-diataxis`) exists because golden-path
(CrossnoKaye Hugo, "1-onboarding/2-the-crossnokaye-way" layout) is
a real counter-example of a useful project that legitimately doesn't
fit Diataxis. Loom recommends Diataxis; loom doesn't impose it.

## Related infrastructure

- Slash command: `commands/docs-scaffold.md` — manual-only entry
  point with `disable-model-invocation: true`.
- Source skeleton: `templates/diataxis/` — canonical bones; see the
  sibling `templates/diataxis-README.md` for inventory + substitution
  mechanism.
- Companion check: `agents/project-onboarder.md` (loom-km8.3) —
  10th INFO check reports Diataxis-shape gap and names this skill
  as the fix.
- Companion drift detection: `/audit-project --check=docs` (loom-
  km8.4 portability) — once the scaffold lands, the same five drift
  checks (cardinality / citation / behavior / glob symmetry /
  explanation consistency) run against the project's own docs.
- Companion how-to: `docs/how-to/scaffold-managed-project-docs.md`
  (loom-km8.5) — narrative walk-through of this flow for a human
  reader.
- Locked design lives in MemPalace: `loom/decisions` wing, drawer
  **DIATAXIS-FOR-MANAGED-PROJECTS — D1 PLAN (loom-9z1.10)**.
