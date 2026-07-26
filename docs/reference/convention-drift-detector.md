# Downstream convention-drift detector

> The machinery that notices when a loom-managed project's scaffolded
> conventions — its Diataxis docs skeleton, design-doc drawers,
> exploration drawers, `.claude/project-constitution.md` — have fallen
> behind loom's *currently shipped* `templates/` tree: a deterministic
> manifest hash, a per-project sync stamp, a non-blocking SessionStart
> nudge, an on-demand deep diff, a per-item apply engine, and two
> correctness gates that keep the machinery itself from rotting.

## Why this exists

Loom does not push conventions to the projects it manages. A project
syncs once (`install.sh`, or its first `/audit-project` run) and then
carries its own copies — scaffolded docs, a constitution file, drawer
templates — forward in its own history. Nothing previously detected
when loom's `templates/` tree moved on without a corresponding resync:
a project could drift arbitrarily far from loom's current conventions
with no signal anywhere.

This generalizes the staleness pattern loom-1lj already used for a
single file (`.claude/project-constitution.md` vs. the newest tooling
manifest mtime) into a convention-set-wide detector, per design cycle
D1–D5 (design drawer `drawer_loom_decisions_4d3918198c51bb65ceaebf90`,
epic loom-ig3p).

## The five pieces

| Piece | What it does | Bead |
|---|---|---|
| `scripts/loom-convention-manifest` | Enumerates loom's convention file-set and hashes it deterministically | loom-ig3p.1 |
| `scripts/loom-sync-stamp` | Writes a project's `.claude/.loom-sync` — `last_checked` on any audit, `last_synced` only when remediation applied | loom-ig3p.2, loom-uh4i |
| `hooks/loom-drift-nudge.sh` | SessionStart hook — non-blocking, once-per-session drift nudge | loom-ig3p.3 |
| `/audit-project --check=drift` / `--apply-drift` | On-demand deep diff + per-item human-reviewed apply | loom-ig3p.4 |
| `lib/tests/convention-drift-gates.test.sh` | Correctness-class gates wired into `script/test` | loom-ig3p.5 |
| `scripts/loom-owned-templates` | Registry of templates loom owns outright + byte-wise drift check over their live copies | loom-f59h |

