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
- `--check=constitution` — run ONLY the project-constitution capture
  flow (Step 7 below): detect the project's tooling fingerprint,
  render draft front-matter, confirm each field with the user **one
  field at a time** (never lump-sum, per loom-xcw), write
  `.claude/project-constitution.md` UNSTAGED, mirror to the
  `<wing>/decisions` MemPalace drawer, and emit KG triples for the
  tooling. The prose body is emitted as a `[HUMAN AUTHOR]` TODO stub —
  **never agent-authored** (loom-d50). On re-run, detection is diffed
  against the captured file and per-field drift is surfaced without
  overwriting the prose body. This mode runs neither the onboarding
  scan nor the docs check — it is the loom-6f8 Constitution epic's
  capture half (loom-1iz). The schema, dogfooded sample, and field
  reference were shipped by loom-vin
  (`references/project-constitution.schema.json`,
  `templates/project-constitution.md`,
  `docs/reference/project-constitution.md`).
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
  - `[AUTOFIX:gitignore-worktrees]` (item 11 INFO) — appends BOTH
    `.claude/worktrees/` and `.claude/workflow-state.json` to
    `<root>/.gitignore` if not already present. Idempotent per
    line. Both are per-session loom ephemera that show up at the
    root of every loom-managed project; folded into one recipe by
    loom-tat after both customer trials (loom-b6o, loom-wxo)
    handled the workflow-state.json line manually.
  - `[AUTOFIX:loom-env-block]` (item 16 WARN/MISS) — deep-merges
    the canonical loom env block (`CLAUDE_CODE_ENABLE_TASKS=false`,
    `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`) into
    `<root>/.claude/settings.json`, overwriting only those two keys
    and preserving every other key. Writes
    `.claude/settings.json.pre-loom.bak` on first overwrite.
    Idempotent — re-running against a canonical file is a no-op
    that does not touch the backup. Counters the harness's
    competing TaskCreate / MEMORY.md defaults on the per-project
    layer (loom-7ro).
  - `[AUTOFIX:loom-upstream-gc-handoff]` (item 17 INFO) — handoff
    recipe for orphan clones under `~/.loom/upstream/<owner>/<repo>/`
    with no matching open `upstream:watch` bead. The recipe does
    NOT prune directly — actual removal is per-clone y/N gated
    inside `/loom-upstream-gc`. The recipe prints the handoff
    message `orphan clones detected; run /loom-upstream-gc to
    review and prune interactively` and marks the row as queued-
    for-user. The handoff tag exists so `--apply-onboarding`
    visibly resolves the row rather than silently leaving it in
    the per-item queue (loom-k2g).
  - `[AUTOFIX:gh-auth-prompt]` (item 18 WARN) — handoff recipe for
    unauthenticated `gh` (`gh auth status` non-zero exit). The
    recipe does NOT attempt the OAuth flow — `gh auth login` is
    interactive and cannot run inside the audit. The recipe prints
    `gh is not authenticated; run \`gh auth login\` interactively
    to fix` and marks the row as queued-for-user. Same handoff-tag
    rationale as item 17 (loom-k2g).
  - `[AUTOFIX:dedup-hook-skip-worktree]` (item 12 WARN — the
    **DEFAULT** offer for a duplicate hook) — when item 12 reports a
    project-tracked SessionStart/PreToolUse hook that is ALSO
    registered by the plugin or user-global layer, this recipe
    resolves the duplicate **per-user and reversibly**:
    1. `git update-index --skip-worktree <root>/.claude/settings.json`
       (so the local strip is untracked — git stops watching the file
       for changes, and a future upstream pull no longer errors with
       "would be overwritten by checkout"),
    2. strip the duplicate `(event, matcher, command)` stanza from the
       local copy of `.claude/settings.json`,
    3. log the recovery snippet (below) to
       `<root>/.claude/loom-audit-state.json` under the
       `dedup-hook-skip-worktree` key, for the inevitable next upstream
       change to the tracked file.
    Recovery snippet (baked into the AUTOFIX log so the next pull is
    not a surprise):
    ```bash
    git update-index --no-skip-worktree .claude/settings.json
    git stash
    git pull
    git stash pop
    # then re-apply skip-worktree + strip via /audit-project --apply-onboarding
    ```
    This is the **default** because it is per-user and reversible: it
    never changes shared content, so it cannot break a non-loom dev's
    setup. The detection mechanism (`find-hook-dups.sh`) is unchanged —
    this recipe only consumes its WARN output (loom-jnn).
  - `[AUTOFIX:dedup-hook-commit]` (item 12 WARN — gated behind an
    explicit y/N confirmation) — the same detection, the opposite
    resolution: remove the duplicate hook stanza from the **tracked**
    `.claude/settings.json` and commit. Because this changes shared
    content, the binary `apply` shape does NOT fit — the recipe
    plumbs a confirmation prompt through and is **NOT auto-applied**
    on `--apply-onboarding`. The prompt names the consequence
    verbatim: `This commits a change to .claude/settings.json that
    assumes loom adoption for all devs on this repo. Non-loom devs
    lose <hook-name> registration. Proceed? (y/N)`. Only on a typed
    `y` does it commit with subject `audit: dedup <hook-name>
    SessionStart hook (loom-managed; plugin + user-global handle
    registration)`. The empirical reason a resolution path is needed
    at all: hook layering is **additive across all four layers**
    (plugin + user-global + project-tracked + project-local) — empty
    arrays in `settings.local.json` do NOT cancel an inherited
    registration, they only add zero entries to the union. Verified
    inert in e2e-api-tests 2026-05-27 (bd prime still fired 3 times in
    a fresh SessionStart after the override). See
    [`docs/reference/claude-code-hook-layering.md`](../../docs/reference/claude-code-hook-layering.md)
    for the full finding (loom-jnn).
  Items NOT tagged AUTOFIX (item 2 `bd init`, item 5 MemPalace wing
  creation, item 6 CLAUDE.md authoring, item 7 `.claude/rules/`)
  remain in the per-item approval queue. The flag never touches
  WARN items (those imply real conflict — dirty tree, malformed
  workflow.json, etc. — and need human triage). Items 17 and 18
  are exceptions to the WARN-untouched rule because they resolve
  by handoff (not by in-process write); the handoff message itself
  IS the resolution.
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
- `--mine-history` — after the audit report is presented, delegate to
  the `/loom-mine-history` skill to mine the project's git/PR history
  for unmined decisions (drawers + KG triples), behind its own
  mandatory two-pass cost gate. Runs against the resolved `--root` /
  `--wing`. WITHOUT this flag the audit only *flags* the gap
  informationally — the `project-onboarder` decision-history line
  reports the unmined-unit count, and the audit **never auto-mines**
  (mining is an explicit, billable action the user opts into). See
  "Step 6 — optional history mining" below.

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

