# Scaffold a managed project's docs

To stand up a Diataxis-shaped MkDocs Material docs surface in a
loom-managed project, run `/docs-scaffold` and approve each file
the skeleton would write.

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

1. **Switch to the target project.** `/docs-scaffold` reads the cwd's
   git root.

   ```bash
   cd /path/to/managed-project
   ```

2. **Run the slash command.** The skill walks six steps (M1–M6) with
   prompts at each transition.

   ```text
   /docs-scaffold
   ```

   `/docs-scaffold` is `disable-model-invocation: true`. It only
   fires when you type the slash command — no recipe, hook, or
   subagent will trigger it for you.

3. **Confirm the variables.** At M4 the skill detects defaults from
   `git config` and asks you to accept or edit each one:

   | Variable | Default source |
   |---|---|
   | `{{ project_name }}` | `git remote.origin.url` basename |
   | `{{ repo_url }}` | `git remote.origin.url`, normalized to https |
   | `{{ short_description }}` | (no default — supply one line) |

   `short_description` has no default because the landing page reads
   badly without it. Provide a single sentence describing the
   project.

4. **Review the per-file diff.** At M5 the skill prints every file
   the scaffold would write, tagged:

   - `[NEW]` — the file does not exist; will be created.
   - `[EXISTS — would overwrite]` — the file exists; requires
     explicit approval to replace.
   - `[EXISTS — identical]` — the file exists with byte-identical
     content; no-op.

   The full skeleton inventory lives at
   [`templates/diataxis/README.md`](https://github.com/fkberthold/loom/blob/main/templates/diataxis/README.md)
   (~17 files: `mkdocs.yml`, `requirements.txt`, the GH Pages
   workflow, four quadrant `index.md`s, a thin tutorial, an install
   how-to, four reference catalog pages, a mental-model explanation,
   and a README pointer).

5. **Approve per file.** The skill prompts once per `[NEW]` /
   `[EXISTS — would overwrite]` line:

   ```text
   File: docs/reference/skills/index.md  [NEW]. Apply? (yes / skip)
   ```

   `yes` queues the write. `skip` drops the file from the apply set.
   Per-file approval is **not optional**; there is no `--apply-all`
   flag in v1. (A bulk "yes to all" / "skip all remaining"
   shortcut is acceptable for ergonomics; do not default to silent
   acceptance.)

6. **Mind the primitive-aware drops.** At M2 the skill scans the
   project for `skills/*/SKILL.md`, `commands/*.md`, `agents/*.md`,
   and `hooks/*.sh`. The matching `docs/reference/<thing>/index.md`
   pages are dropped from the scaffold for primitive types the
   project does not have. The summary at M6 names every dropped
   page so you can re-run after adding the missing primitives.

7. **Skip the bones at your own risk.** If you decline
   `mkdocs.yml.template` or `.github/workflows/docs.yml`, the
   skill warns that the scaffold will not build or deploy without
   them. The skill does not refuse — your project, your call —
   but the warning surfaces the consequence.

8. **Splice the README pointer.** The scaffold writes
   `README.docs-pointer.md` at the project root with a short
   pointer block. Paste it into your project's existing `README.md`
   (or replace its docs section); delete the pointer file
   afterward. The skill does not edit `README.md` for you.

9. **Install dependencies and preview.** From the project root:

   ```bash
   pip install -r requirements.txt
   mkdocs serve
   ```

   Open `http://localhost:8000`. The four quadrants render with
   placeholder copy you will replace; the Reference catalog pages
   include-markdown-glob the project's primitives and should show
   real content already.

10. **Push to publish.** A first-time GH Pages publish needs the
    workflow to run from `main`:

    ```bash
    git add docs/ mkdocs.yml requirements.txt .github/workflows/docs.yml
    git commit -m "scaffold Diataxis docs"
    git push
    ```

    Then enable GitHub Pages in the repo settings: **Source =
    GitHub Actions**. The next push to `main` deploys the site.

## Outcome

The project carries a working `docs/` tree with the four Diataxis
quadrants, an MkDocs Material build, and a GH Pages publish
workflow. Reference pages auto-surface every project primitive via
`include-markdown` globs. Tutorials, How-to, and Explanation
quadrants ship with placeholder copy that is structurally correct
but content-empty — the project owns filling them in.

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
is idempotent: M3 detects the four quadrant subdirs and treats the
run as a refresh of the skeleton bones (`mkdocs.yml`, the workflow,
requirements, catalog index pages). Existing quadrant content is
left alone unless you explicitly approve the overwrite in the M5
diff. Use this to pull in new bones after upgrading loom without
losing your project-owned voice.

## Related

- For the slash command and its skill, see
  [reference: slash commands](../reference/slash-commands/index.md)
  and [reference: skills](../reference/skills/index.md).
- For the canonical skeleton inventory and the `sed`-based
  substitution mechanism, see
  [`templates/diataxis/README.md`](https://github.com/fkberthold/loom/blob/main/templates/diataxis/README.md).
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
