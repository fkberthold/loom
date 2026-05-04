---
name: audit-project
description: Audit the current project's workflow infrastructure (git/branch hygiene, beads init, bd hooks, workflow.json, MemPalace wing, CLAUDE.md, .claude/rules/, .claude/agents/+commands/, bd memories) and — for loom-managed projects — the docs/system/beads/MemPalace alignment of the project's documentation. Drives the project-onboarder subagent, presents the structured checklist to the user, and offers interactive template-based fixes per gap. Manual-only — never auto-suggested by session-startup or any activity recipe; only fires when the user invokes `/audit-project`.
---

# Audit-Project — Project Onboarding + Drift-Detection Skill

This skill is the driver behind the `/audit-project` slash command.
It coordinates two responsibilities, run sequentially in one session:

1. **Onboarding scan** — dispatch the `project-onboarder` subagent to
   scan workflow-infrastructure setup (git hygiene, beads, hooks,
   `workflow.json`, MemPalace wing, `CLAUDE.md`, rules dir, `bd
   memories`) and return a `PASS`/`WARN`/`MISS` checklist. This is
   the v1 behavior shipped 2026-05-03.
2. **Docs drift detection** — for loom-managed projects, compare
   `docs/` against the system (filesystem primitives), beads
   (`bd show`), and MemPalace (`mempalace_*`) and report
   doc-vs-reality drift. This is the v2 behavior gated by
   `--check=docs` (default-on for loom-managed projects).

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
- `--check=all` (default for loom-managed projects) — run both.
- `--apply-trivial` — auto-apply the two trivial doc fixes:
  cardinality count corrections (the loom-469 class) and dead
  bead-ID replacement using the supersedes-chain. Larger fixes
  still require per-item user approval.

If no flag is given, the default is `--check=all` for projects
that look loom-managed (heuristic: `.beads/` exists AND `docs/`
contains at least one Diataxis quadrant directory — `tutorials/`,
`how-to/`, `reference/`, or `explanation/`). For other projects
the default is `--check=onboarding` to preserve v1 behavior.

## The Sequence

### Step 1 — resolve project root + flags

Read the project root from the user's invocation (default: current
working directory's git root). Parse flags. Decide whether the docs
check runs (loom-managed heuristic above, or explicit
`--check=docs|all`).

Detect "loom-managed" by checking the project root for: `.beads/`
present AND `docs/` containing at least one of `tutorials/`,
`how-to/`, `reference/`, `explanation/`. If both conditions hold,
the docs check defaults on; otherwise it defaults off.

### Step 2 — dispatch project-onboarder (unless `--check=docs`)

Call the `project-onboarder` subagent with the absolute project
root and (if known) the project's short name. Wait for its
structured `PASS`/`WARN`/`MISS` checklist. Display the report
verbatim before moving to step 3.

### Step 3 — docs drift detection (unless `--check=onboarding`)

Run the five sub-checks below in order. Each produces zero or more
report lines tagged `[DOC FIX]`, with three fields:

- **what doc says** — the verbatim claim (or path) the doc makes
- **what reality says** — what the system / beads / palace shows
- **suggested fix** — the minimal edit that resolves the drift

Lines accumulate into one report section labeled `## Docs drift
detection`. Empty section = clean.

#### Check 1 — Cardinality

Find numeric claims in `docs/` that count primitives. For v1 the
patterns are naive grep:

- `All (one|two|three|four|five|six|seven|eight|nine|ten|N+) <noun>`
- `<digit>+ (skills|commands|subagents|hooks|recipes|drawers|wings)`
- `(only|just|exactly) <digit>+ <noun>`

For each match, identify the noun and source-of-truth glob:

| Noun | Source-of-truth |
|---|---|
| `skills` / `recipes` | `skills/*/SKILL.md` |
| `commands` / `slash commands` | `commands/*.md` |
| `subagents` / `agents` | `agents/*.md` |
| `hooks` | `hooks/*.sh` |
| `wings` / `rooms` | `mempalace_list_wings` / `mempalace_list_rooms` |

Compare the doc's count to the actual count. Mismatch → emit:

```
[DOC FIX] cardinality
  doc:        <file>:<line> "All <N> <noun> have <claim>"
  reality:    <M> <noun> match <glob> (or N matches but K satisfy <claim>)
  suggested:  s/<N>/<M>/ (or rewrite to enumerate which <K> satisfy)
```

This catches the loom-469 class. If `--apply-trivial` is set AND
the only difference is the numeral, apply the substitution
automatically and add a `[DOC FIX][AUTO-APPLIED]` line.

#### Check 2 — Citation resolution

Every citation in `docs/` must resolve. Scan for:

- **Bead IDs** — pattern `<prefix>-[a-z0-9]{3,}` where `<prefix>`
  matches the project's bd prefix (loom: `loom-`; HAW: `haw-` or
  `hundred-acre-woods-`; etc.). For each match, run
  `bd show <id> 2>&1`. Failure → emit `[DOC FIX] dead-bead-id`.
- **Commit SHAs** — pattern `\b[0-9a-f]{7,40}\b` adjacent to
  "commit" / "sha" / git context. For each match, run
  `git cat-file -e <sha> 2>&1`. Failure → emit `[DOC FIX]
  dead-commit`.