**Run the resolution helper first.** Invoke
`scripts/loom-audit-resolve [--root <path>] [--wing <name>]` (passing
through whatever `--root`/`--wing` the user gave) and read its
`key=value` stdout:

```
root=<abs path>              # resolved per the precedence below
wing=<name>                  # basename verbatim, or explicit --wing
primitives=<csv>             # which of skills,commands,agents,hooks exist
diataxis_optout=<0|1>        # <root>/docs/.no-diataxis present
loom_managed=<0|1>           # .beads/ AND a docs Diataxis quadrant
```

This helper computes the deterministic resolution prelude
(unit-tested at `lib/tests/loom-audit-resolve.test.sh`), so the rules
below are documentation of what it does — **do not re-derive them by
hand**; consume the helper's output. In particular the wing default is
the basename **verbatim** (no `_`↔`-` substitution, no case-folding),
the only rule correct for both underscore wings (`liza_base`) and dash
wings (`golden-path`); Step 1b's variant-WARN backs this up for the
divergence cases.

For reference, the precedence the helper implements:

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

The onboarder enumerates 20 items including git hygiene, bd init,
bd hooks, workflow.json, MemPalace wing, CLAUDE.md, `.claude/rules/`,
docs scaffold, `.claude/agents/+commands/`, `bd memories` tribal
facts, `.gitignore` loom-ephemera entries, the `.deploy` wrap-up
hint (item 21, loom-1tq), and — added by loom-ann —
**Claude Code hook command duplicates**: the same `(event, matcher,
command)` tuple registered in both the project's
`.claude/settings.json` (or `~/.claude/settings.json`) and a plugin's
`plugin.json`. Duplicates fire the command twice per event, billing
wasted tokens (observed in liza_base 2026-05-09; fixed via loom-sd5
by removing the project-layer entry — the plugin's registration is
canonical). Project-level dups surface as WARN; user-level dups as
INFO (machine-specific config, advisory only).

The duplicate JSON-stanza removal is content-aware (multiple hook
entries may share a stanza), so the *raw* removal was excluded from
the Wave 2 deterministic-apply contract. loom-jnn closes the
resolution gap with two purpose-built AUTOFIX paths for the WARN
case (detection via `find-hook-dups.sh` is unchanged): the DEFAULT
`[AUTOFIX:dedup-hook-skip-worktree]` (per-user, reversible —
`git update-index --skip-worktree` the tracked file + strip the dup
locally + log the recovery snippet), and the opt-in
`[AUTOFIX:dedup-hook-commit]` behind an explicit y/N confirmation
that names the shared-content consequence. The empirical reason a
resolution is needed at all — empty-array overrides in
`settings.local.json` do NOT cancel inherited hook registrations
because Claude Code hook layering is **additive across all four
layers** — lives in
[`docs/reference/claude-code-hook-layering.md`](../../docs/reference/claude-code-hook-layering.md).

#### Items 13–15, 21: interactive-resolution checks (loom-r6g, loom-z3m, loom-1tq)

