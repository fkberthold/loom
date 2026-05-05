---
name: docs-scaffold
description: Scaffold a Diataxis-shaped MkDocs Material docs/ tree into the current loom-managed project by copying templates/diataxis/ with variable substitution and per-file approval. Refuses against non-loom-managed projects and against projects carrying the docs/.no-diataxis opt-out marker. Manual-only — never auto-suggested by session-startup or any activity recipe; only fires when the user invokes `/docs-scaffold`.
---

# Docs-Scaffold — Diataxis Skeleton Copier

This skill is the driver behind the `/docs-scaffold` slash command.
It copies the canonical Diataxis skeleton from `templates/diataxis/`
(the loom repo) into the **current loom-managed project**, customising
it with project-local variables and surfacing only the include-markdown
catalog pages for primitives the project actually has.

The discipline this skill codifies, restated:
**loom recommends Diataxis; the project decides.** The scaffold is
opt-in (manual slash command), per-file approval-gated (the user can
decline any single file), and explicitly opt-out-respecting (a
`docs/.no-diataxis` marker terminates the skill with an explanation).
Loom ships the bones; the project owns the voice.

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

Three cases, each handled differently:

1. **`<root>/docs/.no-diataxis` present.** The project has explicitly
   opted out. **Refuse** with this message:

   > This project carries `docs/.no-diataxis` (opt-out marker). The
   > project has chosen a non-Diataxis docs convention. Remove the
   > marker and re-run if you want to switch; otherwise this skill
   > respects the opt-out.

   Stop.

2. **`<root>/docs/` absent or empty.** Clean scaffold path. Proceed to M4.

3. **`<root>/docs/` exists with content.** List every existing file under
   `<root>/docs/` and ask the user how to proceed:

   - **skip** — abort the scaffold, leave existing docs alone.
   - **merge** — proceed; at M5 the user will approve per-file, so
     existing files won't be silently overwritten. Files the scaffold
     would write that already exist are flagged as `[EXISTS — would
     overwrite]` in the M5 preview; the user explicitly approves
     each overwrite or declines.
   - **refuse** — abort with a note suggesting the user move `docs/`
     aside (`mv docs docs.bak`) and re-run for a clean scaffold.

   Default to skip if the user is unclear.

   Sub-case: if `docs/` already has the four quadrant subdirs
   (`tutorials/`, `how-to/`, `reference/`, `explanation/`) and each
   has at least an `index.md`, treat this as **idempotent re-scaffold**:
   M5 will show only the skeleton-bones diffs (mkdocs.yml, workflow,
   requirements.txt, catalog index pages); existing quadrant content
   is left alone unless the user explicitly approves the overwrite.

### M4 — Gather variables

Three variables drive the substitution. Each has a detection step
that the user can override at the prompt:

| Variable | Default source | Example |
|---|---|---|
| `{{ project_name }}` | `git -C <root> config --get remote.origin.url` basename, falling back to `basename "<root>"` | `acme-widgets` |
| `{{ repo_url }}` | `git -C <root> config --get remote.origin.url`, normalized to https form | `https://github.com/acme/widgets` |
| `{{ short_description }}` | (no default — prompt the user) | `Widget orchestration for the Acme platform.` |

Show the user each detected default and ask whether to accept or
edit. Never silently use a default for `short_description` — the
landing page reads badly without it, and asking once is cheap.

If the project has no git remote, prompt the user for `repo_url`
directly. Refuse to proceed with a placeholder; the GH Pages
workflow needs a real URL to do anything useful.

### M5 — Preview the diff

Build the full list of files the scaffold will create or replace.
The list is the contents of `templates/diataxis/` (the loom repo's
canonical skeleton — see `templates/diataxis-README.md` for the
inventory) **minus** any `docs/reference/<thing>/index.md` pages
whose primitive type was absent at M2, **with** every `*.template`
file renamed to drop the suffix (the substituted content lands at
the suffixless path).

For each file, show one of these tags (existence checked under `<root>`):

- `[NEW]` — file does not exist at `<root>/<path>`. Will be created.
- `[EXISTS — would overwrite]` — file exists at `<root>/<path>`.
  Requires explicit approval to overwrite (declined → skip this file).
- `[EXISTS — identical]` — file exists at `<root>/<path>` with
  byte-identical content. No-op; show in the preview but do not prompt.

For each `[NEW]` and `[EXISTS — would overwrite]` line, ask:

> File: `<path>` `[NEW|EXISTS — would overwrite]`. Apply? (yes / skip)

`yes` → queue for write. `skip` → drop from the apply set.

Per-file approval is **not optional**. The user must answer for
every flagged file. A bulk "yes to all" / "skip all remaining"
shortcut is acceptable for ergonomics, but do not default to silent
acceptance.

If the user skips a `mkdocs.yml.template` or the
`.github/workflows/docs.yml`, **warn** that the scaffold will be
non-functional without those files and confirm the skip. Do not
refuse — the user may have their own. Just make the consequence
visible.

### M6 — Apply

For each approved file:

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
Skipped: <K> files (per user decision)
Variables substituted: project_name=<...>, repo_url=<...>,
  short_description=<...>

## Next steps

1. Install dependencies:
   pip install -r requirements.txt
2. Preview locally:
   mkdocs serve
3. Splice the README pointer:
   cat README.docs-pointer.md  # then paste into your project README
4. Push to publish (GH Pages workflow will deploy on push to main):
   git add . && git commit -m "scaffold Diataxis docs" && git push
5. Enable GitHub Pages in repo settings: Source = "GitHub Actions"
6. Run `/audit-project --check=docs` periodically to catch drift
   between docs/ and the system / beads / MemPalace.
```

If any catalog pages were dropped at M2, surface that in the summary
so the user knows: "Note: skipped `docs/reference/agents/index.md`
because no `agents/` directory was detected. Re-run after adding
agents to surface them."

## What this skill does NOT do

- **Does not write to disk without per-file user approval.** Every
  `[NEW]` and `[EXISTS — would overwrite]` file requires explicit
  approval. There is no `--apply-all` flag in v1.
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
is **write-heavy and project-permanent**, and the audit-project
discipline of read-only-checklist + per-item-approval is the proven
shape. Per the D1 drawer §D, conflating detect + scaffold + audit
into one pass would violate that discipline. Keep the surfaces
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