- **File paths** — pattern that looks like a path inside the repo
  (starts with `skills/`, `commands/`, `agents/`, `hooks/`,
  `docs/`, `lib/`, `scripts/`, etc., and ends in a known
  extension or directory marker). For each match, check
  filesystem. Missing → emit `[DOC FIX] missing-path`.
- **Drawer slugs** — any reference to a MemPalace drawer by slug
  or title. Pattern: text inside backticks adjacent to "drawer" /
  "MemPalace" / "wing/" / "decisions" — admittedly fuzzy in v1.
  For each candidate, call `mempalace_search "<slug-or-title>"`
  and emit `[DOC FIX] missing-drawer` if nothing returns a strong
  match.
- **Slash command names** — pattern `/[a-z0-9-]+\b`. For each
  match, check `commands/<name>.md` exists. Missing → emit
  `[DOC FIX] missing-slash-command`.

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
if so, suggest the replacement ID. If `--apply-trivial` is set
AND the supersedes-chain yields a unique replacement, apply the
substitution automatically.

This catches the loom-qj3 lying-doc class for the citation
sub-class.

#### Check 3 — Behavior claims

Doc says X exists / X does Y. Verify against system reality. v1
naive: scan for sentences of shape:

- ``\`<token>\` (exists|is shipped|ships|is installed|carries)``
- ``\`<token>\` (does|fires|invokes|dispatches) <claim>``

For tokens that name a primitive (`/foo` → command,
`<name>-a-bead` → skill, `<name>-researcher` → subagent,
`<name>.sh` → hook), check the corresponding source file:

- `/<name>` → `commands/<name>.md`
- `<name>-a-bead` (without slash) → `skills/<name>-a-bead/SKILL.md`
- bare hook name `<x>.sh` → `hooks/<x>.sh`
- bare subagent name (matches an `agents/*.md` basename) → that
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

For each catalog page in `docs/reference/`:

| Catalog page | Source glob |
|---|---|
| `docs/reference/skills/index.md` | `skills/*/SKILL.md` |
| `docs/reference/slash-commands/index.md` | `commands/*.md` |
| `docs/reference/subagents/index.md` | `agents/*.md` |
| `docs/reference/hooks/index.md` | `hooks/*.sh` |

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

Every page under `docs/explanation/` cites at least one MemPalace
drawer (the design-source-of-truth claim from
`docs/explanation/provenance.md` and the recipe-family doc).
For each citation:

- Exact slug → `mempalace_get_drawer(slug)`. Hit → PASS.
- Title-shaped citation → `mempalace_search(title)`. Top result
  with high similarity → PASS. No strong match → emit `[DOC FIX]
  missing-drawer-citation`.

This is a v1 best-effort check — drawer citation in prose is
unstructured, so the patterns are fuzzy. If the project uses a
convention like `> Drawer: <wing>/<slug>` or footnote-style
citations, prefer those structured patterns and skip free-text
matching.

### Step 4 — present combined report + drive interactive fixes

Produce one combined report:

```markdown
# Project audit: <project-short-name>

## Onboarding
<verbatim project-onboarder report, if run>

## Docs drift detection
<list of [DOC FIX] lines, if run; "no drift detected" otherwise>

## Auto-applied
<list of [DOC FIX][AUTO-APPLIED] lines, if --apply-trivial and any
fired>

## Summary
PASS: <N> · WARN: <N> · MISS: <N> · [DOC FIX]: <N>
Top 3 gaps to fix first: <ordered short list>
```

For each non-auto-applied gap, ask the user:

> Item: <one-line>. Apply suggested fix? (yes / skip / edit)

On `yes`: generate the fix (template for onboarding gaps; surgical
edit for docs drift), preview the diff, then write to disk.
On `skip`: move on. On `edit`: ask the user for the corrected text
and use that.

Never auto-apply a fix outside `--apply-trivial` scope. The skill
is a co-pilot for cleanup, not an autonomous editor.

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
```

## What this skill does NOT do

- **Does not write to disk without user approval** (except for
  `--apply-trivial` items where the user has pre-authorized the
  trivial-fix class by passing the flag).
- **Does not run `bd init`, `bd hooks install`, or any MemPalace
  write.** Onboarding fixes are templated; the user applies them.
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
loom-managed projects, surfaces drift at the moment when there's
budget to fix it.

The precedence rule (`docs lose`) is what makes the check tractable.
If docs and reality disagreed in either direction the check would
need a tie-breaker for every item; with the rule fixed in advance,
every drift item is a doc fix and the check can run unattended for
trivial cases.

## Related infrastructure

- Slash command: `commands/audit-project.md` — manual-only entry
  point with `disable-model-invocation: true`.
- Subagent: `agents/project-onboarder.md` — read-only scanner the
  skill dispatches in step 2.
- Companion how-to: `docs/how-to/where-to-update-what.md` — when a
  human is the one fixing a drift item, this is the page that
  tells them which surface to update.
- Locked design lives in MemPalace: `loom/decisions` wing, drawer
  for the loom-9z1 epic (Diataxis docs restructure + drift
  defenses).