The onboarder also runs several checks that surface defaults wrong
for the project's shape (or fields the user has never been asked
about) but require interactive resolution. The skill (this file)
owns the prompt loop and the write half; the onboarder only reports
the verdict. Items 13–14 (language + solo-workspace) are loom-r6g,
item 15 (upstream:loom label) is loom-z3m.11, and item 21 (`.deploy`
wrap-up hint) is loom-1tq.

##### Item 13 — `preflight-language-match`

The onboarder describes `detect_project_language()` (canonical
markers: pyproject.toml/setup.py/setup.cfg/requirements*.txt →
python; go.mod → go; Cargo.toml → rust; package.json → node;
scripts/+*.sh fallback → shell; otherwise / polyglot → unknown).
Tie-break rule: never guess on polyglot. The onboarder reads
`<root>/.beads/preflight.template` (or `config.yaml`'s
`preflight.template` field) for the bd preflight shape.

Verdicts the onboarder emits, and the skill's response:

- **PROMPT** (language=unknown AND preflight.template unset / bd-default).
  The skill prompts the user interactively:

  ```
  Item 13: project language is unknown and preflight.template is
  unset / bd-default Go-shaped. Pick a language for the preflight
  template: (python / go / rust / node / shell / skip)
  ```

  On a non-skip answer the skill writes the matching template into
  `.beads/preflight.template` (or the equivalent field in
  `config.yaml`). On `skip`, the skill writes a per-check memo into
  `<root>/.claude/loom-audit-state.json` so future runs render this
  row as a silent PASS.

- **WARN** (language ∈ {python, rust, node, shell} AND
  preflight.template starts with `go ` or is the bd-default
  Go-shaped template). The skill offers a y/N/skip diff preview
  showing the proposed template replacement. On `y` it writes; on
  `N` it leaves the row in the queue; on `skip` it writes the
  state-file memo. The skill does NOT add a new AUTOFIX recipe —
  the choice of replacement template is content-aware and stays in
  the per-item conversational gate.

- **PASS** otherwise.

Test mocking surface: the env var `LOOM_AUDIT_PROMPT_ANSWER` lets
test fixtures inject the PROMPT/WARN answer non-interactively (e.g.
`LOOM_AUDIT_PROMPT_ANSWER=python` or `LOOM_AUDIT_PROMPT_ANSWER=skip`).
The skill checks this env var first when running under tests; in
real interactive sessions it stays unset and the conversational
gate fires normally.

##### Item 14 — `claude-md-solo-aware`

The onboarder describes `is_solo_workspace()`: run
`bd dolt remote list --json`. `[]` → TRUE; non-empty (a `"name"`
field present) → FALSE; error → degrade-safe TRUE. When solo, the
onboarder scans `<root>/CLAUDE.md` for `bd dolt push` lines that
are NOT wrapped in the canonical loom-hsb guard.

The **canonical loom-hsb guard shape** (copy verbatim from loom's
own CLAUDE.md — do NOT paraphrase):

```bash
if bd dolt remote list --json 2>/dev/null | grep -q '"name"'; then
  bd dolt push
else
  echo "(solo bd workspace; no Dolt remote — skipping bd dolt push)"
fi
```

Verdicts:

