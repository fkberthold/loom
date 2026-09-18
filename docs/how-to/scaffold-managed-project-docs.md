# Scaffold a managed project's docs

To stand up a Diataxis-shaped MkDocs Material docs surface in a
loom-managed project, run `/docs-scaffold`. It writes the files the
project doesn't have and leaves every file it does have alone.

## Precondition

- The target project is **loom-managed** (`<root>/.claude/workflow.json`
  exists). If not, run `/audit-project` first to onboard it.
- `git status` is clean in the target project. The scaffold writes
  ~17 files; you want them in their own commit.
- The target project has a real git remote (`git remote get-url origin`
  returns a URL). The published GH Pages workflow needs a real
  `repo_url` to deploy.
- The project does **not** carry a `<root>/docs/.no-diataxis`
  opt-out marker. If it does, see [Opt out](#opt-out) below.

## Steps

1. **Switch to the target project.** `/docs-scaffold` resolves the
   target via the same precedence chain as `/audit-project`: explicit
   `--root <path>` flag wins, then cwd's git root, then cwd itself.

   ```bash
   cd /path/to/managed-project          # implicit cwd
   # or
   /docs-scaffold --root /path/to/managed-project  # cross-project from anywhere
   ```

2. **Run the slash command.** The skill walks six steps (M1–M6) and
   stops to ask at one of them.

   ```text
   /docs-scaffold
   ```

   `/docs-scaffold` is `disable-model-invocation: true`. It only
   fires when you type the slash command — no recipe, hook, or
   subagent will trigger it for you.

3. **Supply the short description.** At M4 the skill reads two of
   the three variables straight out of `git config` and uses them
   without asking:

   | Variable | Source |
   |---|---|
   | `{{ project_name }}` | `git remote.origin.url` basename |
   | `{{ repo_url }}` | `git remote.origin.url`, normalized to https |
   | `{{ short_description }}` | you (no mechanical source) |

   `short_description` is the one input the repo can't supply, which
   is why it's the one question. Give a single sentence saying what
   the project is for. The skill asks for `repo_url` too when the
   project has no remote, for the same reason.

4. **Read the file list.** At M5 the skill prints every file in the
   skeleton, tagged:

   - `[NEW]` — the file does not exist. It gets written.
   - `[EXISTS — differs]` — the project has its own version. Left
     alone.
   - `[EXISTS — identical]` — already byte-identical to the
     template. No-op.

   The full skeleton inventory lives at
   [`templates/diataxis-README.md`](https://github.com/fkberthold/loom/blob/main/templates/diataxis-README.md)
   (~17 files: `mkdocs.yml`, `requirements.txt`, the GH Pages
   workflow, four quadrant `index.md`s, a thin tutorial, an install
   how-to, four reference catalog pages, a mental-model explanation,
   and a README pointer).

5. **Let it write.** Every `[NEW]` file lands. Both `[EXISTS]`
   classes are left where they are.

   There's no per-file question because there's no per-file decision
   left. A `[NEW]` file displaces nothing, and an existing file is
   never overwritten, so neither outcome turns on something you know
   and the skill doesn't. The approval beat existed to stop anyone
   losing hand-written docs to a template stub, and not writing over
   them buys the same property without asking N times for the same
   answer.

   If `mkdocs.yml` or `.github/workflows/docs.yml` comes back
   `[EXISTS — differs]`, the M6 report names it and names the
   consequence: the tree won't build or publish on the scaffold's
   terms until your own copy carries the same wiring. Reported, not
   refused. You may well have your own and be right to.

6. **Mind the primitive-aware drops.** At M2 the skill scans the
   project for `skills/*/SKILL.md`, `commands/*.md`, `agents/*.md`,
   and `hooks/*.sh`. The matching `docs/reference/<thing>/index.md`
   pages are dropped from the scaffold for primitive types the
   project does not have. The summary at M6 names every dropped
   page so you can re-run after adding the missing primitives.

7. **Splice the README pointer.** The scaffold writes
   `README.docs-pointer.md` at the project root with a short
   pointer block. Paste it into your project's existing `README.md`
   (or replace its docs section); delete the pointer file
   afterward. The skill does not edit `README.md` for you.

8. **Install dependencies and preview.** From the project root:

   ```bash
   pip install -r requirements.txt
   mkdocs serve
   ```

   Open `http://localhost:8000`. The four quadrants render with
   placeholder copy you will replace; the Reference catalog pages
   include-markdown-glob the project's primitives and should show
   real content already.

9. **Push to publish.** A first-time GH Pages publish needs the
   workflow to run from `main`:

   ```bash
   git add docs/ mkdocs.yml requirements.txt .github/workflows/docs.yml
   git commit -m "scaffold Diataxis docs"
   git push
   ```

   Then enable GitHub Pages in the repo settings: **Source =
   "Deploy from a branch" → `gh-pages`** (one-time setup; the
   workflow auto-creates the branch on first run). The next push to
   `main` deploys the site.

## Outcome

The project carries a working `docs/` tree with the four Diataxis
quadrants, an MkDocs Material build, and a GH Pages publish
workflow. Reference pages auto-surface every project primitive via
`include-markdown` globs. Tutorials, How-to, and Explanation
quadrants ship with placeholder copy that is structurally correct
but content-empty — the project owns filling them in.

## Migrating existing flat docs

Most projects adopt loom *after* accumulating some `docs/` content.
M3 detects the existing files and carries on: the quadrants and
skeleton bones land alongside the legacy files, and nothing already
there is touched. The two cases with real stakes have already stopped
the run by then. An opted-out project refuses at the `.no-diataxis`
marker, and a generated `docs/` tree refuses because scaffolding into
one writes files the next build erases.

If you wanted a clean scaffold rather than an additive one, move the
old tree aside (`mv docs docs.bak`) and re-run. That's one command,
and it keeps the old tree in your hands.

That leaves the project in a **legitimate half-migrated state**:
the new `docs/{tutorials,how-to,reference,explanation}/` tree
co-exists with whatever was there before (`architecture.md`,
`spec.md`, `*-reference.md`, project-local `plans/`, `research/`,
etc.). This is fine. The skill is a copier, not a migrator; the
project owner decides which legacy files belong inside the
quadrants and on what schedule.

When you do migrate, this cheat-sheet covers most filenames:

| Legacy filename pattern | Likely quadrant | Notes |
|---|---|---|
| `*-reference.md`, `api.md`, `cli.md`, `spec.md` | `reference/` | Move into a flat file under `docs/reference/`, or a sub-page of the catalog if it documents one of the project's primitives. |
| `architecture.md`, `mental-model.md`, `philosophy.md`, `theory.md` | `explanation/` | Why-shaped prose. Diataxis F1 forbids mixing with how-to or reference content. |
| `setup.md`, `install.md`, `*-guide.md`, `*-walkthrough.md` | `how-to/` | Goal-oriented procedural content. Each how-to should solve one problem. |
| `getting-started.md`, `tutorial.md`, `intro.md` | `tutorials/` | Learning-oriented; one path through the project for a beginner. |
| `plans/`, `research/`, `decisions/` (existing project-local subdirs) | usually leave as-is | These are typically project conventions for ADRs / decision logs / RFCs and don't fit the four Diataxis quadrants. The Diataxis discipline doesn't require absorbing them. Cross-link from `explanation/` if useful. |
| `notes/`, `scratch/`, `wip/` | leave as-is or delete | Diataxis is about published docs. Internal notes belong elsewhere or in version control's history. |

When a legacy file straddles two quadrants (e.g. half-reference,
half-how-to), split it. Don't keep mixed-mode pages just to avoid
the work; mixed-mode pages are exactly what `/audit-project
--check=docs` Check 4 will start surfacing once `reference/` and
`how-to/` catalog pages exist.

You don't have to migrate everything in one pass. A common rhythm
is: scaffold → leave legacy alone for a release → audit drift →
migrate the noisiest files → audit again. The audit shows you which
flat files are now being cited from quadrant pages, which surfaces
the natural migration order without guessing.

A `/docs-migrate` skill that auto-classifies legacy files is out of
scope for v1; this human playbook is the supported v1 path.

## Opt out

To declare that the project will not adopt Diataxis:

```bash
mkdir -p docs
touch docs/.no-diataxis
```

The marker terminates `/docs-scaffold` with an explanation. The
[`/audit-project` Diataxis-shape check](#audit-after-scaffolding)
also respects the marker — it reports `INFO ("project opts out of
Diataxis docs convention")` and stops nagging. The marker wins
even when the four quadrants happen to exist; explicit opt-out is
explicit.

Use this when the project has chosen a non-MkDocs SSG (Hugo,
Jekyll, Docusaurus) or a non-Diataxis layout. The marker is the
supported escape hatch; loom does not ship alternative scaffolds
for v1.

## Audit after scaffolding

To check the new docs surface for drift against the project's
system / beads / MemPalace:

```bash
/audit-project --check=docs
```

In a managed project, the check runs against the project's own
root and MemPalace wing. To target a different project explicitly:

```bash
/audit-project --check=docs --root /path/to/other-project --wing other-project
```

The five checks (cardinality, citation resolution, behavior
claims, inclusion-glob symmetry, explanation consistency) run
against the project's own primitives, beads, and decision drawers
— not loom's. Re-run after each Reference catalog change or
non-trivial doc edit to catch drift early.

## Idempotent re-runs

A re-run of `/docs-scaffold` against an already-scaffolded project
is idempotent by construction. M3 detects the four quadrant subdirs
and the run becomes a refresh of the skeleton bones (`mkdocs.yml`,
the workflow, requirements, catalog index pages). Existing quadrant
content is left alone, because overwriting isn't on the table at
all. Use this to pull in new bones after upgrading loom without
losing your project-owned voice.

## Related

- For the slash command and its skill, see
  [reference: slash commands](../reference/slash-commands/index.md)
  and [reference: skills](../reference/skills/index.md).
- For the canonical skeleton inventory and the `sed`-based
  substitution mechanism, see
  [`templates/diataxis-README.md`](https://github.com/fkberthold/loom/blob/main/templates/diataxis-README.md).
- For why loom recommends Diataxis (Procida verbatim plus the C1–C6
  loom accommodations), see
  [explanation: mental model](../explanation/mental-model.md).
- The locked design lives in MemPalace as drawer
  **DIATAXIS-FOR-MANAGED-PROJECTS — D1 PLAN (loom-9z1.10)** in the
  `loom/decisions` wing. The phase-2 closing drawer
  **LOOM-KM8 PHASE 2 — PARALLEL DISPATCH OF T2/T3/T4** captures
  what shipped for the slash command, onboarder check, and audit
  portability; T1's templates closure has its own drawer in the
  same wing. Search `loom-km8` to surface the family.
