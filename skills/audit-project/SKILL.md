---
name: audit-project
description: Audit the current project's workflow infrastructure (git/branch hygiene, beads init, bd hooks, workflow.json, MemPalace wing, CLAUDE.md, .claude/rules/, .claude/agents/+commands/, bd memories) and — for projects that already have a Diataxis docs substrate — the docs/system/beads/MemPalace alignment of the project's documentation. Drives the project-onboarder subagent, presents the structured checklist to the user, and offers interactive template-based fixes per gap. Manual-only — never auto-suggested by session-startup or any activity recipe; only fires when the user invokes `/audit-project`.
---

# Audit-Project — Project Onboarding + Drift-Detection Skill

This skill is the driver behind the `/audit-project` slash command.
It coordinates two responsibilities, run sequentially in one session:

1. **Onboarding scan** — dispatch the `project-onboarder` subagent to
   scan workflow-infrastructure setup (git hygiene, beads, hooks,
   `workflow.json`, MemPalace wing, `CLAUDE.md`, rules dir, `bd
   memories`) and return a `PASS`/`WARN`/`MISS` checklist. This is
   the v1 behavior shipped 2026-05-03.
2. **Docs drift detection** — for projects with a Diataxis docs
   substrate, compare `docs/` against the system (filesystem
   primitives), beads (`bd show`), and MemPalace (`mempalace_*`) and
   report doc-vs-reality drift. This is the v2 behavior gated by
   `--check=docs` (default-on when the substrate is present).

   Note: "Diataxis substrate" (the docs-check gate) is a *different*
   condition from "loom-managed" (the docs-scaffold and onboarding
   gate). Loom-managed = `.claude/workflow.json` present. Diataxis
   substrate = `.beads/` present AND `docs/` already has at least one
   Diataxis quadrant. A project is typically loom-managed first, then
   gains a Diataxis substrate after running `/docs-scaffold`. Don't
   conflate the two terms.

The two phases produce a single combined report. The user approves
fixes per item — nothing is auto-applied unless the user asks.

The discipline this skill codifies, restated for the docs check:
**when docs disagree with system / beads / MemPalace, docs lose.**
The check reports doc fixes — never the other way around. A doc
that says "all six commands have X" when only five do is the doc's
problem; a doc that cites a bead-ID that no longer resolves is the
doc's problem. The system / beads / palace are the sources of
truth; `docs/` is the surface.

Invocation: explicit only. `/audit-project` (with optional flags)
fires this skill. The slash command and this skill both carry
`disable-model-invocation: true` in spirit — the user has to ask;
session-startup and the activity recipes never auto-suggest the
audit. This is a deliberately user-pulled workflow.

## When to use

- The user types `/audit-project` (with or without flags).
- The user asks to "audit this project" / "check docs drift" /
  "see what's missing for the workflow."
- A new project just got `bd init`-ed and you want a sanity check
  on what's wired up.
- You suspect docs have drifted from reality (cardinality claims,
  dead bead-IDs, primitives that changed shape) and want a
  systematic sweep instead of ad-hoc grepping.

## Skip when

- Mid-task in another bead. The audit is a session-spanning
  ceremony; don't interleave it with claimed work.
- The project is not a beads workspace and not a loom-managed
  project. The skill produces empty output for non-loom projects
  with no `.beads/`.
- The user wants to verify a single fact ("does X exist?"). Just
  check it directly; don't run the full audit.

## Flags

- `--check=onboarding` — run only the project-onboarder dispatch.
  Equivalent to v1 behavior.
- `--check=docs` — run only the docs drift detection. Useful when
  the project is already onboarded and you only want the
  doc-vs-reality sweep.
- `--check=all` (default when the project has a Diataxis substrate;
  see Step 1) — run both.
- `--apply-trivial` — auto-apply doc-drift items the skill has tagged
  `[DOC FIX][TRIVIAL]`: cardinality count corrections (the loom-469
  class — single-numeral substitution at a known file:line) and dead
  bead-IDs whose `bd show` returns a unique `superseded-by` ID.
  Ambiguous items (factual claims, behavior descriptions, fuzzy
  drawer-citation matches) are NEVER tagged TRIVIAL and remain in
  the per-item approval queue. See "Step 3.5 — apply tagged items"
  below for the full apply procedure. (loom-8hg.)
- `--apply-onboarding` — auto-apply onboarding-checklist items the
  `project-onboarder` subagent has tagged `[AUTOFIX:<recipe-id>]` on
  the suggested-fix line. Recognised recipes (loom-a29):
  - `[AUTOFIX:bd-hooks]` (item 3 MISS) — runs `bd hooks install`
    then `git add .beads/issues.jsonl && git commit -m "bd:
    post-install export sync"` (the loom-cka two-step absorbing
    commit).
  - `[AUTOFIX:workflow-json]` (item 4 MISS) — writes
    `{"v":1,"mode":"full"}` to `<root>/.claude/workflow.json`. Mode
    is a real choice; `full` is the documented default. Override
    with `--workflow-mode=light|off` to change the value the flag
    writes; users who later want a different mode can edit the file
    directly.
  - `[AUTOFIX:gitignore-worktrees]` (item 11 INFO) — appends
    `.claude/worktrees/` to `<root>/.gitignore` if not already
    present. Idempotent.
  Items NOT tagged AUTOFIX (item 2 `bd init`, item 5 MemPalace wing
  creation, item 6 CLAUDE.md authoring, item 7 `.claude/rules/`)
  remain in the per-item approval queue. The flag never touches
  WARN items (those imply real conflict — dirty tree, malformed
  workflow.json, etc. — and need human triage).