The first three form the **detect** half — cheap, automatic,
opt-in-by-stamp. The fourth is the **remediate** half — deliberately
reuses `/audit-project` rather than a new command. The fifth is a
different thing entirely: not drift detection over a project's
*copies*, but drift detection over loom's *own* internal consistency
(does a skill invoke a script by the right path; does a hook
registration point at a file that exists). The sixth covers the one
channel the stamp cannot see at all — see
[Owned vs scaffold templates](#owned-vs-scaffold-templates).

## Convention manifest — `scripts/loom-convention-manifest`

Computes a single sha256 hash over loom's convention-bearing file set.

```bash
scripts/loom-convention-manifest              # print the hash
scripts/loom-convention-manifest --list       # print the sorted file list
scripts/loom-convention-manifest --root <dir> # resolve against <dir> instead
```

**File-set decision.** The manifest covers the entire `templates/`
tree — every scaffold source that seeds a downstream project's `docs/`
tree, design-doc drawers, exploration drawers, or its
`.claude/project-constitution.md`. Two things are deliberately
*excluded*, not overlooked:

- **`skills/` and `hooks/`** — these are globally symlinked into
  `~/.claude/`, so a downstream project always sees loom's *current*
  copy live. They cannot drift the way a copied/scaffolded file can,
  so hashing them would manufacture false drift.
- **Loom's own `.claude/project-constitution.md`** — already has its
  own independent staleness nudge (loom-1lj, tooling-manifest mtime
  skew). Folding it into this manifest would double-count the same
  signal under two mechanisms.

**Determinism.** The file set is a fixed array of convention roots
(`CONVENTION_PATHS`, currently just `templates`), resolved with `find`
and sorted lexically — filesystem iteration order and mtime never
factor in. Each file is hashed independently; the sorted
`<relpath>␠␠<sha256>` lines are concatenated and hashed once more to
produce the composite manifest hash. A content change to any listed
file changes its own line, which changes the composite; a change
outside `templates/` is never read, so it cannot move the hash.

`--root <dir>` exists so callers — and tests — can point the scan at
an isolated fixture tree instead of the real repo.

## Sync stamp — `scripts/loom-sync-stamp`

Writes `<target-dir>/.claude/.loom-sync`, a tiny key=value file
carrying **two facts** (loom-uh4i):

```
last_synced=<manifest hash>      # omitted until a real sync happens
last_synced_date=<YYYY-MM-DD>    # omitted until a real sync happens
last_checked=<manifest hash>
last_checked_date=<YYYY-MM-DD>
```

| key | written by | meaning |
| --- | --- | --- |
| `last_checked` / `last_checked_date` | **any** invocation | somebody looked at this project. Informational only. |
| `last_synced` / `last_synced_date` | only an invocation that **applied** remediation (`--synced`) | loom's conventions actually landed here. **The nudge compares this one.** |

Two forms, same unit:

```bash
# CLI (shells out)
scripts/loom-sync-stamp [--synced|--checked] <target-dir> <manifest-hash> [date]

# sourced (side-effect-free until called)
source scripts/loom-sync-stamp
loom_write_sync_stamp [--synced|--checked] <target-dir> <manifest-hash> [date]
```

`--checked` is the **default**. That polarity is deliberate: a
forgotten `--synced` leaves the drift nudge firing — visible and
self-correcting — whereas a forgotten `--checked` would silently
silence the detector, which is precisely the bug this split fixed.

Each key appears **at most once**; a write replaces a key's value
rather than appending. A check-only write is a read-modify-write that
**preserves** any existing `last_synced` pair — recording "we looked"
must never destroy the record of "we synced". `[date]` defaults to
today (UTC) and is only overridden for deterministic tests or a caller
with a specific date to record.

### Why two facts (loom-uh4i)

The stamp originally carried a single `hash=`, rewritten
unconditionally on every `/audit-project` invocation. Because the
[SessionStart nudge](#sessionstart-nudge--hooksloom-drift-nudgesh)
compares that field against loom's current hash, a **read-only**
`--check=` run that applied nothing still marked the project synced
and silenced the nudge: **the detector could be quieted by looking at
it.** Measured 2026-07-25 — a managed project was stamped with a hash
matching loom exactly, nudge silent, zero remediation applied, its
`CLAUDE.md` and `.claude/rules/dispatched-agents.md` byte-unchanged
for weeks and still missing every current convention.

The original unconditional-stamp rationale is real and was **not**
dropped: a project audited before the drift machinery existed still
needs a baseline, and "no prior stamp" must not read as "the entire
manifest drifted" forever. So the fix separates the two facts rather
than discarding either.

### Legacy migration

A pre-loom-uh4i stamp carries only `hash=` / `date=`. Both the writer
and the hook read that pair as **`last_synced`** — not as
`last_checked` — because under the old semantics the write happened at
what was *called* a sync. Grandfathering it any other way would take
every already-stamped project from silent to nudging overnight, and
would break the deliberately grandfathered
stamped-but-no-`workflow.json` shape from loom-oktm. The migration
**consumes** the legacy keys (they are not re-emitted): carrying two
representations of one fact is the conflation this change removes.
No downstream project needs to do anything — its next
`/audit-project` run rewrites the stamp in the new shape.

**Callers, targets, and which flag each passes:**

- `install.sh` stamps **loom's own** `<loom-root>/.claude/.loom-sync`
  with `--synced` — loom dogfoods itself as "the target project" the
  same way it dogfoods its own `.claude/settings.json` and
  `.claude/project-constitution.md`, and installing loom's conventions
  *is* the remediation.
- `/audit-project` **Step 1c** records the **check** on a
  downstream/managed project's `<root>/.claude/.loom-sync`,
  unconditionally, on *every* invocation regardless of which
  `--check=` mode was requested — running `/audit-project` at all *is*
  a check event.
- `/audit-project` **Step 3.5 `--apply-drift`** is the only place a
  **sync** is ever recorded, and only when
  `scripts/loom-drift-resolve` reports `N >= 1` applied. Zero applied
  — including an `--apply-drift` where the user skipped every item —
  is a check, not a sync: *a run that leaves the project
  byte-identical leaves the nudge state byte-identical.*

In every case the caller computes the hash (always against the loom
checkout, never against the target) and passes it in; this unit only
writes.

## SessionStart nudge — `hooks/loom-drift-nudge.sh`

Fires on every `SessionStart` (fresh start, resume, and `/clear`). For
each managed project it opens in:

1. **Opt-in guard.** The signal is *loom-managedness*, and either of two
   things proves it: a `<project>/.claude/workflow.json`, or an existing
   `<project>/.claude/.loom-sync` stamp (only `/audit-project` ever
   writes one, so its presence is itself proof the project opted in).
   With **neither** → silent no-op. A project that isn't loom-managed at
   all is never nudged.
2. **Never-synced branch.** Loom-managed (`workflow.json` present) but
   carrying **no stamp** → emit the *never-synced* nudge and stop. There
   is no hash to compare, and skipping the manifest computation keeps
   this path robust where the manifest script can't be resolved. This is
   the case an earlier revision silently swallowed: it read "no stamp" as
   "nothing to compare" and exited quietly, so a project that was
   **current** and one that had **never received loom's conventions at
   all** were indistinguishable — and never-synced is the state that most
   needs the nudge. Fixed in `loom-oktm`.
3. Otherwise the stamp exists (with or without `workflow.json`) — reads
   its **`last_synced` / `last_synced_date`** record, falling back to a
   legacy `hash=` / `date=` pair (see
   [Legacy migration](#legacy-migration)). `last_checked` is **never**
   compared; a read-only audit writes only that field, so it cannot
   silence the nudge (loom-uh4i).
3b. **Checked-but-never-synced branch.** The stamp exists but carries
   no `last_synced` record, only a `last_checked` one → emit the
   *never-synced* nudge, naming the last-checked date, and stop. The
   loom-oktm never-synced branch keys on the **absence of
   `last_synced`**, not on the absence of the stamp file. A stamp with
   neither record is malformed or hand-edited → fail open, silent.
4. Recomputes loom's **current** manifest hash — resolving its own
   real path via `readlink -f` first, since `BASH_SOURCE` reflects the
   `~/.claude/hooks/` symlink install.sh creates, not the real loom
   checkout, and the manifest script's own root-resolution needs the
   real one.
5. Mismatched hash → emits the **stale-stamp** nudge (below) and stops.
6. Matching hash → the *stamp* says in sync. Before believing it, runs
   the **stamp-independent owned-file check** (loom-5od2, see
   [Two signals](#two-signals-hash-and-bytes)) — one
   `scripts/loom-owned-templates --check` subprocess against the
   project. Any `[DRIFT]` entry → the **owned-file** nudge. Otherwise
   silent no-op.

Every nudge is **one** stderr line, gated by a once-per-session
sentinel under `$XDG_RUNTIME_DIR` (falling back to `$TMPDIR`), keyed on
the stamp path. Same fix command throughout, different emphasis — and a
reader can tell which condition tripped from the line alone, because
only the stale one prints hashes and only the owned-file one prints a
path:

```text
[loom-drift-nudge] INFO: this project's loom-convention stamp
(hash=abc123456789..., synced 2026-06-01) is behind loom's current
conventions (hash=def987654321...) — run `/audit-project
--apply-drift` to resync.
```

```text
[loom-drift-nudge] INFO: this project's loom-OWNED convention file(s)
do not match loom's current copies — .claude/rules/loom-conventions.md
(absent — never seeded from templates/rules/loom-conventions.md). The
sync stamp says current, but this is a byte comparison of the files
themselves, so the stamp cannot vouch for them — run `/audit-project
--apply-drift` to apply loom's copy.
```

### Two signals: hash and bytes

The hook nudges if **either** signal fires.

| | Manifest hash | Owned-file bytes |
|---|---|---|
| Compares | the stamped `last_synced` vs loom's current manifest hash | loom's owned templates vs the project's live copies |
| Reads the stamp? | yes — it *is* the stamp | **no** |
| Answers | "was this project ever told about loom's current conventions?" | "does this project actually *have* them?" |
| Nudge names | both hashes | the drifted path(s) + reason |

The stamp is a **claim about the past**; the bytes are a **fact about
the present**, and the fact wins. That is loom-f59h's framing, and
before loom-5od2 it only held inside `/audit-project` step 3.3a — on
manual invocation. The hole: per [the checked/synced
split](#legacy-migration), an `--apply-drift` run with ≥1 item applied
re-stamps `last_synced` at loom's **full** current hash. A user who
applies some items and **skips** the `loom-conventions.md` one ends up
stamped-current with the owned file absent, and the SessionStart nudge
stayed silent until the next convention change happened to move the
hash — a smaller version of exactly the false-green loom-uh4i fixed,
one layer along.

Three properties of the check, all pinned by
`lib/tests/loom-drift-nudge.test.sh` (cases V–AC):

- **Cheap.** Exactly ONE subprocess regardless of the owned set's size
  — the registry loops internally. At today's owned count of one it is
  a single `cmp` on top of the manifest hash the hook already computes.
- **Degrades to hash-only, silently.** A missing or non-executable
  `scripts/loom-owned-templates` (an older checkout, a partial install)
  → the hook behaves exactly as it did before, and says nothing about
  the degradation. There is nothing the user could act on.
- **`[FAIL]` is not `[DRIFT]`.** The registry reports `[FAIL]` — and
  exits non-zero — when **loom's own** copy of an owned template is
  missing. That is loom's problem, not the project's, so the hook keys
  on `[DRIFT]` lines specifically and never on the exit code. Nudging a
  project to apply a file loom cannot supply would be a false positive.

A hash mismatch takes precedence when both fire: the two carry the same
fix command, and one nudge per session is the loudness budget.

**Never blocks.** The hook always exits 0 — see
[Gate, don't advise](../explanation/gate-dont-advise.md) for why this
is the *correct* posture here: whether to resync now is an ATTENDED
decision for the human, not a correctness invariant that must always
hold. Session-startup surfaces the nudge at
[step 1g](skills/session-startup.md) if it fired; it does not
re-derive or re-check the drift itself.

Bypass: `LOOM_DRIFT_NUDGE_SKIP=1` (literal `"1"` only, per the
loom-b1l env-gate convention).

## Deep diff + remediation — `/audit-project --check=drift` / `--apply-drift`

The nudge above only affords an O(1) hash-equality check — useful for
"has anything changed" but not "*what*." `/audit-project --check=drift`
is the on-demand deep diff that answers that: it compares the prior
stamp (captured in Step 1c-pre, before Step 1c's unconditional
re-stamp overwrites it) against loom's current hash and, on a
mismatch, walks `git log --since=<prior-date> --name-only -- templates/`
in the loom checkout to enumerate exactly which `templates/<relpath>`
files changed.

`/audit-project --apply-drift` (implies `--check=drift`) drives each
drifted file through `scripts/loom-drift-resolve`, a per-item
human-reviewed apply engine, mirroring the shape `--apply-onboarding`
already uses for its `[AUTOFIX:...]` recipes.

This reference page covers the *mechanism*; the full step-by-step flow
for a downstream user is
[How to: resync a managed project's conventions](../how-to/resync-managed-project.md).
The one fact worth stating here because it shapes every other design
choice: **`--apply-drift` never overwrites a file your project owns.**
For a SCAFFOLD template it stages loom's current version into a
project-local mirror at `<root>/.claude/loom-templates/<relpath>` — a
human-reconciliation aid you diff against your own copy — not an
automatic in-place resync. A live, cross-project template
reconciliation engine was explicitly ruled out of scope (YAGNI, per
the design drawer's "Question / Scope" section): a project's
scaffolded files carry per-file variable substitution and human edits
this detector does not attempt to understand.

The exception is a template **loom owns outright**, which by
construction has neither property. Those apply at their live path.

## Owned vs scaffold templates

Loom-managed projects receive two structurally different kinds of file
from `templates/`, and the difference decides everything about how
each is checked and applied.

| | **Scaffold** template | **Owned** template |
|---|---|---|
| Examples | `templates/diataxis/**`, `templates/design-doc/**`, `templates/project-constitution.md` | `templates/rules/loom-conventions.md` |
| Carries `{{ substitutions }}` | yes | no |
| Expected to be hand-edited | yes — that's the point | **no** — stated in the file's own header |
| Can loom byte-diff the project's copy? | no | yes |
| `--apply-drift` target | mirror: `<root>/.claude/loom-templates/<relpath>` | **live**: the file's real path |
| Drift signal | loom's template changed (git log since the stamp) | the project's actual file is absent or differs |

Membership in the `OWNED_TEMPLATES` array inside
`scripts/loom-owned-templates` **is** the distinction — listed means
live-apply, unlisted means mirror-apply. Existing scaffold templates
were deliberately not converted: live-applying one would clobber
customized files loom does not understand.

### Why the owned kind had to exist (loom-f59h)

loom-pogc named two channels by which loom pushes conventions
downstream:

1. **Globally symlinked** skills, hooks, and commands under
   `~/.claude/` — a managed project always sees loom's *current* copy,
   so these cannot drift.
2. **Per-project priming** — the project's own `CLAUDE.md` and
   `.claude/rules/`. loom-pogc's words: *"this is the STEERING WHEEL,
   and nothing forces it to re-sync."*

The machinery above covers a **third** thing: `templates/`-derived
scaffolds. So channel (2) went uncovered, and the gap was measured
rather than theorized — a managed project on 2026-07-25 carried a
`.claude/.loom-sync` stamp matching loom's manifest hash *exactly*
(nudge silent, audit clean) while its priming was 15 days stale and
mentioned none of loom's current conventions.

A hash stamp records what a project was **told**. Only reading the
project's actual file records what it **has**. That is the whole
argument for the owned kind, and for `--check=drift` running the
byte comparison (Step 3.3a) even on the branch where the manifest
hash matches and the manifest half returns early.

Two options were rejected on the way:

- **Marker-delimited region inside the project's `CLAUDE.md`** — the
  detector would have to parse project prose, and markers drift.
- **Keyword-presence nudge** ("does the priming *mention* the current
  conventions?") — advisory-only and undiffable, which fails
  [gate-don't-advise](../explanation/gate-dont-advise.md) for what is
  a correctness invariant.

### `scripts/loom-owned-templates`

```bash
loom-owned-templates --list [--loom <dir>]
loom-owned-templates --check --root <dir> [--loom <dir>]
loom-owned-templates --items --root <dir> [--loom <dir>]
```

- `--list` prints the registry as `<template-relpath>\t<live-target-relpath>`.
- `--check` prints one line per entry and **exits 1 if any drifted**:

  ```
  [DRIFT] <root>/.claude/rules/loom-conventions.md (absent — never seeded from templates/rules/loom-conventions.md)
  [DRIFT] <root>/.claude/rules/loom-conventions.md (content differs from templates/rules/loom-conventions.md — trails loom's current convention set)
  [OK]    <root>/.claude/rules/loom-conventions.md (matches loom's current copy of templates/rules/loom-conventions.md)
  ```

  A `[FAIL]` line means loom's own source is missing — a loom bug, not
  a project gap.
- `--items` prints a `loom-drift-resolve` queue (absolute
  `<target>\t<source>`) for the drifted entries only, and exits 0
  either way: it is a queue *builder*, not a verdict. It never writes.

**Seeding falls out for free.** A project that has never carried the
file reports `[DRIFT] (absent)`, `--items` queues it, and
`loom-drift-resolve`'s `approve` path creates the parent directories
and copies — through the same per-item review gate as every other
item, with never-auto-apply intact. There is no separate seeding path.

The `CLAUDE.md` **pointer** that sends a reader to the file is the
other half of seeding, and it lives in the *onboarding* path
(`[AUTOFIX:loom-conventions-pointer]`, onboarder item 24) rather than
in `--apply-drift` — because it edits a **project-owned** file, which
the drift path must never do. The pointer text is fixed and
append-only, which is what keeps it clear of loom-d50's
never-author-project-rules constraint.

**Stamp independence.** The owned check does not read or write
`.claude/.loom-sync`. A current `last_synced` cannot silence it, and
re-stamping cannot mark it resolved — only applying the file does.
Same fail-toward-nudging polarity loom-uh4i chose: the stamp is a
claim about the past, the byte comparison is a fact about the present,
and where they disagree the fact wins.

Since loom-5od2 the [SessionStart nudge](#sessionstart-nudge--hooksloom-drift-nudgesh)
runs this check too, so the property holds unattended and not only when
someone remembers to invoke `/audit-project` — see
[Two signals](#two-signals-hash-and-bytes).

### `scripts/loom-drift-resolve` — the apply engine

```bash
loom-drift-resolve --items <items-file> [--decisions <decisions-file>]
```

- `--items` (required): lines of `<target-path>\t<source-path>`.
- `--decisions` (optional): lines of `<target-path>=<approve|skip|quit>`.
  Falls back to `$LOOM_AUDIT_RESOLVE_DECISIONS`, then to interactive
  stdin prompts (a diff preview followed by `Apply? (approve/skip/quit)`
  on stderr).

**Never-auto-apply, by construction.** An item with no decision
recorded for it — including every remaining item once one is `quit`
— defaults to `skip`. Given zero decisions at all, the entire queue
resolves to skip and nothing on disk changes. This is enforced by the
script itself, not by prose discipline in the calling skill, so it
holds even for a human running the script by hand. `approve` copies
the source over the target (creating parent directories as needed);
a missing source fails just that one item (`[FAIL]`) without aborting
the rest of the queue. Exit code is 2 on a usage error (nothing
processed), 1 if any item failed while applying, 0 otherwise.

The naming departs from the loom-ig3p.4 bead brief's original
`loom-audit-resolve` — that name was already taken by loom-6ah's
unrelated `--root`/`--wing` resolution prelude
(`loom/scripts/loom-audit-resolve`) — hence `loom-drift-resolve`.

## Correctness gates — `lib/tests/convention-drift-gates.test.sh`

Distinct from everything above: these gates don't detect a *project's*
drift from loom — they catch loom's *own* internal drift, the kind
where the detector machinery quietly stops working because a
reference inside loom itself went stale. Per
[Gate, don't advise](../explanation/gate-dont-advise.md), a
correctness-critical class gets wired into `script/test`, never left
as an advisory a human has to remember to run.

Three gates today, in one file, each following the same
detect-function / RED-case / GREEN-case / LIVE-case shape:

- **Gate 1 — bare downstream `scripts/loom-X` invocation.** A
  loom skill or command referencing a helper script by its
  repo-relative path (`scripts/<name>`) only resolves when
  cwd *is* the loom checkout. Referenced from any downstream project —
  where the skill actually runs, via the `~/.claude/skills/` symlink —
  the bare path misses silently. The gate scans `skills/*/SKILL.md`
  and `commands/*.md` for the GLOBAL_ONLY helper set and fails if any
  of them appear as a bare `scripts/<name>` reference instead of the
  installed global form (`~/.claude/scripts/<name>`,
  `$HOME/.claude/scripts/<name>`, or `.claude/scripts/<name>`). This is
  a lighter re-assertion of the loom-5x5o class already owned
  exhaustively by
  `lib/tests/downstream-script-invocation.test.sh`; it exists so a
  reader finds every correctness-critical class enumerated in this one
  file.
- **Gate 2 — `settings.snippet.json` hook/script path integrity.**
  Every downstream project installs `settings.snippet.json` into its
  own `settings.json`; each hook entry hardcodes a
  `$HOME/.claude/{hooks,scripts}/<name>` path. If a hook or script is
  renamed or deleted without updating the snippet, the reference
  404s silently at hook-fire time for every downstream install — the
  gate the hook was supposed to provide is just quietly absent, with
  no diagnostic anywhere a human is likely to look. The gate asserts
  every such reference in `settings.snippet.json` resolves to a real
  file in the repo.
- **Gate 3 — the same class as Gate 1, in `docs/`.** Gate 1 scans
  `skills/` and `commands/` only, but `docs/` is followed by downstream
  users too: a how-to that says "run `scripts/loom-rebase-worktree
  main`" is read by someone sitting in *their* project, where that path
  does not exist. Gate 3 calls the *same* matcher Gate 1 calls (shared
  `cdg_bare_scan` helper — identical GLOBAL_ONLY set, anchor, and
  filters, so the two cannot drift apart) across `docs/**/*.md`. See
  [the three accepted forms](#the-three-accepted-forms-in-docs) below.

Run directly: `bash lib/tests/convention-drift-gates.test.sh`. Wired
into the default `script/test` run.

### The three accepted forms in `docs/`

Gate 3 needs a distinction Gate 1 does not. Every file Gate 1 scans is
downstream-routed by construction, so a bare `scripts/loom-X` there is
unconditionally wrong. `docs/` is **mixed** — the same token appears in
two roles and only one is a defect:

| Role | Written as | Use when |
|---|---|---|
| **1. Downstream-routed invocation** | `~/.claude/scripts/loom-X` (or `$HOME/.claude/scripts/loom-X`, `.claude/scripts/loom-X`) | The text tells a reader or an agent to **run** the helper, and the reader is in their own project. |
| **2. loom-repo path citation** | `loom/scripts/loom-X` | The page describes where the file **lives in the loom repository** — a `## Files` inventory, an architecture seam, the source of an `install.sh` symlink, a naming-collision discussion. |
| **3. Generic anti-pattern quotation** | `scripts/<name>` | The text deliberately **exhibits** the broken bare form — as the Gate 1 bullet above does. |

Anything else is an offender.

Form 2 is what keeps this gate from mangling loom's own reference
docs: rewriting "Script: `scripts/loom-rebase-worktree`" to the
installed global path would make the page factually **wrong** about the
repo it documents. The `loom/` prefix names *which* repo's `scripts/`
is meant — ambiguous by default in a project-agnostic page — and it
costs zero extra gate machinery, because the shared matcher's
`[^/.~]` anchor already skips any `scripts/` preceded by `/`. Sibling
repo paths on the same line stay bare (`lib/tests/…`, `hooks/…`): the
qualifier is added exactly where a bare path would be
**mis-actionable**, i.e. only on the one token a reader might type
into a shell.

**Generator-produced pages are excluded.** `scripts/loom-docs-gen`
writes thin include-wrapper pages under
`docs/reference/{skills,slash-commands,subagents,hooks}/` carrying a
`GENERATED by scripts/loom-docs-gen` marker. Hand-editing a rendered
wrapper is always wrong — the next `script/gen` reverts it, and
`lib/tests/script-gen-clean-regen.test.sh` catches the drift. Their
content comes from the source primitive, which **Gate 1 already
scans**, so excluding them loses no coverage. Fix the source
primitive, never the rendered page.

## Scope note (v1, intentional)

The drift *set* `--check=drift` reports is loom's own template files
that changed since the project's last sync — not a live diff against
the project's actual scaffolded copies. Building a general
cross-project template-reconciliation engine was explicitly ruled out
(YAGNI) by the design cycle. See the how-to's
[mirror, not overwrite](../how-to/resync-managed-project.md#the-mirror-not-a-live-resync)
section for what this means in practice for a downstream user.

## Files

- `scripts/loom-convention-manifest` — manifest hash + `--list`
- `scripts/loom-sync-stamp` — `loom_write_sync_stamp` unit, CLI + sourced
- `hooks/loom-drift-nudge.sh` — SessionStart nudge
- `scripts/loom-drift-resolve` — per-item apply engine
- `skills/audit-project/SKILL.md` — Step 1c-pre, Step 1c, Step 3.3
  (`--check=drift`), Step 3.5 (`--apply-drift`)
- `lib/tests/convention-drift-gates.test.sh` — Gate 1 + Gate 2 + Gate 3
- Tests: `lib/tests/loom-convention-manifest.test.sh`,
  `lib/tests/loom-sync-stamp.test.sh`,
  `lib/tests/loom-drift-nudge.test.sh`,
  `lib/tests/loom-drift-resolve.test.sh`

## Lineage

- Epic loom-ig3p (downstream convention-drift detection), children
  loom-ig3p.1 through loom-ig3p.6 (this doc).
- Design drawer `drawer_loom_decisions_4d3918198c51bb65ceaebf90` —
  the D1 (foundation: manifest + stamp), D2 (remediation reuses
  `/audit-project`, not a new `/loom-sync`), D3 (SessionStart cadence),
  D4 (nudge loudness), D5 (gate-layer compose) decisions.
- Generalizes loom-1lj's single-file tooling-manifest staleness
  pattern (see
  [constitution-enforce hook](constitution-enforce-hook.md)) to the
  whole convention set.
- loom-pty2 — Gate 3: extends the Gate 1 class to `docs/`, factors the
  shared `cdg_bare_scan` matcher, and locks the three accepted forms
  above. 12 genuine offenders remediated; 7 loom-repo path citations
  identified as correct-as-written and converted to form 2 rather than
  rewritten.
- [Gate, don't advise](../explanation/gate-dont-advise.md) — the
  principle Gates 1/2/3 and the nudge's non-blocking posture both
  apply, in opposite directions.