- **WARN** (solo workspace AND unguarded `bd dolt push` present in
  CLAUDE.md's BEADS INTEGRATION block). The skill offers a y/N/skip
  diff preview that rewrites the canonical block to the loom-hsb
  guard shape. If the surrounding block has been hand-edited
  beyond pattern recognition (e.g., the surrounding `bd dolt push`
  is part of a larger custom workflow, or the lines around it
  don't match the canonical `bd init`-generated template), the
  fix refuses with a one-line pointer to loom's own CLAUDE.md
  ("Reference shape lives in loom/CLAUDE.md — copy by hand").
  `skip` writes the state-file memo for `claude-md-solo-aware`.

- **PASS** otherwise (no CLAUDE.md; no BEADS INTEGRATION block;
  block already uses the guard; skip memo exists;
  is_solo_workspace returned FALSE).

##### Item 15 — `upstream-loom-label-suggest`

Cross-tracker dependency hygiene. Project beads sometimes exist only
because of an open loom-side bug — the bead's life ends when the
loom fix lands, but there is no auto-clearing signal back to the
project's tracker. The `upstream:loom` label is the cross-tracker
handshake (see
[`docs/reference/upstream-loom-label.md`](../../docs/reference/upstream-loom-label.md)),
and this check surfaces candidate beads that should carry it.

The onboarder enumerates open project beads whose description matches
the canonical loom-keyword regex:

```
(^|[^a-zA-Z0-9_])(loom-hook|loom-script|loom-[a-z0-9]+)|hooks/|scripts/loom-
```

The word-boundary anchor on `loom-` prefix avoids matching substrings
inside other words (heirloom-data, etc.). The five canonical signals:

- `loom-hook` — bare token reference to a loom hook class
- `hooks/` — path prefix referring to loom's `hooks/` directory
- `loom-script` — bare token reference to a loom script class
- `scripts/loom-` — path prefix referring to loom's installed scripts
- `loom-<id>` — direct bead-ID reference (`loom-x4m`, `loom-z3m`, etc.)

Verdicts:

- **INFO** = at least one matching bead lacks the `upstream:loom`
  label. The skill renders the matching beads in a y/N/skip gate per
  bead — the user decides whether to apply the label. **Informational
  only — never auto-applies.** On `y` the skill runs
  `bd label add <id> upstream:loom`; on `N` it leaves the row in
  the queue; on `skip` it writes a `upstream-loom-label-suggest` memo
  to `.claude/loom-audit-state.json` so the same row does not re-prompt.
- **PASS** otherwise (no matching beads; all matching beads already
  carry the label; skip memo exists).

**No AUTOFIX tag** — applying the label per-bead is a real human
choice (the regex catches structural workaround beads, but also
catches beads that mention loom in passing without being a workaround).
The gate stays interactive.

The companion `/check-loom-upstream` slash command runs the same
sweep on-demand outside of an audit and additionally pairs labeled
beads against recently-closed loom beads — its output is a
suggestion-stream, never a write.

Lineage: loom-z3m.11 (2026-05-23). Surfaced by lingering HAW bead
`7iz` that mirrored what loom-x4m fixed; cleared by inspection only
because someone happened to remember the pairing. The label +
sweep + suggest-on-audit triad addresses the next sibling case
structurally.

##### Item 21 — `workflow-deploy-hint`

The `.deploy` field in `<root>/.claude/workflow.json` (loom-0k0) is
the shell command `/wrap-up` section 6 surfaces as `Next step
(project deploy): <cmd>` after a bead closes. It is optional and
silent-skip by default, which makes it undiscoverable until a user
reads the wrap-up source — this check surfaces it so the user can
set it (or explicitly opt out) at onboarding time. Mirrors the
`.guest`-block discovery + onboarding pattern (loom-4re).

The onboarder reads the field's three-state lifecycle
(`workflow_config_deploy_state` in `lib/workflow-config.sh`):
`set` (non-empty string), `empty` (`""`/`null` — explicit opt-out),
`absent` (key not present — never decided). The skill (this file)
owns the prompt loop and the write half; the onboarder only reports
the verdict.

Verdicts the onboarder emits, and the skill's response:

- **MISS** (`workflow.json` exists AND `.deploy` is `absent`). The
  skill prompts the user interactively with the loom-1tq prompt
  verbatim:

  ```
  Item 21: .deploy is unset in <root>/.claude/workflow.json. What
  command should /wrap-up surface as the project deploy hint? (e.g.
  ./install.sh, make deploy, ./scripts/build. Leave blank to
  explicitly opt out — sets .deploy: "".)
  ```

  On a **non-blank** answer the skill writes the command verbatim via
  `workflow_config_deploy_set "<command>" <root>` — no validation, no
  auto-detection (both out of scope, loom-1tq). On a **blank** answer
  (the explicit opt-out) the skill writes `.deploy: ""` via
  `workflow_config_deploy_set "" <root>`; the empty string flips the
  state from `absent` to `empty` so future audits report PASS and do
  NOT re-prompt — empty means "explicitly chose nothing", distinct
  from absent's "never decided". Either write preserves `.mode`,
  `.v`, and any `.guest` block. On a literal `skip` answer the skill
  writes a `workflow-deploy-hint` skip memo into
  `<root>/.claude/loom-audit-state.json` so the row renders as a
  silent PASS on future runs.

- **N/A** (`workflow.json` doesn't exist). Item 4 already covers the
  missing-config case; the skill renders the row as `N/A` and takes
  no action. Do not write a `workflow.json` from this item — that is
  item 4's `[AUTOFIX:workflow-json]` job.

- **PASS** otherwise (state is `set` or `empty`, or a skip memo
  exists).

**No AUTOFIX tag** — the value is user-supplied (a command or an
explicit blank opt-out); there is no deterministic command to write,
so the fix stays in the per-item conversational gate. The
`LOOM_AUDIT_PROMPT_ANSWER` env var injects the answer
non-interactively under tests (same mocking surface as items
13/14): `LOOM_AUDIT_PROMPT_ANSWER='./install.sh'` simulates a typed
command, `LOOM_AUDIT_PROMPT_ANSWER=''` simulates the blank opt-out,
`LOOM_AUDIT_PROMPT_ANSWER=skip` writes the skip memo.

Lineage: loom-1tq (2026-06-08), parent finding
`drawer_loom_decisions_9fb2868e288751d22c6dd7ec` (loom-0k0). The
schema-write path is unit-tested at
`lib/tests/workflow-config-deploy.test.sh` (parallel to
`workflow-config-guest.test.sh`).

##### State file: `<root>/.claude/loom-audit-state.json`

Per-project, gitignored. Stores per-check skip memos so re-runs
respect "user said no". Schema:

```json
{
  "<check-name>": {
    "skipped_at": "<ISO-8601 timestamp>",
    "reason": "user-skipped"
  }
}
```

Recognised check-names: `preflight-language-match`,
`claude-md-solo-aware`, `upstream-loom-label-suggest`,
`workflow-deploy-hint` (item 21 — skip memo when the user declines to
set or opt out of `.deploy`), `dedup-hook-skip-worktree` (item 12 —
stores the recovery snippet applied by the default AUTOFIX, not a
skip memo). The skill
reads the file at the start of Step 2; for any check with a skip
memo, the onboarder's verdict is silently downgraded to PASS in the
rendered report. The `dedup-hook-skip-worktree` entry is a record of
the applied recovery snippet rather than a user-skipped memo — its
presence does not suppress the row, since a later upstream change to
`settings.json` may re-introduce the duplicate. The skill writes the memo on `skip` answers from
the per-item gate. The file is NOT a config file; it is never read
outside `/audit-project`, and the `<root>/.gitignore` adds
`.claude/loom-audit-state.json` on first audit so it stays out of
the project's history.

Lineage: loom-r6g (2026-05-21) for items 13-14. Surfaced by
/audit-project on fresh ~/repos/mforth: a Python solo project
passed every existing check while inheriting a Go preflight template
and an unguarded CLAUDE.md `bd dolt push`. The two checks are
conceptually "workflow-infrastructure language fit" plus "workflow-
infrastructure topology fit" — orthogonal to the existing 12 checks,
hence two new rows rather than expanding one. Item 15
(`upstream-loom-label-suggest`) added by loom-z3m.11 (2026-05-23)
to address the orthogonal "cross-tracker dependency awareness" gap.

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
  (`refuse_if_guest AUTOFIX:gitignore-worktrees`), then append BOTH
  of the per-session loom ephemera lines to `<root>/.gitignore`
  (creating the file if absent):
  - `.claude/worktrees/` — the dispatch-isolation path
    (`Agent` + `isolation: "worktree"`); never meant to be tracked.
  - `.claude/workflow-state.json` — per-session ephemeral state
    written at every session start by the loom statusline /
    `workflow-state` helper. Both customer trials (tla-puzzles
    loom-b6o, liza_base loom-wxo) hit this manually; loom-tat
    folded the line into the same recipe.
  Each line is appended INDEPENDENTLY and IDEMPOTENTLY — re-read
  the file first; for each candidate line, skip the append if it
  is already present (line-exact match against `.claude/worktrees/`
  or `.claude/workflow-state.json` respectively). A partial pre-
  existing state (only one of the two lines present) results in
  exactly the missing line being appended; the already-present
  line is never duplicated.

- **`[AUTOFIX:loom-env-block]`** — gate first
  (`refuse_if_guest AUTOFIX:loom-env-block`), then deep-merge the
  canonical loom env block into `<root>/.claude/settings.json`. The
  block:
  ```json
  {
    "env": {
      "CLAUDE_CODE_ENABLE_TASKS": "false",
      "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1"
    }
  }
  ```
  Loom owns these two keys — conflicts on them OVERWRITE; every
  other `env.*` key (and every non-env top-level key) is preserved
  verbatim. The merge uses the same python-shape as loom's own
  `install.sh` env-merge step (loom-7ro):
  ```bash
  mkdir -p "<root>/.claude"
  if [ ! -f "<root>/.claude/settings.json" ]; then
    cat >"<root>/.claude/settings.json" <<'JSON'
  {
    "env": {
      "CLAUDE_CODE_ENABLE_TASKS": "false",
      "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1"
    }
  }
  JSON
  else
    python3 - "<root>/.claude/settings.json" <<'PYEOF'
  import json, os, shutil, sys
  path = sys.argv[1]
  canonical = {
      "CLAUDE_CODE_ENABLE_TASKS": "false",
      "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1",
  }
  with open(path) as f:
      cur = json.load(f)
  cur_env = cur.get("env", {}) if isinstance(cur.get("env"), dict) else {}
  conflicts = [(k, cur_env[k], v) for k, v in canonical.items()
               if k in cur_env and cur_env[k] != v]
  additions = [k for k in canonical if k not in cur_env]
  if not conflicts and not additions:
      sys.exit(0)
  backup = path + ".pre-loom.bak"
  if not os.path.exists(backup):
      shutil.copy2(path, backup)
  merged = dict(cur_env)
  for k, v in canonical.items():
      merged[k] = v
  cur["env"] = merged
  with open(path, "w") as f:
      json.dump(cur, f, indent=2); f.write("\n")
  PYEOF
  fi
  ```
  Writes `.claude/settings.json.pre-loom.bak` on first overwrite (the
  python script handles the idempotency check internally — when both
  keys are already canonical the script exits without writing and
  without creating a backup). The lineage and motivation match loom's
  install.sh env-merge step: counters the harness's competing
  defaults (TaskCreate / MEMORY.md) on a per-project basis.

- **`[AUTOFIX:loom-upstream-gc-handoff]`** — handoff recipe; no
  in-tree write and no guest-mode gate needed (the recipe only
  prints text). For each orphan clone the onboarder reported under
  `~/.loom/upstream/<owner>/<repo>/`, the recipe emits:

  ```
  orphan clone: ~/.loom/upstream/<owner>/<repo>/
    no open upstream:watch bead references this clone
    run /loom-upstream-gc to review and prune interactively
  ```

  Then mark the item resolved-by-handoff so it does not re-surface
  in the per-item Step 4 queue. The actual prune lives in
  `/loom-upstream-gc` (loom-k2g.4) which gates per-clone with y/N
  and refuses removal when uncommitted changes are present.

- **`[AUTOFIX:gh-auth-prompt]`** — handoff recipe; no in-tree write
  and no guest-mode gate needed. Emit:

  ```
  gh is not authenticated (`gh auth status` exited non-zero):
    <verbatim gh auth status stderr from the onboarder report>
  run `gh auth login` interactively to authenticate
  ```

  Then mark the item resolved-by-handoff. `gh auth login` is an
  interactive OAuth/token flow that cannot run inside the audit;
  the user runs it in their own terminal, then re-runs
  `/audit-project` to confirm the WARN cleared.

- **`[AUTOFIX:dedup-hook-skip-worktree]`** — the default (DEFAULT)
  duplicate-hook resolution (item 12 WARN). Gate first
  (`refuse_if_guest AUTOFIX:dedup-hook-skip-worktree`), then resolve
  the duplicate **per-user and reversibly**:

  ```bash
  . "$LOOM_ROOT/lib/refuse-on-guest.sh"
  refuse_if_guest AUTOFIX:dedup-hook-skip-worktree || exit $?
  cd <root>
  # 1. Stop tracking local edits to the shared settings file. This
  #    ALSO defuses the "would be overwritten by checkout" error a
  #    future upstream pull would otherwise raise on the local strip.
  git update-index --skip-worktree .claude/settings.json
  # 2. Strip the duplicate (event, matcher, command) stanza from the
  #    LOCAL copy — content-aware JSON edit (the dup hook the item-12
  #    WARN line named; preserve every other stanza). Use the Edit
  #    tool / a python json rewrite, not a blind sed.
  # 3. Log the recovery snippet under the dedup-hook-skip-worktree key
  #    in .claude/loom-audit-state.json (see below).
  ```

  The recovery snippet baked into `.claude/loom-audit-state.json`
  (so the next upstream change to `settings.json` is not a surprise):

  ```bash
  git update-index --no-skip-worktree .claude/settings.json
  git stash
  git pull
  git stash pop
  # then re-apply skip-worktree + strip via /audit-project --apply-onboarding
  ```

  This recipe is safe to auto-apply on `--apply-onboarding` because it
  is per-user and reversible — it never touches shared content, so it
  cannot break a non-loom dev's checkout. It is the default offer for
  item 12. The state-file entry shape:

  ```json
  {
    "dedup-hook-skip-worktree": {
      "applied_at": "<ISO-8601 timestamp>",
      "hook": "<event> <command>",
      "recovery": "git update-index --no-skip-worktree .claude/settings.json; git stash; git pull; git stash pop"
    }
  }
  ```

- **`[AUTOFIX:dedup-hook-commit]`** — the OPT-IN duplicate-hook
  resolution (item 12 WARN) that **never auto-applies** without an
  explicit y/N confirmation. This recipe changes **shared content** (it removes the
  duplicate stanza from the *tracked* `.claude/settings.json` and
  commits), so the binary `apply` shape does NOT fit — even with
  `--apply-onboarding` set, the recipe **MUST NOT auto-apply**. It
  plumbs a confirmation prompt through and obeys the same
  conversational-pause invariant as Step 4 (loom-xcw): after printing
  the prompt, STOP and wait for a user-typed reply.

  Gate first (`refuse_if_guest AUTOFIX:dedup-hook-commit`), then print
  the confirmation prompt verbatim (substitute the offending hook name
  from the item-12 WARN line):

  ```
  This commits a change to .claude/settings.json that assumes loom
  adoption for all devs on this repo. Non-loom devs lose <hook-name>
  registration. Proceed? (y/N)
  ```

  On a typed `y` (and only then): strip the duplicate stanza from the
  tracked file and commit with the scoped subject —

  ```bash
  cd <root>
  # strip the duplicate (event, matcher, command) stanza (content-aware)
  git add .claude/settings.json
  git commit -m "audit: dedup <hook-name> SessionStart hook (loom-managed; plugin + user-global handle registration)"
  ```

  On `N` (or any non-`y` reply): leave the row in the per-item queue
  and emit `AUTOFIX:dedup-hook-commit: declined — left for manual
  handling`. The `LOOM_AUDIT_PROMPT_ANSWER` env var injects the
  y/N answer non-interactively under tests (same mocking surface as
  items 13/14).

  The reason a resolution path is needed at all: Claude Code hook
  layering is **additive across all four layers** (plugin +
  user-global `~/.claude/settings.json` + project-tracked
  `.claude/settings.json` + project-local `.claude/settings.local.json`).
  Empty arrays in `settings.local.json` do NOT cancel an inherited
  registration — layering is union, not override. Verified inert in
  e2e-api-tests on 2026-05-27: bd prime still fired 3 times in a
  fresh SessionStart after the empty-array override was applied. The
  only resolutions that actually work are the two recipes above; see
  [`docs/reference/claude-code-hook-layering.md`](../../docs/reference/claude-code-hook-layering.md)
  for the full finding. (loom-jnn.)

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
  - appended `.claude/workflow-state.json`

[AUTOFIX:loom-env-block] @ <root>/.claude/settings.json
  - backed up to settings.json.pre-loom.bak
  - merged env block: CLAUDE_CODE_ENABLE_TASKS=false (added),
    CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 (added)

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

### Step 6 — optional history mining (`--mine-history`)

This step runs **only when `--mine-history` was passed**. Without the
flag, skip it entirely — the audit has already *flagged* the
decision-history gap informationally (the `project-onboarder`
decision-history line, which shells out to `scripts/loom-mine-history
--dry-run` for the unmined-unit count). Mining is a separate, billable
action the user opts into; the audit never auto-mines.

When the flag IS set, after the report + interactive fixes are done,
delegate to the `/loom-mine-history` skill against the resolved
`--root` / `--wing`:

1. Announce: "Mining <root> decision history into wing `<wing>` …".
2. Invoke the `loom-mine-history` skill (it owns the mandatory
   two-pass cost gate: a zero-spend `--dry-run` preview → explicit
   user go-ahead → the paid LLM salience pass → MCP filing). Pass the
   resolved `--root` and `--wing` through; do NOT re-implement the
   engine or the cost gate here.
3. Fold the mine's adoption summary (drawers filed / skipped-dup /
   triples added) into the audit's closing summary.

Do not bypass `loom-mine-history`'s cost gate — the audit delegating
to it does not change the "preview-before-spend, explicit go-ahead"
contract.

### Step 7 — project-constitution capture (`--check=constitution`)

This step runs **only when `--check=constitution` was passed** (it is
NOT part of `--check=all`). It is the capture half of the loom-6f8
Constitution epic (loom-1iz). The schema, the fillable template, the
dogfooded loom sample, and the field reference are loom-vin artifacts:

- Schema: `references/project-constitution.schema.json`
- Template: `templates/project-constitution.md`
- Dogfood: loom's own `.claude/project-constitution.md`
- Reference: `docs/reference/project-constitution.md`

The output is one file per project at
`<root>/.claude/project-constitution.md` — YAML front-matter (the
machine-read tooling fingerprint) plus a Markdown prose body (human
rationale). This step writes the front-matter from detected signals
and stubs the prose body for a human to author; it never authors the
prose itself (loom-d50).

#### Step 7a — detect the tooling fingerprint

Dispatch the `project-onboarder` subagent (or, if it was already
dispatched in Step 2, reuse its fingerprint section) to scan
`<root>` and return a tooling fingerprint. The onboarder is
read-only — it reports the fingerprint; this skill owns every write,
the per-field confirmation, and the MemPalace mirror.

The detection heuristics (all filesystem-marker based, relative to
`<root>`), in the order they resolve each field:

- **`shell`** — `<root>/devbox.json` present → `shell.enter: "devbox
  shell"`, `shell.run_prefix: "devbox run"`. Else `<root>/flake.nix`
  present → `shell.enter: "nix-shell"`, `shell.run_prefix: "nix-shell
  --run"`. Else both empty (no shell wrapper). `devbox.json` wins over
  `flake.nix` when both are present (devbox is the outer envelope).
- **`package_manager`** — first decisive lockfile / manifest wins, in
  this precedence: `<root>/pnpm-lock.yaml` → `pnpm`; `<root>/yarn.lock`
  → `yarn`; `<root>/package-lock.json` → `npm`; `<root>/uv.lock` →
  `uv`; `<root>/poetry.lock` → `poetry`; `<root>/Cargo.toml` →
  `cargo`; `<root>/go.mod` → `go`. None present → `none`.
- **`language.runtime`** — `<root>/Cargo.toml` → `rust`;
  `<root>/go.mod` → `go`; any of `pyproject.toml` / `setup.py` /
  `setup.cfg` / `requirements*.txt` → `python`; `<root>/package.json`
  (with a non-`none` package_manager) → `node`; a `<root>/scripts/`
  directory containing `*.sh` and no other language marker → `bash`;
  otherwise `unknown` (polyglot or undetected — never guess).
  `language.version` is left EMPTY (version pins are a human choice,
  not a filesystem signal).
- **`canonical_commands`** — `<root>/Makefile` with a `build:` /
  `test:` / `lint:` target → `make build` / `make test` / `make lint`
  for those verbs. For any verb the Makefile does not cover (and for
  all five verbs when there is no Makefile), an executable
  `<root>/scripts/<verb>` fills it: `scripts/build` → build,
  `scripts/test` → test, `scripts/lint` → lint, `scripts/gen` → gen,
  `scripts/server` → dev. The Makefile target wins over the script for
  the same verb. Verbs with neither signal stay EMPTY.
- **`forbidden`** / **`bypass_patterns`** — NOT auto-detected. These
  encode a project-specific lock-in posture (e.g. forbid `pip install`
  on a uv project) that is a human judgment, not a filesystem signal.
  They are rendered as empty lists in the draft for the human to fill.

**Empty fields stay empty.** The detector never invents a value it
could not read from a marker — an undetected verb, an unpinned
version, an absent shell wrapper all render as `""` (or `[]` for the
lists). This is the same discipline as the loom-vin template: leave
keys present with empty values rather than guessing.

#### Step 7b — render the draft front-matter

Render the detected fingerprint into the YAML front-matter shape from
`templates/project-constitution.md` (and validated by
`references/project-constitution.schema.json`). Every required key is
present; detected fields carry their value; undetected fields carry
`""` / `[]`. Do NOT write the file yet — Step 7c confirms each field
first.

#### Step 7c — per-field interactive confirmation (one field at a time)

**Invariant (loom-xcw): confirm ONE field at a time — never
lump-sum.** Walk the front-matter fields in schema order
(`shell.enter`, `shell.run_prefix`, `package_manager`,
`language.runtime`, `language.version`, each `canonical_commands.*`
verb, `forbidden`, `bypass_patterns`). For EACH field, show the
detected value and ask the user to confirm, edit, or clear it:

```
Field `<name>`: detected `<value>` (from `<marker>`).
Keep / edit / clear? (keep / <new value> / clear)
```

After printing each field's prompt, STOP and wait for a user-typed
reply before moving to the next field. Do NOT batch all fields into
one prompt and accept a single lump-sum approval — that is exactly
the loom-xcw / loom-wxo failure mode (multiple items applied without
an intervening user turn). This is a USER-approval gate (a
conversational pause), distinct from the TOOL-permission gate;
`--dangerously-skip-permissions` does NOT auto-resolve it.

Test mocking surface: the `LOOM_AUDIT_PROMPT_ANSWER` env var (same
surface as items 13/14) injects per-field answers non-interactively
for fixtures.

#### Step 7d — write the file UNSTAGED + stub the prose body

After every field is confirmed, write
`<root>/.claude/project-constitution.md`:

- The confirmed YAML front-matter.
- The Markdown prose body emitted as a **`[HUMAN AUTHOR]` TODO
  stub** — section headers (`## Tooling choices`, `## Forbidden
  patterns`, `## Bypass patterns`, `## Lineage`) each carrying a
  `> [HUMAN AUTHOR] TODO: …` placeholder line. **The skill NEVER
  authors the prose body itself** — this is the loom-d50 lesson: in
  the loom-wxo liza_base trial the audit silently drafted+applied
  `.claude/rules/tests.md` content (project conventions) without human
  authorship; the constitution prose is the same class of
  convention-encoding text and MUST stay a human-authored MISS, not an
  agent draft. The agent fills the machine-read front-matter; the
  human fills the prose.

The file is written **UNSTAGED** — the skill does not `git add` it.
The user reviews with `git diff`, authors the prose body, and commits
when ready. (Same posture as the Step 3.5 AUTOFIX recipes: write to
the working tree, leave git dirty, never commit on the user's behalf.)

#### Step 7e — mirror to MemPalace + emit KG triples

Mirror the captured constitution to a single drawer in the
`<wing>/decisions` room (the resolved `--wing` from Step 1 — same
hardcoded destination as the Step 5 audit-findings drawer):

- `mempalace_add_drawer(wing=<wing>, room='decisions', title='Project
  constitution: <project-short-name> (<YYYY-MM-DD>)', content=<the
  confirmed front-matter + the field-by-field detection provenance>)`.

Then emit KG triples for the tooling so the fingerprint is queryable
(via `mempalace_kg_add`):

- `<project> uses_shell <shell.enter>` (omit when no shell wrapper)
- `<project> uses_package_manager <package_manager>`
- `<project> uses_language <language.runtime>`

These triples let session-startup, subagent-dispatch briefs, and the
debugging recipes (loom-ld4 surfacing) query a project's tooling
fingerprint without re-reading the file.

#### Step 7f — re-run drift detection (idempotent)

When `<root>/.claude/project-constitution.md` already exists, Step 7
becomes a drift check rather than a fresh capture:

1. Parse the captured front-matter.
2. Re-run the Step 7a detection against the current tree.
3. For each field where the detected value differs from the captured
   value, surface the drift per field:

   ```
   [CONSTITUTION DRIFT] <field>
     captured:   <value in the file>
     detected:   <value from the current tree>
     suggested:  confirm / skip (per-field — same one-at-a-time gate
                 as Step 7c)
   ```

4. The drift loop reuses the Step 7c one-field-at-a-time confirmation
   — the user confirms or skips each drifted field. Only the
   front-matter is rewritten, and only for confirmed fields.

**The prose body is NEVER overwritten on re-run.** Detection is
read-only against the prose; the drift check rewrites front-matter
fields the user confirms and leaves the entire Markdown body
(including any human-authored rationale) untouched. A re-run that
finds no front-matter drift is a no-op that does not modify the file
at all.

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
