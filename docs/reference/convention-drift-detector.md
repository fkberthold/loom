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
| `scripts/loom-sync-stamp` | Writes a project's `.claude/.loom-sync` (hash + date) at sync time | loom-ig3p.2 |
| `hooks/loom-drift-nudge.sh` | SessionStart hook — non-blocking, once-per-session drift nudge | loom-ig3p.3 |
| `/audit-project --check=drift` / `--apply-drift` | On-demand deep diff + per-item human-reviewed apply | loom-ig3p.4 |
| `lib/tests/convention-drift-gates.test.sh` | Correctness-class gates wired into `script/test` | loom-ig3p.5 |

The first three form the **detect** half — cheap, automatic,
opt-in-by-stamp. The fourth is the **remediate** half — deliberately
reuses `/audit-project` rather than a new command. The fifth is a
different thing entirely: not drift detection over a project's
*copies*, but drift detection over loom's *own* internal consistency
(does a skill invoke a script by the right path; does a hook
registration point at a file that exists).

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

Writes `<target-dir>/.claude/.loom-sync`, a tiny key=value file:

```
hash=<manifest hash>
date=<YYYY-MM-DD>
```

Two forms, same unit:

```bash
# CLI (shells out)
scripts/loom-sync-stamp <target-dir> <manifest-hash> [date]

# sourced (side-effect-free until called)
source scripts/loom-sync-stamp
loom_write_sync_stamp <target-dir> <manifest-hash> [date]
```

Every call **overwrites** the file — it is a point-in-time record,
never an append log. `[date]` defaults to today (UTC) and is only
overridden for deterministic tests or a caller with a specific sync
date to record.

**Two callers, two targets, same unit:**

- `install.sh` stamps **loom's own** `<loom-root>/.claude/.loom-sync`
  — loom dogfoods itself as "the target project" the same way it
  dogfoods its own `.claude/settings.json` and
  `.claude/project-constitution.md`.
- `/audit-project` Step 1c stamps a **downstream/managed** project's
  `<root>/.claude/.loom-sync`, unconditionally, on *every* invocation
  regardless of which `--check=` mode was requested — running
  `/audit-project` at all against a project *is* the sync event.

In both cases the caller computes the hash (always against the loom
checkout, never against the target) and passes it in; this unit only
writes.

## SessionStart nudge — `hooks/loom-drift-nudge.sh`

Fires on every `SessionStart` (fresh start, resume, and `/clear`). For
each managed project it opens in:

1. **Opt-in guard.** No `<project>/.claude/.loom-sync` stamp → silent
   no-op. A project that has never synced against loom (or isn't
   loom-managed at all) is never nudged.
2. Reads the stamped `hash=` / `date=`.
3. Recomputes loom's **current** manifest hash — resolving its own
   real path via `readlink -f` first, since `BASH_SOURCE` reflects the
   `~/.claude/hooks/` symlink install.sh creates, not the real loom
   checkout, and the manifest script's own root-resolution needs the
   real one.
4. Matching hash → in sync → silent no-op.
5. Mismatched hash → emits **one** stderr line, gated by a
   once-per-session sentinel under `$XDG_RUNTIME_DIR` (falling back to
   `$TMPDIR`), keyed on the stamp path:

   ```text
   [loom-drift-nudge] INFO: this project's loom-convention stamp
   (hash=abc123456789..., synced 2026-06-01) is behind loom's current
   conventions (hash=def987654321...) — run `/audit-project
   --apply-drift` to resync.
   ```

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
choice: **`--apply-drift` never overwrites your project's live files.**
It stages loom's current template versions into a project-local
mirror at `<root>/.claude/loom-templates/<relpath>` — a
human-reconciliation aid you diff against your own copy — not an
automatic in-place resync. A live, cross-project template
reconciliation engine was explicitly ruled out of scope (YAGNI, per
the design drawer's "Question / Scope" section): a project's
scaffolded files carry per-file variable substitution and human edits
this detector does not attempt to understand.

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
(`scripts/loom-audit-resolve`) — hence `loom-drift-resolve`.

## Correctness gates — `lib/tests/convention-drift-gates.test.sh`

Distinct from everything above: these gates don't detect a *project's*
drift from loom — they catch loom's *own* internal drift, the kind
where the detector machinery quietly stops working because a
reference inside loom itself went stale. Per
[Gate, don't advise](../explanation/gate-dont-advise.md), a
correctness-critical class gets wired into `script/test`, never left
as an advisory a human has to remember to run.

Two gates today, in one file, each following the same
detect-function / RED-case / GREEN-case / LIVE-case shape:

- **Gate 1 — bare downstream `scripts/loom-X` invocation.** A
  loom skill or command referencing a helper script by its
  repo-relative path (`scripts/loom-fanout-detect`) only resolves when
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

Run directly: `bash lib/tests/convention-drift-gates.test.sh`. Wired
into the default `script/test` run.

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
- `lib/tests/convention-drift-gates.test.sh` — Gate 1 + Gate 2
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
- [Gate, don't advise](../explanation/gate-dont-advise.md) — the
  principle Gate 1/2 and the nudge's non-blocking posture both apply,
  in opposite directions.