- `--workflow-mode=full|light|off` — only meaningful with
  `--apply-onboarding`. Sets the `mode` value the
  `[AUTOFIX:workflow-json]` recipe writes. Default `full`.
- `--root <path>` — project root to audit (default: current working
  directory's git root, or cwd if not in a git repo). All filesystem
  globs, `bd` lookups, and `git` commands resolve against this root.
  Lets the skill run against any loom-managed project, not just loom
  itself.
- `--wing <name>` — MemPalace wing to use for drawer-slug resolution
  in Check 5 (and any other palace-citation checks). Default: the
  basename of `--root` used verbatim (no case-folding, no `_`↔`-`
  substitution — the palace's de-facto convention follows filesystem
  naming, so `liza_base` filesystem → wing `liza_base`,
  `hundred_acre_woods` → wing `hundred_acre_woods`). Fallback: `loom`
  only if the auto-detect basename is itself `loom` (preserves the
  pre-portability behavior for loom's own audit). The wing-name flag
  exists for projects whose directory basename doesn't match their
  MemPalace wing slug (e.g., a checkout named `liza_live` whose wing
  is `liza`). Step 1b's wing-variant WARN catches the remaining
  divergence cases (capitalization that doesn't match, separator
  flip relative to a larger sibling wing).

If no flag is given, the default is `--check=all` for projects with
a Diataxis substrate (heuristic: `.beads/` exists AND `docs/`
contains at least one Diataxis quadrant directory — `tutorials/`,
`how-to/`, `reference/`, or `explanation/`). For other projects
the default is `--check=onboarding` to preserve v1 behavior.

This gate condition is named `has-diataxis-substrate` throughout the
sequence below; it is *not* the same as "loom-managed" (which is
`.claude/workflow.json` present, the gate `/docs-scaffold` and the
project-onboarder use).

## The Sequence

### Step 1 — resolve project root + flags + wing

Resolve the project root in this precedence order:

1. Explicit `--root <path>` flag (absolute or relative; resolved to
   absolute).
2. Current working directory's git root (`git -C $PWD rev-parse
   --show-toplevel`).
3. Current working directory itself (fallback when not in a git repo).

Parse the rest of the flags. Decide whether the docs check runs
(`has-diataxis-substrate` heuristic below, or explicit
`--check=docs|all`).

Resolve the project's MemPalace wing in this precedence order:

1. Explicit `--wing <name>` flag.
2. Basename of the resolved root, used verbatim — no case-folding,
   no `_`↔`-` substitution (e.g., a root at `/home/frank/repos/loom`
   → wing `loom`; a root at `/home/frank/repos/hundred_acre_woods` →
   wing `hundred_acre_woods`; a root at `/home/frank/repos/liza_base`
   → wing `liza_base`). The palace's de-facto wing convention follows
   filesystem naming, so the verbatim basename is the right default.
   Step 1b's variant WARN handles the cases where the filesystem name
   genuinely diverges from the canonical wing slug.
3. The literal `loom` only when step 2 already produces `loom` —
   this is the no-flag, loom-itself path and preserves v1 behavior.

Detect the project's primitive directories from the filesystem
(used by Checks 3 and 4). Probe each of these under the resolved
root; record which exist:

- `skills/` (each `skills/*/SKILL.md` is a primitive)
- `commands/` (each `commands/*.md` is a primitive)
- `agents/` (each `agents/*.md` is a primitive)
- `hooks/` (each `hooks/*.sh` is a primitive)

Do NOT hardcode the loom set. Projects that follow loom's primitive
shape will have all four; projects that adopted only a subset (or
that use additional primitive types) drive what the checks compare
against. Checks 3 and 4 silently skip a primitive class whose
directory doesn't exist.

Detect `has-diataxis-substrate` by checking `<root>` for: `.beads/`
present AND `docs/` containing at least one of `tutorials/`,
`how-to/`, `reference/`, `explanation/`. If both conditions hold,
the docs check defaults on; otherwise it defaults off. (This is
distinct from "loom-managed", which is `.claude/workflow.json`
present — the gate used by `/docs-scaffold` and the
project-onboarder. The two gates can be true independently.)

Detect the Diataxis opt-out: if `<root>/docs/.no-diataxis` exists,
record `opt_out_diataxis = true`. Check 4 (inclusion-glob coverage,
which assumes Diataxis-shaped `docs/reference/<thing>/` catalog
pages) is skipped under opt-out. Checks 1, 2, 3, and 5 still run
if `<root>/docs/` exists at all — those checks are about
docs-vs-reality drift in whatever shape the docs take, not about
Diataxis layout.

Detect whether `<root>/docs/` is generated by running the shared
detector at `lib/docs-generated.sh` (loom repo, sourced from this
loom checkout):

```bash
bash <loom-checkout>/lib/docs-generated.sh "<root>"
```

The detector exits 0 when `docs/` is generated (gitignored, or
written by a build script — see the helper for the full signal
list) and prints a one-line reason on stdout. Record the result as
`docs_generated = true|false` along with the reason.

When `docs_generated = true`:

- All sub-checks in Step 3 that would scan files under `<root>/docs/`
  (Checks 1, 2, 3, 5) are **skipped for paths under `<root>/docs/`**
  but still run against root-level docs files in scope (per loom-ojn:
  `README.md`, `README.rst`, `README.txt`).
- Check 4 (inclusion-glob coverage) is skipped entirely — the
  generated catalog page is not the source-of-truth.
- Step 3 emits one line per skipped class:

  ```
  [DOC SKIP][GENERATED] docs/ is generated — skipping <check-name>
    reason:    <verbatim detector reason>
    pointer:   edit the source named in the build script, not docs/
  ```

This is loom-qp0's required behavior — when docs/ is the artifact,
audit-project must not point the user at it. The README-in-scope
expansion below (loom-ojn) naturally handles the cardinality drift
case (reports drift in README, the source, even when docs/ is
generated from README).

### Step 1b — wing-variant warning (auto-detect only)

If the wing was auto-detected (steps 2 or 3 of the wing precedence
chain — i.e., `--wing` was NOT explicitly passed), surface a WARN when
the resolved wing has basename-variant siblings in the palace. This
catches the case where the canonical project wing uses a different
separator or capitalization than the directory basename suggests
(e.g., directory `hundred-acre-woods` auto-resolves to wing
`hundred-acre-woods` with 3 drawers, but the canonical wing is
`hundred_acre_woods` with 13 drawers).

Procedure:

1. Call `mempalace_list_wings`.
2. Compare the auto-detected wing slug `W` against every other wing
   slug `S` in the result. `S` is a basename-variant of `W` when any
   of these holds:
   - `S` equals `W` after substituting `_` ↔ `-` and lowercasing
   - `S` equals `W` after stripping/adding a trailing `s` (singular ↔
     plural)
   - `S` equals `W` after collapsing `_` and `-` to a common neutral
     (snake_case ↔ kebab-case both reduce to the same compact form)
3. For each variant `S`, record its drawer count (use
   `mempalace_list_drawers(wing=S, limit=1)` and the returned total
   count, or whichever palace API surfaces the count cheaply).
4. Emit the WARN line **only when** at least one variant `S` has
   `drawer_count(S) > drawer_count(W)`. Skip the WARN when the
   auto-detected wing is the largest sibling (it's plausibly canonical;
   no escalation needed).

WARN line shape:

```
[WING WARN] auto-detected wing may not be canonical
  resolved:   <W> (<M> drawers, basename auto-detect)
  variants:   <S1> (<N1> drawers), <S2> (<N2> drawers)
  suggested:  re-run with --wing <S_largest> if you want drift checks
              scoped to the larger wing
```

Surface this WARN **before Step 2**, so the user can interrupt and
re-run with the correct `--wing`. Do not block — emit, then continue.
The user owns the call; the skill just makes the silent-wrong case
loud.

If `--wing` was explicitly passed, skip Step 1b entirely (the user
made the call deliberately).

### Step 2 — dispatch project-onboarder (unless `--check=docs`)

Call the `project-onboarder` subagent with the absolute project
root (the resolved `--root` value) and the project's short name
(the resolved `--wing` value, which doubles as the bd-memories
search keyword and the wing slug the subagent reports against).
Wait for its structured `PASS`/`WARN`/`MISS` checklist. Display
the report verbatim before moving to step 3.

### Step 3 — docs drift detection (unless `--check=onboarding`)

Run the five sub-checks below in order. Each produces zero or more
report lines tagged `[DOC FIX]`, with three fields:

- **what doc says** — the verbatim claim (or path) the doc makes
- **what reality says** — what the system / beads / palace shows
- **suggested fix** — the minimal edit that resolves the drift

Lines accumulate into one report section labeled `## Docs drift
detection`. Empty section = clean.

#### Default doc scope

All sub-checks scan a single flat set of doc files (loom-ojn):

- `<root>/README.md`, `<root>/README.rst`, `<root>/README.txt` — the
  root README, in whichever extension the project uses.
- `<root>/docs/**/*.md` — the existing scope.

**Out of scope (excluded by default):** `AGENTS.md`, `CLAUDE.md`,
`GEMINI.md` at the root (these are agent-instruction files, not
user-docs); `.github/*` and package-metadata files. The exclusion is
hardcoded for v1; a future bead may add a `--scope-extra <glob>`
flag if a project needs to bring more files into scope.

There is no `MIRROR` qualifier — root README is a sibling doc to
`docs/`, not a mirror. Drift in README reports as a plain `[DOC FIX]`
on the same footing as drift inside `docs/`. (Historical note: the
`[DOC FIX][MIRROR]` tag was an emergent runtime behavior during the
loom-b6o trial; it is not part of the skill's specified output.)

When `docs_generated = true` (per Step 1), the `<root>/docs/**/*.md`
half of the scope is skipped per check (one `[DOC SKIP][GENERATED]`
line emitted per class) but root README files remain in scope —
which is usually the source-of-truth in generated-docs projects
(e.g. `cp README.md docs/index.md` in tla-puzzles).

#### Sub-check execution

All filesystem globs and paths in the sub-checks below are relative
to the resolved `--root`. All `bd show` calls run in the project's
`.beads/` workspace by `cd`-ing to `<root>` first (or by setting
`bd`'s `--workspace` flag if available — `cd` is the portable
default). All `mempalace_search` calls filter by the resolved
`--wing` value.

If neither `<root>/docs/` nor any of `<root>/README.{md,rst,txt}`
exists, emit `## Docs drift detection` with a single line `no
in-scope doc files at <root> — skipping docs drift detection` and
proceed to Step 4. If `<root>/docs/.no-diataxis` is present, emit a
`[DOC FIX][INFO] diataxis-opt-out` note explaining that Check 4 is
skipped, then run Checks 1, 2, 3, and 5 normally.

#### Check 1 — Cardinality

Find numeric claims in `<root>/docs/` that count primitives. For
v1 the patterns are naive grep:

- `All (one|two|three|four|five|six|seven|eight|nine|ten|N+) <noun>`
- `<digit>+ (skills|commands|subagents|hooks|recipes|drawers|wings)`
- `(only|just|exactly) <digit>+ <noun>`

For each match, identify the noun and source-of-truth glob (all
paths relative to the resolved `--root`; wing-scoped MCP calls use
the resolved `--wing` value):

| Noun | Source-of-truth |
|---|---|
| `skills` / `recipes` | `<root>/skills/*/SKILL.md` |
| `commands` / `slash commands` | `<root>/commands/*.md` |
| `subagents` / `agents` | `<root>/agents/*.md` |
| `hooks` | `<root>/hooks/*.sh` |
| `wings` / `rooms` | `mempalace_list_wings` / `mempalace_list_rooms` (filtered to `--wing` for room counts) |

If a primitive directory doesn't exist under `<root>` (e.g., a
project that has no `agents/`), skip cardinality claims about that
noun rather than reporting "0 found".

Compare the doc's count to the actual count. Mismatch → emit:

```
[DOC FIX][TRIVIAL] cardinality
  doc:        <file>:<line> "All <N> <noun> have <claim>"
  reality:    <M> <noun> match <glob>
  suggested:  s/<N>/<M>/
```

Emit the `[TRIVIAL]` qualifier ONLY when:

- The doc's text differs from reality by exactly one numeral (or one
  word-number like `four` → `five`), AND
- The substitution is unambiguous at the given file:line (the numeral
  appears once on that line, so a literal s/old/new/ is safe).

When the mismatch is "N matches but K satisfy <claim>" (e.g., the doc
asserts a property of all six items but only five satisfy it), the fix
is a rewrite, not a substitution — emit `[DOC FIX]` without the
`[TRIVIAL]` tag and let the user resolve it manually.

This catches the loom-469 class. The `--apply-trivial` flag (Step 3.5)
applies every `[DOC FIX][TRIVIAL]` item.

#### Check 2 — Citation resolution

Every citation in `<root>/docs/` must resolve. Scan for:

- **Bead IDs** — delegate the scan + resolve to
  `lib/bd-id-extract.sh` (loom-6m8). The helper takes doc text on
  stdin and emits one dead bead-ID per line on stdout. It detects
  the project's bd prefix as a LITERAL string from
  `<root>/.beads/issues.jsonl` (or `bd list --limit 1 --json` as
  fallback), so snake_case prefixes (`liza_base-`) and hyphenated
  prefixes (`tla-puzzles-`) both work without regex-shape guessing.
  Invocation:

  ```bash
  find <root>/docs -type f -name '*.md' -print0 \
    | xargs -0 cat \
    | bash <loom>/lib/bd-id-extract.sh --root=<root>
  ```

  For each emitted ID, also run `cd <root> && bd show <id> 2>&1`
  to recover close-reason / supersession metadata for the
  `[DOC FIX] dead-bead-id` line. Do NOT write ad-hoc regexes
  inline — the helper exists precisely so every `/audit-project`
  run produces the same answer (loom-6m8 surfaced an "every ID
  shows as dead" false-positive caused by per-run regex drift).
  Failure → emit `[DOC FIX] dead-bead-id`.
- **Commit SHAs** — pattern `\b[0-9a-f]{7,40}\b` adjacent to
  "commit" / "sha" / git context. For each match, run
  `git -C <root> cat-file -e <sha> 2>&1`. Failure → emit `[DOC FIX]
  dead-commit`.
- **File paths** — pattern that looks like a path inside the repo
  (starts with one of the project's detected primitive directories
  — `skills/`, `commands/`, `agents/`, `hooks/` if present — or
  with `docs/`, `lib/`, `scripts/`, etc., and ends in a known
  extension or directory marker). For each match, check the
  filesystem under `<root>`. Missing → emit `[DOC FIX] missing-path`.
- **Drawer slugs** — any reference to a MemPalace drawer by slug
  or title. Pattern: text inside backticks adjacent to "drawer" /
  "MemPalace" / "wing/" / "decisions" — admittedly fuzzy in v1.
  For each candidate, call `mempalace_search` with `wing=<--wing>`
  to scope the lookup to the project's own wing, plus an unfiltered
  fallback search if nothing hits (the doc may legitimately cite a
  cross-wing drawer reachable via tunnel). Emit `[DOC FIX]
  missing-drawer` only if both searches return no strong match.
- **Slash command names** — pattern `/[a-z0-9-]+\b`. For each
  match, check `<root>/commands/<name>.md` exists. Missing → emit
  `[DOC FIX] missing-slash-command`. Skip this check if the project
  has no `commands/` directory at all (the slash-command convention
  doesn't apply).

Output line shape (per failed citation):

```
[DOC FIX] <citation-class>
  doc:        <file>:<line> cites `<token>`
  reality:    <one-line failure from the resolution attempt>
  suggested:  <replacement|removal hint>
```

For dead bead-IDs specifically, attempt to follow the
supersedes-chain: `bd show <dead-id>` may return supersession
metadata in the close reason or via a `superseded-by` label;
if so, suggest the replacement ID. When the supersedes-chain
yields exactly one replacement ID, emit the line with the
`[TRIVIAL]` qualifier:

```
[DOC FIX][TRIVIAL] dead-bead-id
  doc:        <file>:<line> cites `<dead-id>`
  reality:    bd show <dead-id> → superseded-by <new-id>
  suggested:  s/<dead-id>/<new-id>/
```

When the chain yields zero or multiple candidates, emit
`[DOC FIX] dead-bead-id` without the `[TRIVIAL]` tag — the
replacement is a real choice and stays in the per-item approval
queue.

This catches the loom-qj3 lying-doc class for the citation
sub-class.

#### Check 3 — Behavior claims

Doc says X exists / X does Y. Verify against system reality. v1
naive: scan for sentences of shape:

- ``\`<token>\` (exists|is shipped|ships|is installed|carries)``
- ``\`<token>\` (does|fires|invokes|dispatches) <claim>``

For tokens that name a primitive (`/foo` → command,
`<name>-a-bead` → skill, `<name>-researcher` → subagent,
`<name>.sh` → hook), check the corresponding source file under
`<root>` (and skip the class entirely if the project doesn't
have that primitive directory):

- `/<name>` → `<root>/commands/<name>.md`
- `<name>-a-bead` (without slash) → `<root>/skills/<name>-a-bead/SKILL.md`
- bare hook name `<x>.sh` → `<root>/hooks/<x>.sh`
- bare subagent name (matches an `<root>/agents/*.md` basename) → that
  file

Missing source file → emit:

```
[DOC FIX] missing-primitive
  doc:        <file>:<line> "<verbatim claim>"
  reality:    <expected source file> does not exist
  suggested:  remove the claim, or file a bead to add the primitive
```

For "does Y" claims, v1 cannot semantically verify the action
description (that's v2). It can only confirm the primitive itself
exists. If the primitive exists but the claim's verb is suspect
(e.g., "fires on X" claims with a hook that doesn't bind to X in
`settings.json`), surface as a `[DOC FIX][SOFT]` for human review
rather than `[DOC FIX]`.

This catches the loom-qj3 lying-doc class for the
"X exists" / "X does Y" sub-class.

#### Check 4 — Inclusion-glob coverage (symmetric)

**Skipped entirely under `docs/.no-diataxis` opt-out** — this
check assumes the Diataxis-shaped `docs/reference/<thing>/` catalog
layout, which the opt-out marker disclaims. The other four checks
still run.

For each catalog page in `<root>/docs/reference/` whose source
primitive directory exists under `<root>`:

| Catalog page | Source glob |
|---|---|
| `<root>/docs/reference/skills/index.md` | `<root>/skills/*/SKILL.md` |
| `<root>/docs/reference/slash-commands/index.md` | `<root>/commands/*.md` |
| `<root>/docs/reference/subagents/index.md` | `<root>/agents/*.md` |
| `<root>/docs/reference/hooks/index.md` | `<root>/hooks/*.sh` |

Pairs are skipped when either side is absent: a project with no
`agents/` directory has nothing to glob; a project that hasn't
shipped `docs/reference/hooks/index.md` has no catalog to check.
The check fires only on (catalog-page-exists AND source-dir-exists)
pairs.

Two checks per pair:

1. **Source → doc.** Every primitive on disk must appear in the
   catalog page (by name). Missing → emit `[DOC FIX]
   missing-from-catalog`.
2. **Doc → source.** Every primitive named in the catalog page
   must correspond to a real file under the source glob. Missing
   → emit `[DOC FIX] catalog-ghost`.

The symmetric check is what catches the case where a
new primitive shipped without doc backfill (source → doc miss) AND
the case where docs claim a primitive that doesn't exist (doc →
source miss; the loom-qj3 / installed-files-claims-audit-project
class).

For projects that use `mkdocs-include-markdown` to auto-glob the
catalog, the auto-generated `all-<thing>.md` page should be
trusted as the authoritative inclusion result. Compare the
human-edited Inventory / Invocation tables in `index.md` against
the auto-globbed `all-<thing>.md` content; any name that appears
in `all-<thing>.md` but not in `index.md` is a `missing-from-
inventory` drift. Names that appear in `index.md` but not in
`all-<thing>.md` are a `inventory-ghost` drift.

#### Check 5 — Explanation-doc consistency

Every page under `<root>/docs/explanation/` cites at least one
MemPalace drawer (the design-source-of-truth claim from
`docs/explanation/provenance.md` and the recipe-family doc).
For each citation:

- Exact slug → `mempalace_get_drawer(slug)`. Hit → PASS.
- Title-shaped citation → `mempalace_search(title, wing=<--wing>)`.
  Scope the search to the project's own wing first; on no strong
  hit, retry without wing filter (cross-wing tunnel case). Top
  result with high similarity → PASS. No strong match either way
  → emit `[DOC FIX] missing-drawer-citation`.

This is a v1 best-effort check — drawer citation in prose is
unstructured, so the patterns are fuzzy. If the project uses a
convention like `> Drawer: <wing>/<slug>` or footnote-style
citations, prefer those structured patterns and skip free-text
matching.

### Step 3.5 — apply tagged items (only when --apply-trivial / --apply-onboarding set)

If neither flag is set, skip this step entirely; every item flows to
the per-item approval queue in Step 4.

When at least one apply flag is set, walk the report top-to-bottom and
process items as follows. Order: onboarding items first (they may
create `.beads/`, `.claude/`, etc. that downstream items reference),
then doc-drift items.

#### --apply-onboarding: walk the project-onboarder report

For each line whose `Suggested fix` text contains a literal
`[AUTOFIX:<recipe-id>]` token (substring match — exact bracketed
form), apply the recipe:

> **Guest-mode gate (loom-3r8).** The read-only scan that produced
> this report ALWAYS runs (Diataxis-shape detection, drawer-citation
> probes, etc. don't touch the tree). But every AUTOFIX recipe below
> writes into the project tree, so each one MUST source
> `lib/refuse-on-guest.sh` and call `refuse_if_guest AUTOFIX:<recipe-id>`
> before doing any in-tree work. If the call returns 1, skip that
> item with a one-line note (`AUTOFIX:<id>: skipped — guest mode
> active`) and continue to the next item. The check is per-item, not
> per-run, so a future AUTOFIX recipe that's safe under guest mode
> (e.g. external-only) can opt out simply by omitting the call.

- **`[AUTOFIX:bd-hooks]`** — gate first, then execute:
  ```bash
  . "$LOOM_ROOT/lib/refuse-on-guest.sh"
  refuse_if_guest AUTOFIX:bd-hooks || exit $?
  cd <root> && bd hooks install
  cd <root> && git add .beads/issues.jsonl 2>/dev/null
  cd <root> && git -c core.hooksPath=/dev/null commit -m "bd: post-install export sync" 2>/dev/null \
    || echo "(nothing to absorb — fresh .beads/ already clean)"
  ```
  The `core.hooksPath=/dev/null` override on the absorbing commit
  prevents the just-installed pre-commit hook from re-firing on its
  own export — it's the chicken-and-egg break the loom-cka two-step
  is meant to dodge. If the absorbing commit has no staged content,
  emit a one-line "(nothing to absorb)" note and continue.

- **`[AUTOFIX:workflow-json]`** — gate first
  (`refuse_if_guest AUTOFIX:workflow-json`), then write
  `{"v":1,"mode":"<mode>"}` (where `<mode>` defaults to `full`, or
  the value passed via `--workflow-mode`) to
  `<root>/.claude/workflow.json`. Create `<root>/.claude/` if it
  doesn't exist. Do NOT overwrite an existing file — re-check the
  presence first; if the file appeared between the scan and apply
  step (race), skip with a note.

- **`[AUTOFIX:gitignore-worktrees]`** — gate first
  (`refuse_if_guest AUTOFIX:gitignore-worktrees`), then append the
  line `.claude/worktrees/` to `<root>/.gitignore` (creating the file
  if absent). Idempotent: re-read the file first; skip if the entry
  is already present (any of `.claude/worktrees`,
  `.claude/worktrees/`, `/.claude/worktrees/`, etc.).

For each item NOT carrying an `[AUTOFIX:<id>]` tag, leave it in the
queue for Step 4. Emit one summary line per skipped item: `--apply-
onboarding: skipping item N (no AUTOFIX tag — requires human review)`.

#### --apply-trivial: walk the docs-drift section

For each line tagged `[DOC FIX][TRIVIAL]`, apply the suggested
substitution:

- The `suggested:` field for TRIVIAL items is always shape
  `s/<old>/<new>/`. Use the `Edit` tool against the file at the
  `doc:` field's `<file>:<line>` location; pass the verbatim
  doc-line text (read fresh — file may have shifted) as `old_string`
  and the substituted text as `new_string`.
- Re-read the file before each Edit to defend against line-number
  drift; if the verbatim text from the report no longer appears in
  the file, skip the item with a note `--apply-trivial: skipping
  <file>:<line> (text drifted between scan and apply)`.

For each `[DOC FIX]` line WITHOUT the `[TRIVIAL]` qualifier, leave
it in the queue for Step 4. Emit one summary line per skipped item:
`--apply-trivial: skipping <file>:<line> (no TRIVIAL tag — requires
human review)`.

#### Apply-step output

Print a `## Auto-applied` section listing every change made:

```
## Auto-applied

[AUTOFIX:bd-hooks] @ <root>
  - ran `bd hooks install` → wrote .beads/hooks/pre-commit + post-commit
  - absorbed export queue: 1 commit `bd: post-install export sync`

[AUTOFIX:workflow-json] @ <root>/.claude/workflow.json
  - wrote {"v":1,"mode":"full"}

[AUTOFIX:gitignore-worktrees] @ <root>/.gitignore
  - appended `.claude/worktrees/`

[DOC FIX][TRIVIAL] cardinality @ README.md:42
  - s/(105 dirs)/(106 dirs)/

[DOC FIX][TRIVIAL] cardinality @ docs/index.md:78
  - s/Prelude (4)/Prelude (5)/

(N items skipped — see "--apply-* skipping" notes above)
```

#### What this step does NOT do

- **Does not commit.** Git is left in a dirty state for the user to
  review with `git diff` / `git status` and commit (or revert)
  themselves. The `[AUTOFIX:bd-hooks]` recipe is the one exception
  — it MUST commit the absorbing commit because the bd hook needs
  to fire once on a clean queue before the user's first logical
  commit (loom-cka). That commit is intentional, scoped, and
  message-tagged.
- **Does not run the project's test suite.** The user verifies post-
  apply.
- **Does not retry on failure.** A failed Edit / Bash / Write step
  emits one error line and continues to the next item; the
  per-item approval queue in Step 4 still has the failed items for
  manual handling.
- **Does not touch WARN items.** Onboarding WARNs (item 1 dirty
  tree, item 4 malformed workflow.json, etc.) imply real conflict
  — apply flags never auto-resolve them.

### Step 4 — present combined report + drive interactive fixes

Produce one combined report:

```markdown
# Project audit: <project-short-name>

## Pre-flight warnings
<[WING WARN] line from Step 1b, if any; omitted when wing was
explicit or when no basename-variant has more drawers>

## Onboarding
<verbatim project-onboarder report, if run>

## Docs drift detection
<list of [DOC FIX] lines, if run; "no drift detected" otherwise>

## Auto-applied
<output of Step 3.5, if --apply-trivial and/or --apply-onboarding
fired and any items applied; omitted otherwise>

## Summary
PASS: <N> · WARN: <N> · MISS: <N> · [DOC FIX]: <N>
auto-applied: <K> · skipped (untagged): <S>
Top 3 gaps to fix first: <ordered short list>
```

For each non-auto-applied gap, ask the user:

> Item: <one-line>. Apply suggested fix? (yes / skip / edit)

**Invariant (loom-xcw): the per-item gate is a conversational pause,
not a tool-permission prompt.** Two distinct gates can be confused
here:

- **TOOL permission** — Claude Code's built-in prompt before
  Write/Edit/Bash. `--dangerously-skip-permissions` silently
  auto-accepts this gate. It is about which tools the harness is
  allowed to invoke, not about whether the USER approved the change.
- **USER approval** — the per-item question above. This is a real
  conversational pause that requires a user-typed reply ("yes",
  "skip", or "edit"). `--dangerously-skip-permissions` MUST NOT
  auto-resolve this gate; running with it does NOT imply blanket
  user consent.

The two gates are NOT interchangeable. A session with
`--dangerously-skip-permissions` set still owes the user an explicit
yes/skip/edit reply per item — the flag only removes the
tool-permission friction layer, never the user-approval layer.

**Execution rule.** After printing the prompt, STOP. Do NOT call
any tool (no Edit, no Write, no Bash, no further analysis) until
the user replies with a message containing one of `yes` / `skip` /
`edit`. Treat the next user message as the answer; if the user's
reply is ambiguous, re-prompt rather than guessing. This is the
fix for the loom-wxo / loom-xcw symptom where three items applied
without an intervening user turn.

On `yes`: generate the fix (template for onboarding gaps; surgical
edit for docs drift), preview the diff, then write to disk.
On `skip`: move on. On `edit`: ask the user for the corrected text
and use that.

Never auto-apply a fix outside `--apply-trivial` / `--apply-onboarding`
scope. The skill is a co-pilot for cleanup, not an autonomous editor.

### Step 5 — capture findings to `<wing>/decisions`

When the audit produces non-trivial findings (any `WARN` / `MISS` /
`[DOC FIX]` / `[DOC SKIP]` lines), file a single drawer summarising
the audit. **The drawer always goes to `<wing>/decisions`.**
`<wing>` is the resolved wing from Step 1 (the `--wing` value).

This is hardcoded — the skill does not create per-audit rooms
(`audit_results`, `findings`, `gaps`, etc.). Every loom-managed
project's MemPalace wing carries a `decisions` room by convention;
audit findings ARE decisions about project state, so they live
there alongside design decisions. (loom-lpy.)

Drawer shape:

- **Title:** `Project audit: <project-short-name> (<YYYY-MM-DD>)`.
  The "this is an audit" semantic is carried by the title, not by
  the room name.
- **Content:** the combined report from Step 4 verbatim, plus a
  short "what to do next" section listing the top gaps by severity
  and any beads filed against them.
- **Wing/Room:** `<wing>/decisions` (hardcoded).

If the MemPalace stop-hook auto-files the audit findings as part of
session checkpointing, the auto-file MUST honour the same
destination — do not let the hook create a separate
`<wing>/audit_results` or `<wing>/findings` room. If the hook
defaults elsewhere, override with an explicit
`mempalace_add_drawer(wing=<wing>, room='decisions', ...)` call
before the hook fires.

Migration of pre-loom-lpy drawers (e.g. drawers in
`tla_puzzles/audit_results` and `tla_puzzles/findings` from the
loom-b6o trial) is out of scope for this skill — those remain as
historical artifacts. The new convention applies to all future
audits.

## Output format (drift items)

One line per drift item, prefix-tagged. Concrete examples:

```
[DOC FIX] cardinality
  doc:        docs/reference/manual.md:432 "All three commands have disable-model-invocation"
  reality:    6 commands match commands/*.md; 6 of 6 have the flag
  suggested:  s/All three/All six/

[DOC FIX] dead-bead-id
  doc:        docs/explanation/provenance.md:117 cites `loom-xyz`
  reality:    bd show loom-xyz → not found (no superseded-by metadata)
  suggested:  remove citation, or file a bead to recreate the lineage

[DOC FIX] missing-primitive
  doc:        docs/reference/installed-files.md:40 lists `skills/audit-project/SKILL.md`
  reality:    skills/audit-project/SKILL.md does not exist
  suggested:  ship the SKILL.md (file a bead) OR remove the line

[DOC FIX] catalog-ghost
  doc:        docs/reference/skills/index.md row "audit-project"
  reality:    skills/audit-project/SKILL.md does not exist
  suggested:  remove the row, or ship the SKILL.md

[DOC FIX] missing-drawer-citation
  doc:        docs/explanation/recipe-family.md:23 cites drawer "RECIPE SHAPES — ACTIVITY MATRIX"
  reality:    mempalace_search returned no strong match
  suggested:  fix the slug, or capture the drawer if the design is unrecorded

[DOC SKIP][GENERATED] docs/ is generated — skipping cardinality (docs/ scope)
  reason:    Signal 1: docs/ matches .gitignore entry 'docs/' in .gitignore
  pointer:   edit the source named in the build script, not docs/
             (root README.md remains in scope and is checked normally)
```

## What this skill does NOT do

- **Does not write to disk without user approval** (except for
  `--apply-trivial` / `--apply-onboarding` items where the user
  has pre-authorized the AUTOFIX-tagged class by passing the flag).
- **Does not run `bd init`** (interactive — requires the user to
  acknowledge the workspace prompt). Even with `--apply-onboarding`,
  item 2 MISS stays in the per-item queue.
- **Does not write to MemPalace.** Even with `--apply-onboarding`,
  item 5 MISS (no project-named wing) stays in the per-item queue —
  wing creation is a per-user MCP-server operation, not a script
  recipe.
- **Does NOT run `bd hooks install` or write `workflow.json` /
  `.gitignore` without `--apply-onboarding`.** When the flag is set,
  the AUTOFIX recipes in Step 3.5 do these writes; without it, the
  skill emits the suggested-fix line and waits for per-item approval.
- **Does not perform semantic claim extraction in v1.** "X does Y"
  claims with verb-level disagreement (the doc says "fires on
  X" but the hook fires on Y) are out of scope. v2 may add LLM-
  assisted claim extraction; v1 is grep + filesystem + bd + MCP
  resolution.
- **Does not modify beads or MemPalace state.** Read-only against
  `bd show` and `mempalace_get_drawer` / `mempalace_search`.
- **Does not exceed the report cap** of 250 onboarding lines + 250
  drift lines. If drift output would exceed the cap, emit the top
  250 by sort order (file path, then line) and a final line
  `[DOC FIX] truncated · <K> more · re-run with --check=docs
  --full-output for everything`.

## Why this exists

The v1 onboarding scan caught wiring gaps but assumed `docs/` was
truthful. Two bug classes proved that assumption wrong:

- **loom-469** (cardinality drift) — the manual claimed "All three
  commands have `disable-model-invocation`" while six commands
  shipped. The claim was true at write time and silently false
  three commits later.
- **loom-qj3** (lying-doc) — docs cited a `/feature-a-bead`
  command that didn't exist; cited primitives that had been
  renamed; cited bead IDs that no longer resolved. Each individual
  drift was small, but they accumulated faster than humans noticed
  during review.

The docs check exists because the human review pass at PR time is
the wrong layer to catch this kind of drift — it's mechanical and
should be mechanized. Running it at audit time, default-on for
projects with a Diataxis substrate, surfaces drift at the moment
when there's budget to fix it.

The precedence rule (`docs lose`) is what makes the check tractable.
If docs and reality disagreed in either direction the check would
need a tie-breaker for every item; with the rule fixed in advance,
every drift item is a doc fix and the check can run unattended for
trivial cases.

## Related infrastructure

- Slash command: `commands/audit-project.md` — manual-only entry
  point with `disable-model-invocation: true`. The slash command
  forwards `--root`, `--wing`, `--check`, `--apply-trivial`,
  `--apply-onboarding`, and `--workflow-mode` to this skill.
- Subagent: `agents/project-onboarder.md` — read-only scanner the
  skill dispatches in step 2. The subagent already takes the
  project root + short name as inputs, so portability flows
  through unchanged.
- Companion how-to: `docs/how-to/where-to-update-what.md` — when a
  human is the one fixing a drift item, this is the page that
  tells them which surface to update.
- Locked design lives in MemPalace: `loom/decisions` wing —
  drawer for the loom-9z1 epic (Diataxis docs restructure + drift
  defenses) plus drawer `drawer_loom_decisions_63aadc6e849779a509678d90`
  (loom-9z1.10 D1 plan §A.4 — the portability spec implemented
  by loom-km8.4).
