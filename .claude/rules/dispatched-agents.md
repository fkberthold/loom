---
description: Conventions for workers dispatched via Agent(isolation="worktree") to keep changes inside the worktree and verifications honest
---

# Dispatched-agent conventions

This file collects discipline that worker agents must follow when
running inside a `.claude/worktrees/agent-<id>/` worktree. The
Agent harness creates the worktree but does NOT fully sandbox the
worker — several failure modes leak changes into the main repo or
make verification dishonest. The conventions below mitigate each.

## Pre-flight smoke battery

**Run these as the FIRST bash calls of every dispatched-worker
session, before touching any file** (loom-g5k). Catches the most
common worktree-isolation failure modes at their cheapest detection
point. Abort and ask for guidance if any check fails.

**Run each step as its own separate Bash call — this battery is NOT
one pasteable block** (loom-ta1w). The worktree-isolation harness
statically verifies that every command stays inside the worktree and
refuses anything it cannot prove. Command substitution (`$(...)`),
brace grouping (`|| { echo ...; exit 1; }`), and multi-statement
`if … fi` blocks all come back as:

> This agent is isolated in the worktree `<path>`, but this command is
> too complex to verify that it stays inside the worktree; break it
> into plain, separate commands. Refusing to run it.

A worker handed one big block therefore improvises a split nobody
reviewed — and an improvised battery is one nobody verified. **Brief
authors: present these steps as separate calls**, never as a single
fenced block to paste.

Each step below is a plain command whose OUTPUT the worker reads and
compares. **The comparison is the agent's job, not the shell's** —
that inversion is what keeps every step runnable under the harness.

**Step 0 — constitution.** Read the project's tooling profile into
context (information, not action; loom-ld4). An absent file is fine.

```bash
cat .claude/project-constitution.md 2>/dev/null || echo "(no .claude/project-constitution.md — proceeding without a pinned profile)"
```

**Step 1 — repo identity.** The checkout you are in must BE the repo
your brief names. `isolation: "worktree"` worktrees the **dispatching
session's** repo, whatever the brief claims (loom-stdi). **Compare the
remote's repository name against the repo your brief names — if they
differ, ABORT and report the mismatch. Do not proceed, do not adapt,
do not write anything.**

```bash
git remote -v
```

Corroborate with two signals you already have: step 0's constitution
(a different project's runtime/package-manager profile is a mismatch)
and step 4's bd id prefix (`loom-…` vs `liza_base-…`). A repo with no
remote configured falls back to those two plus the step-2 toplevel
path.

**Step 2 — path.** The worktree root, canonicalized through symlinks
(`realpath .` is `pwd` with symlinks resolved), then git's idea of the
toplevel. **The two outputs must be identical**; if they differ, stop
and escalate.

```bash
realpath .
```

```bash
git rev-parse --show-toplevel
```

**Step 3 — import.** The project's Python (if any) must resolve inside
the worktree. Substitute `<project_name>`; skip entirely if the
project has no Python. **The printed path must start with the step-2
toplevel** — if it points at MAIN, the shadow is active.

```bash
python3 -c 'import <project_name>; print(<project_name>.__file__)'
```

**Step 4 — bd state.** The worktree's bd dolt must be non-empty. An
error or an empty listing means the next write-class `bd` call will
wipe `issues.jsonl` on merge — stop and escalate. Read the id prefix
too — it is step 1's corroborating identity signal.

```bash
bd list -n 1
```

**Step 5 — base freshness.** The branch base must match main's tip.
**Compare the two SHAs**; they must be identical.

```bash
git merge-base HEAD main
```

```bash
git rev-parse main
```

If they differ the base is STALE — rebase before doing any work, then
re-run step 5 to confirm. (Use `scripts/loom-rebase-worktree main`
instead when untracked WIP from a prior crash needs preserving; see
the Base-freshness section below.)

```bash
git rebase main
```

Each section below documents the failure mode that motivates one
smoke test, plus the mechanical-fix hook that backstops it. The
sections form a single pre-flight battery: step 0 (constitution
read) + repo identity + pwd + import + bd state + base-freshness.

## Step 0 — read the constitution (loom-ld4)

**Information, not action.** Step 0 of the battery `cat`s
`.claude/project-constitution.md` into the worker's context BEFORE
any verification step. It is the one battery step that is purely
informational — it pins NOTHING, gates NOTHING, and never aborts on
its result. Its job is to load the project's agreed tooling profile
(shell envelope, package manager, language runtime, the canonical
build/test/lint/gen/dev commands, and the `forbidden:` /
`bypass_patterns:` lists) so the worker runs the project's
*canonical* test/lint command instead of guessing one — the same
recurring guess (pip-on-uv, npm-on-pnpm, wrong test command) that the
constitution epic (loom-6f8) exists to kill.

An absent file is NOT a failure: a project may not have a
constitution yet, and a dispatched worker is the wrong place to nudge
`/audit-project` (that nudge lives at session-startup, step 1f). When
the file is missing, the `cat` falls through to a one-line note and
the battery proceeds. Step 0 runs first precisely because it is
information for every step that follows: the worker reads the profile,
THEN verifies repo-identity / pwd / import / bd-state / base-freshness.

One consequence worth stating: because step 0 loads the project's
identity along with its tooling, a constitution belonging to a
*different project than the brief names* is the cheapest possible
signal of the Mode 7 wrong-repo dispatch below. That is exactly how the
2026-07-25 incident was caught. Step 1 promotes that accident into a
deliberate check.

## Repo identity (loom-stdi)

**Risk (Mode 7 — isolation honored, WRONG REPO).** `isolation:
"worktree"` creates a worktree of the **dispatching session's** repo.
It does not read the brief, and there is no parameter that says which
repo to worktree. A brief that names a different project is simply
*wrong about where the worker is*, and nothing in the harness or in
loom's hooks contradicts it.

This is the third silent-failure shape for `isolation: "worktree"`,
alongside the two already documented above (isolation bypassed by an
absolute path — Mode 1; isolation honored but verification dishonest —
Modes 5/6). Here isolation is honored *perfectly*. The worktree is
real, the guard hook is live, every write lands inside the worktree —
and it is the wrong repo's worktree.

**What happened (2026-07-25, central's own error).** Central's session
cwd was `/home/frank/repos/loom`. It dispatched a `liza_base` bead with
`isolation: "worktree"` and a brief opening *"Dispatched worker in an
isolated git worktree of liza_base (NOT loom)"*. The harness made a
worktree of **loom**. The brief's claim was false and nothing caught
it.

**The inversion — this is the finding.** Had the worker followed the
brief's relative-path instruction, it would have overwritten **loom's
own `CLAUDE.md`** with a liza_base reconciliation. Relative-path
discipline is loom's headline mitigation for the absolute-path leak
(Mode 1, loom-tag) — and under Mode 7 it is precisely what causes the
damage, because a relative path resolves to the wrong repo's *real*
file of that name. The two guards are not unconditionally
complementary: loom-tag's mitigation assumes the worktree is of the
intended repo, and Mode 7 is the case where that assumption fails. No
existing guard covers it, because every existing guard reasons about
*where* a path resolves, never about *which project* the tree is.

**What saved it.** Battery step 0 returned loom's constitution
(`package_manager: none`, `runtime: bash`) instead of liza_base's
Python profile, and the bd-state step returned `loom-*` ids. The worker
recognized the mismatch and recovered without bypassing anything — it
registered a real liza_base worktree at a path *inside* the granted
worktree root so `hooks/edit-write-pwd-guard.sh` still governed its
writes, and probed that guard first to confirm it was live.

**Pre-flight smoke test** (battery step 1):

```bash
git remote -v
```

**Why the remote is the signal.** Four candidates were considered:

- **`git remote -v` (chosen).** It is the repo's identity as the *repo*
  declares it, independent of filesystem layout, and a worktree
  inherits its parent repo's remote config, so it reads identically
  from inside one. It is a read-only git command with no substitution,
  so the isolation harness accepts it.
- **Toplevel basename.** Useless alone inside a worktree: the basename
  is `agent-<hash>`. The *enclosing* path does embed the repo name
  today, but that is a filesystem accident of where worktrees are
  parked, not an identity the repo asserts.
- **Constitution project identity.** The constitution's front matter
  has no structured project-name field — only a prose comment header.
  Parsing that would be fragile. It stays a *corroborating* signal,
  which is the role it actually played in the incident.
- **bd id prefix.** A genuinely good signal, and it also caught the
  incident — but the battery already runs `bd list -n 1`, so promoting
  it to primary would add no new evidence. It stays corroborating.

The fallback for a repo with **no remote** is those two corroborating
signals plus the step-2 toplevel path. Say so in the report rather than
silently skipping the step.

**ABORT, do not adapt.** On mismatch the worker stops and reports.
It does not creatively route around the problem — the recovery in the
incident (registering a nested worktree of the correct repo) was sound
under supervision but is *not* the prescribed response, because a
worker that adapts silently produces a branch in a repo central is not
tracking.

**Cross-repo dispatch is UNSUPPORTED.** To dispatch a worker into
project X, **the dispatching session must be in project X.** There is
no brief wording, no path convention, and no flag that makes
`isolation: "worktree"` target another repo. If work is needed in
another project, open a session there. A brief that names a repo other
than the dispatching session's is a bug in the brief.

**No mechanical fix — and why this one earns a battery step.** Contrast
with Mode 6 (bash lib resolution, loom-8ztk), which deliberately added
**no** battery step: a bash-lib shadow is a property of the hooks
themselves, so it is settled **once, in the repo, by a gate**, and
every worker inherits the fix by running the suite. Repo identity is
the opposite kind of property. It is **per-dispatch** — it depends on
where the dispatching session happened to be sitting when it called
`Agent`, which no repo-side gate can observe and no committed file can
settle. A check that must re-run on every dispatch, against a fact that
varies per dispatch, has to live in the battery. The file now holds one
example of each: **settled-once → gate it, add no step; per-dispatch →
add a step.** That is the test for whether a new failure mode belongs
in the battery.

Central-side pre-detection was considered and rejected as a mechanical
guard — see "Central-side pre-dispatch repo check" below.

## Pwd verification

**Risk (Mode 1 — absolute-path-in-brief leak).** The dispatcher's
brief contains `/home/frank/repos/<project>/path/...` paths. The
worker dutifully uses them as the `file_path` argument to Edit/
Write. Those paths resolve to MAIN, not the worktree — commits
either land on MAIN's working tree, or land on a worktree branch
that's empty of the actual changes.

**Risk (Mode 4 — relative-path resolution surprise).** Even with a
brief that uses only relative paths (`tests/foo.py`), the path can
resolve OUTSIDE the worktree through symlinks or `../` traversal.
This is why the older "prefer-relative-paths-in-briefs" prescription
was dropped: relative paths alone are not sufficient. Verify the cwd
directly, canonicalized through realpath.

**Pre-flight smoke test** (battery step 2 — two separate calls, whose
outputs the worker compares):

```bash
realpath .
```

```bash
git rev-parse --show-toplevel
```

`realpath` normalization handles symlink-resolved worktree roots
(common when `.claude/worktrees/` sits behind a symlinked checkout
or when the worktree path itself contains `..` segments). Comparing
the two outputs by eye replaces the old
`[ "$pwd_real" = "$top_real" ]` shell test, which the isolation
harness refuses for its command substitution (loom-ta1w).

**Mechanical fix.** The `hooks/edit-write-pwd-guard.sh` PreToolUse
hook (loom-ymc) catches Mode 1 + Mode 2 + Mode 4 at write time: it
intercepts Edit/Write/MultiEdit calls in a worktree and refuses any
target that resolves outside the worktree root. Bypass with
`LOOM_EDIT_WRITE_GUARD_SKIP=1` when an intentional cross-tree write
is needed. See
[`docs/reference/edit-write-pwd-guard.md`](../../docs/reference/edit-write-pwd-guard.md).

## Python import resolution

**Risk (loom-rsk, Mode 5).** If `pip install -e <main>` was ever
run against the main repo, MAIN's source becomes a site-package on
sys.path. A worker running `python3`, `python3 -m pytest`, or any
Python script from the worktree gets MAIN's modules instead of the
worktree's modifications — tests pass against MAIN's behavior while
pretending to verify the worktree's changes. Silent and
post-merge-only.

**Pre-flight smoke test** (battery step 3):

```bash
python3 -c 'import <project_name>; print(<project_name>.__file__)'
```

The printed path MUST start with the worktree's toplevel
(`.claude/worktrees/agent-<id>/...`). If it points at MAIN, the
shadow is active — escalate to the wrapper below.

**Mechanical fix.** Use `scripts/loom-worktree-python` instead of
plain `python3` for any python invocation inside a worktree:

```bash
# Instead of:
python3 -m pytest tests/

# Use:
scripts/loom-worktree-python -m pytest tests/
```

The wrapper prepends the worktree's git toplevel to `PYTHONPATH`,
so the worktree's copy of the project always wins sys.path
resolution. It refuses to run in the main repo (the shadow doesn't
apply there) and passes through python3's exit code unchanged. See
[`docs/reference/loom-worktree-python.md`](../../docs/reference/loom-worktree-python.md).

## Bash lib resolution (loom-8ztk)

**Risk (Mode 6 — the bash flavor of the Python-import shadow).**
`install.sh` installs `~/.claude/lib/*` as **symlinks into the loom
repo's MAIN checkout**. A hook that sources
`$HOME/.claude/lib/loom-hook-helpers.sh` from inside a worktree
therefore loads **MAIN's** copy, not the worktree's. A dispatched
worker that modifies `lib/` and runs the hook tests gets tests that
silently exercise MAIN's code while appearing to verify its own
work — the exact same dishonest verification as the Python
`pip install -e` shadow above, in a different runtime. Silent, and
post-merge-only.

This one bites harder than the Python case in one respect: the
Python shadow needs someone to have run `pip install -e` at some
point, whereas the bash shadow is active on **every** loom
installation by construction — the symlinks are what `install.sh`
does.

**The fix — a TESTLIB-first source ladder.** Every hook resolves a
lib through three rungs, in this order:

```bash
# shellcheck source=../lib/loom-hook-helpers.sh
if [ -n "${LOOM_TEST_LIB_DIR:-}" ] && [ -f "$LOOM_TEST_LIB_DIR/loom-hook-helpers.sh" ]; then
  . "$LOOM_TEST_LIB_DIR/loom-hook-helpers.sh"
elif [ -f "$HOME/.claude/lib/loom-hook-helpers.sh" ]; then
  . "$HOME/.claude/lib/loom-hook-helpers.sh"
else
  . "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/loom-hook-helpers.sh"
fi
```

`LOOM_TEST_LIB_DIR` **must be the first rung.** A test that sets it
to the worktree's `lib/` then reads the worktree's copy; without the
first rung the installed symlink wins and the test reads MAIN's. The
`readlink -f` on the last rung is a separate fix (loom-fxad) — it
makes the repo-relative fallback resolve correctly when the hook is
reached through an installed `.git/hooks` symlink.

The rungs BELOW the first are each hook's own business: some end
fail-open (`2>/dev/null || true`), some fail-closed, and some omit
the repo-relative rung entirely. Preserve whatever posture the hook
already has — only the ordering is universal.

**Writing a test for a hook.** Export `LOOM_TEST_LIB_DIR` at the top
of the test file, pointing at the repo root's `lib/`:

```bash
LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export LOOM_TEST_LIB_DIR="$LOOM_ROOT/lib"
```

Inside a worktree `LOOM_ROOT` is the worktree, so the hook under test
loads the worktree's lib. This also means the suite no longer depends
on `install.sh` having been run.

**Mechanical fix.** `lib/tests/hook-source-ladder.test.sh` is the
gate. It scans **every** `hooks/*.sh` by glob — never a hardcoded
list, so a newly added hook cannot ship shadowed — and fails naming
any hook that references a lib without a guarded `LOOM_TEST_LIB_DIR`
rung ahead of the lower-precedence ones. Per gate-don't-advise
(loom-wj26.1) this is a correctness invariant, so it gates via
`script/test` rather than nudging.

Note this section adds **no step to the pre-flight smoke battery** —
unlike its Python sibling, which needs a per-worker check because the
shadow depends on whether anyone ever ran `pip install -e`. The bash
shadow is a property of the hooks themselves, so it is settled once,
in the repo, by the gate. A worker inherits the fix by running the
suite.

## bd state preseed

**Risk (Mode 3 — bd-state-empty fresh worktree).** Git worktrees
created via `git worktree add` get a copy of the repo tree
including `.beads/`, but the bd embedded-dolt DB under
`.beads/embeddeddolt/` is local-not-checked-in. The fresh worktree
inherits an empty dolt. The first write-class `bd` call inside the
worktree (`bd update --claim`, `bd close`, etc.) writes one-issue
state to the empty dolt AND auto-exports `.beads/issues.jsonl`,
overwriting the worktree's full checked-in copy. On merge to main,
**all other issues in issues.jsonl are silently lost**.

**Pre-flight smoke test** (battery step 4):

```bash
bd list -n 1
```

An error, or an empty result, means the embedded dolt is
empty and the next write-class bd call will wipe issues.jsonl on
merge. Stop and escalate. (The bare command replaces the old
`>/dev/null 2>&1 || exit 1` guard — the worker reads the listing
directly, and suppressing the output would have hidden the very
thing being checked.)

**Mechanical fix.** The `hooks/bd-worktree-preseed.sh` PreToolUse
hook (loom-x4m) pre-seeds the worktree's bd dolt on the first
write-class `bd` call inside a worktree. It runs `bd import
.beads/issues.jsonl`, sets `export.git-add=false`, and adds
`.beads/issues.jsonl` to the worktree's `.git/info/exclude`. The
sentinel `.beads/.loom-preseeded` memoizes the seed; self-heals if
the dolt is later wiped. Bypass with
`LOOM_BD_WORKTREE_PRESEED_SKIP=1`. See
[`docs/reference/bd-worktree-preseed.md`](../../docs/reference/bd-worktree-preseed.md).

**Sentinel absence at smoke-time is expected.** The preseed hook
fires on the first *write-class* bd call; the smoke battery's
`bd list -n 1` is read-class and does NOT trigger it. A fresh
worktree will not yet carry `.beads/.loom-preseeded` when smoke
runs — that's correct behavior, not a regression. The smoke check's
job is verifying dolt non-empty, not sentinel presence. See the
"Sentinel timing" section of the reference page.

## Base-freshness check

**Risk (loom-6zi, surfaced 2026-05-15 by loom-b1l worker).** A
dispatched worker on a fresh branch with NO commits yet runs
`git rebase main` and gets a no-op return code 0 — even when the
branch's merge-base trails main by N intervening merges. The
rebase is a no-op on an empty branch because there's nothing to
replay; it nonetheless returns success. The staleness only surfaces
post-commit when `git diff --stat main HEAD` shows unrelated files
(the intervening merges' contents). By then the worker has already
done work against a stale base; recovery requires a stash-bracketed
rebase against a partially-typed change set. Catch it pre-flight by
comparing merge-base against main's tip directly, before any work
begins.

**Pre-flight smoke test** (battery step 5 — two separate calls, whose
SHAs the worker compares):

```bash
git merge-base HEAD main
```

```bash
git rev-parse main
```

If the two SHAs differ the base is stale; rebase, then re-run both
calls to confirm they now match:

```bash
git rebase main
```

For an empty branch the rebase fast-forwards the branch tip to
main; for a branch with commits it replays them onto main. Either
way the worker proceeds on a known-fresh base AND knows its
starting point shifted (the diagnostic the silent no-op was
hiding). Doing the comparison in the agent rather than in an
`if … fi` shell block is what makes this step runnable under the
isolation harness (loom-ta1w).

**Mechanical fix.** Use `scripts/loom-rebase-worktree main`
(loom-azt) instead of plain `git rebase main` when untracked WIP
from a prior crash needs preserving across the rebase. The wrapper
refuses outside a linked worktree, snapshots untracked files,
pre-detects collisions, and restores files post-rebase. See
[`docs/reference/loom-rebase-worktree.md`](../../docs/reference/loom-rebase-worktree.md).

## Worker-side leak check (loom-ta1w)

**Before handing back, a worker verifies its own footprint** — that
what it changed is exactly what it meant to change, and that nothing
leaked into the shared checkout.

**Risk (the un-runnable leak check).** The obvious way to check "did
I leak into main?" is to look at main's working tree, pointing git at
the main checkout's absolute path with a `-C` redirect. **A worker
cannot run that.** The isolation harness refuses it with a message
distinct from the too-complex one:

> This agent is isolated in the worktree `<path>`, but this command
> redirects git to the shared checkout via `-C`. Refusing to run it —
> a worktree-isolated agent's git operations must target its own
> worktree.

Three workers in one session (loom-vr6k, loom-8ztk, loom-qo4j) each
hit this and each improvised a *different* fallback — a content
comparison against the `main` ref, or a bare directory listing. Those
improvisations were sound but ad hoc, and an ad-hoc check is one
nobody reviewed.

**The fix — go through git REFS, not the main working-tree PATH.**
Refs are fully visible from inside the worktree, so both questions a
worker needs to answer are answerable without leaving it.

*What did my branch actually touch?*

```bash
git diff --stat main HEAD
```

The listed paths must match the bead's declared `Files:` (plus any
footprint expansion the worker is about to declare in its report).
Unrelated files here mean either a stale base (re-run battery step 5)
or a genuine leak.

*Should this path be absent from main?* Compare against the main
**ref** rather than the main **path**:

```bash
git show main:<path>
```

A `fatal: path '<path>' does not exist in 'main'` is the expected,
successful answer for a file the worker newly created. Content coming
back means the file already exists on main — inspect before assuming
a leak.

**This is DISTINCT from the Edit/Write pwd guard.** Two different
mechanisms, easy to conflate, and conflating them is harmful:

- The `git -C` refusal above is the **isolation harness**, at the
  **Bash** level. It is a limitation to route around — hence the
  ref-based checks in this section.
- `hooks/edit-write-pwd-guard.sh` (loom-ymc) is **loom's own hook**, on
  the **Edit/Write/MultiEdit** tools, refusing writes that resolve
  outside the worktree. When it blocks a write — including an
  out-of-worktree scratchpad `Write`, as it correctly did for two
  workers this session — **it is working exactly as designed**. Do not
  treat that block as the same problem, and do not reach for
  `LOOM_EDIT_WRITE_GUARD_SKIP=1` to "fix" it; write inside the
  worktree instead.

**Central's leak check is unchanged.** Central runs from the main
checkout, where a plain `git diff --stat` works and is still the right
call after a dispatch wave returns. This section is the worker-side
counterpart, for the one context where that command is unavailable.

## Worker-report sampling transparency (loom-z3m.16)

**Risk (loom-z3m.1 f10, liza-base).** When a dispatched worker
processes only a SAMPLE/subset of a larger set — it chose N-of-M items
rather than all M (a sampled remine, a truncated scan, "the first two
dozen of 600") — that fact does not reliably surface in its return.
The user has to ask "so you only grabbed a sample?" after the fact.
The truncation looks like completeness; the report is silently
dishonest about scope.

**Convention.** Every dispatched worker that samples or truncates MUST
surface the fact explicitly in its structured return —
**never silently sample.** When the worker processed a subset, include a
`Processed: X of Y` line (sampled-of-total) in its report, naming both
the count it handled and the size of the full set. A worker that
processed the entire set need not state it; a worker that did NOT must.
Centrally, the dispatcher should add a `sampled_of_total` field
requirement to any worker brief when the input set is large enough that
the worker might reasonably sample it — so the obligation is briefed
in, not relied on as an afterthought. This is the worker-report
analogue of the smoke battery: a single structured line a downstream
consumer (the user, or central) reads to know scope at a glance.

## Claim provenance in worker returns (loom-myhi)

**Risk (provenance flattening; design drawer
`drawer_loom_decisions_1a296178707cdc55c872b467`).** A worker's report
blends rigorously-verified claims with unverified inferences at uniform
confidence, and the verified ones lend their credibility to the
inferred one. Central is not failing to examine the report — it is
correctly reading a report that erased a distinction its own author
held. The distinction existed at authoring time, so the fix needs no
second agent to re-derive it: the worker states it as it writes.

**Convention — the evidence slot (D2).** Every load-bearing claim in a
worker's return carries **either** a citation — the command run and its
result, or a `file:line` — **or** the literal marker `INFERRED`. Never
neither. A citation is a **pointer, not a rationale**: it says where to
look, not why to believe. Do not write a justifying sentence into the
slot. Reasoning stays wherever the report already keeps it (a triple's
`*Why*` line, the surrounding prose); the slot only points.

**Two surface forms — both are slots.** Which form to use follows the
shape of the report, and one report may carry both.

*Bracket form*, in prose reports (dispatched workers, `drawer-author`,
`bug-family-researcher`, `project-onboarder`). A trailing bracketed
token ends the claim line:

```
FIFO ordering is broken by the map range.   [INFERRED]
The deleted test pinned FIFO.               [test_methods.go:151]
All 4 mutants die under the new test.       [go test -run TestScan -count=1 → 4/4]
```

*Field form*, in structured triple reports
(`agents/kg-relationship-extractor.md:35`). Triples are not sentences
and already carry a `*Why*` line, so bracketing would collapse the slot
into the rationale — exactly what D2 splits apart. The slot is instead
a **line-leading `evidence:` field**, matched anchored
(`^\s*evidence:`), parallel to loom's `Files:` / `RED:` /
`AUTOFAN-EXCLUDE:` convention — so a mid-prose mention of the word is
not a slot:

```
1. `subject` → `predicate` → `object`
   valid_from: YYYY-MM-DD
   source_closet: (optional drawer ref)
   evidence: <command + result, or file:line, or INFERRED>
   *Why*: <one sentence>
```

Describing only the bracket form understates the contract: a
bracket-only reading skips every triple report wholesale — a whole
agent's output passing by being invisible.

**Both arrow glyphs.** In either form, a payload containing an arrow is
a **command citation**: the command is the text before the arrow, the
result after. The separator may be ASCII ` -> ` **or** Unicode ` → `
(U+2192), and both are accepted. This is not cosmetic — measured on the
shipped agent definitions, the Unicode arrow is used *exclusively*
(`grep -c ' -> ' agents/drawer-author.md agents/bug-family-researcher.md
agents/kg-relationship-extractor.md` → `0/0/0`; the same count for
` → ` → `1/2/9`), while ASCII is what gets typed in prose. Pinning one
glyph would miss every real command citation in the wild. A payload of
the `path:line` shape is a **file citation**; a bare `INFERRED` is the
marker.

**F1 is "zero slots of either form" — never "zero brackets".** A
bracket-free triple report whose triples each carry an `evidence:` line
is fully evidenced and PASSES. Counting brackets would fail an entire
agent's output for using the form that agent is specified to use.

**Refuting a claim is TWO fields — verdict + residue (D5).** When
central refutes an `INFERRED` claim, the disposition answers two
*separate* questions:

- **`verdict`** — was the claim true, and why.
- **`residue`** — was it pointing at anything? The literal `none` is a
  valid answer; **absence is not**.

A refuted claim can still be load-bearing. The claim that motivated
this rule was wrong about FIFO ordering *and* surfaced a real untested
liveness gap; the test that eventually landed was strictly stronger
than the property the reviewer had correctly defended. A binary
accept/reject discards the claim and the gap along with it — which is
why `residue` is a field of its own rather than a clause inside the
verdict.

**File before acting on an `INFERRED` claim (D6).** Central may not
make a change on the basis of an `INFERRED` claim without **filing it
first**; the filed bead is where D5's `verdict` + `residue` land, so D6
gives D5 a mechanical home. This is not size-scoped — a three-line
change built on a wrong premise is still wrong, so the ≤15-line inline
threshold does not exempt it. Claims central does **not** intend to act
on simply stay in the worklist: no filing, no ceremony.

**Mechanical fix.** `scripts/loom-claim-provenance` is the gate — a
central-side reader over the session's `agent-*.jsonl` subagent
transcripts, which central runs after a dispatch returns. (Not a hook:
`Stop` / `SubagentStop` do not reliably fire on sidechains, so no hook
can ever observe a worker's return — see
[`docs/reference/claude-code-hook-semantics.md`](../../docs/reference/claude-code-hook-semantics.md).)
It reads the worker's FINAL report plus its tool calls, and fails on
exactly two mechanical conditions:

- **F1** — the final report carries zero evidence slots of either form.
- **F2** — the report cites a command absent from that worker's own
  tool calls.

Everything else succeeds, emitting each `INFERRED` claim as a worklist
for attended review. The reader NEVER judges whether an `INFERRED`
claim is true: that is attended judgment, and gating it would produce a
rubber-stamp. Gate the structure, nudge the claims — gate-don't-advise
(loom-wj26.1) applied to this contract.

## Central-side pre-dispatch repo check (loom-stdi — considered, not built)

Catching a Mode 7 brief *before* dispatch would be cheaper than
catching it worker-side. A mechanical version was considered and
**deliberately not built**, because it cannot be made reliable.

The proposal was: scan the brief for a named repo, compare against the
dispatching session's toplevel, warn on mismatch. The failure is in the
first step — a brief is free-form prose, and "names a repo" is not a
decidable property of it. The counterexample is this bead's own brief:
`loom-stdi` is a legitimate **loom** dispatch whose brief mentions
`liza_base` a dozen times, because liza_base is the subject of the
incident being documented. Any scanner that would have fired on the
2026-07-25 brief fires on this one too. A guard that cries wolf on
correct briefs is worse than no guard: it trains central to dismiss it,
and the one real hit arrives pre-dismissed.

Nor can the check be sharpened by requiring an explicit target-repo
field in every brief. Central would fill that field from its own cwd,
so it would be correct by construction and would never disagree with
reality — the contradiction would still only be visible against the
brief's *prose*, which is the undecidable part again.

**What is prescribed instead** is an authoring convention, not a
detector: when a brief states which repo the worker is in, central
states it from the **output of `git rev-parse --show-toplevel`**, not
from memory of where the session started. The 2026-07-25 brief asserted
`liza_base` from central's intent rather than from its cwd, and intent
is exactly what was wrong.

That is advisory by design and does not violate gate-don't-advise
(loom-wj26.1). The correctness invariant here — *the battery contains a
repo-identity step that aborts on mismatch* — **is** gated, by
`lib/tests/dispatched-agents-rule.test.sh` in `script/test`. What stays
advisory is the brief-authoring habit, which is an attended judgment a
human or central makes per dispatch: the nudge case, not the gate case.

## Central-side cwd verification (after worker dispatch returns)

**Risk (loom-d2o, surfaced 2026-05-27 by the loom-7p6 + loom-cuk
parallel-completion sequence).** This is the worker-side battery's
mirror failure mode, on the CENTRAL agent's persistent-bash
session. After 7 background workers were dispatched and one
returned (loom-7p6.7), central's persistent-bash cwd silently
resolved into the returned worker's
`.claude/worktrees/agent-a36b96c117ccefeda/` — no explicit `cd`
was issued. The next two ops mis-routed:

- `bd close loom-7p6.7` ran in the worktree's bd context. The
  worktree's `.beads/` permissions warning (`0775 != 0700`)
  surfaced first; the close itself wrote to the worktree's dolt
  and propagated through bd's sync layers from the wrong tree.
- `git merge --no-ff frank/loom-7p6.7` returned 'Already up to
  date' because from the worktree, the branch tip IS HEAD —
  central thought it was merging into main, but was effectively
  no-op'ing against the worker branch.

The drift is silent: no notification, no banner, no diagnostic.
Pre-completion `pwd` looked correct; post-worker-return `pwd`
silently changed. Mechanism is opaque from the Claude Code
harness's outside (persistent-bash cwd state may leak across the
worker dispatch boundary, or the completion-notification path may
propagate cwd back).

**Mechanical fix.** The `hooks/cwd-drift-guard.sh` PreToolUse
hook (loom-d2o) intercepts five central-context Bash commands
when cwd resolves inside `.claude/worktrees/agent-*/`:

- `git merge` (any options)
- `git push` (any options)
- `bd close` (any options)
- `bd update` (any options)
- `bd dolt push`

It refuses with `exit 2` and emits a stderr message naming the
worktree root, the inferred main root, and the recovery command
(`cd <main-root> && <retry>`). Bypass via
`LOOM_CWD_DRIFT_GUARD_SKIP=1` (literal-"1" match per loom-b1l;
`=yes`/`=true`/`=0`/empty all rejected). See
[`docs/reference/cwd-drift-guard.md`](../../docs/reference/cwd-drift-guard.md).

Read-only ops (`git status`/`log`/`diff`/`branch`, `bd
list`/`show`/`ready`) are NOT in the allowlist — they're safe
from any cwd and pass through silently.

**Convention fallback.** After any parallel-dispatch wave
returns, central should verify cwd before the first
merge/push/bd-close:

```bash
pwd                            # should be the main repo root
git branch --show-current      # should be `main` (or central's branch)
```

If `pwd` shows a `.claude/worktrees/agent-<id>/` path, run
`cd <main-root>` before any central-context op. The hook will
also catch it mechanically; the convention is the read-only
diagnostic.

The hook composes with the worker-side battery: workers use the
six-step pre-flight smoke battery above; central uses the
cwd-drift hook on returning from each dispatch wave. Defense in
depth.

## Background dispatch is the DEFAULT (loom-li8h)

**Central dispatches workers with `run_in_background: true` by
default.** This is the central-side dispatch posture that the
worker-side battery above presupposes: workers run while central is
free to do other things.

**Risk (the foreground-wait anti-pattern).** A foreground dispatch
holds central's turn idle until the worker returns — central sits and
waits, doing nothing, for the whole RED→GREEN cycle. Observed all
session 2026-06-08 (the parallel wave + both `/dispatch-middle`
pipelines ran foreground). It contradicts dispatch-v2's lean-central
goal: central should not be *blocked* during the middle, only
*write-nothing*.

**Default.** Dispatch with **`run_in_background: true`**. Central
**yields the turn** the moment it dispatches and **resumes on the
worker's completion event** — free meanwhile to converse with the
user, plan, pre-stage the next bead, or revise the in-flight contract.
Foreground is the explicit **exception**, reserved for the narrow case
where the **next step is immediate integration with nothing else
interleavable** (a single short dispatch central will merge + close the
instant it lands, with no conversation/planning/staging to fill the
gap). When in doubt, background it. See the Dispatch-mode sections of
`skills/dispatch-middle/SKILL.md` and
`skills/bead-lifecycle-shell/SKILL.md`.

## Concurrency caution — never two full-suite loops in one repo at once

Backgrounding makes multiple agents in flight cheap and is the default
above — but there is one hard concurrency rule: **never run two
full-suite loops in the same repo at the same time.** Two suite runs
racing in one working tree contend on shared git/bd state and produce
nonsense numbers.

**Risk (loom-fx9m close detour, 2026-06-08).** A foreground-wait
combined with the harness auto-backgrounding a long-running loop
produced **two suite runs racing in one repo**. When the duplicate
suite task was `TaskStop`'d, it left **orphan `bd-post-rewrite` child
processes** behind: `TaskStop` reaps the task it targets but **may not
reap that task's grandchildren**, so the orphaned children kept racing
on git/bd state and yielded a **false `63/2` suite result**.

**Convention.** One suite loop per repo at a time. After any
`TaskStop` on a suite/loop task, confirm no orphan `bd-post-rewrite`
(or other grandchild) processes survived — e.g.
`pgrep -fa bd-post-rewrite` should be empty — before trusting any
suite number. Treat a suite result obtained while a second loop or a
just-`TaskStop`'d task was live as untrustworthy until re-run clean.

## API 529 / overload resilience

**Risk (loom-417, surfaced 2026-05-06 during liza_base FRH Wave C).**
The Claude Code harness routes EVERY agent call — including a
subprocess `claude` CLI spawned from inside an agent — through the
**same** Anthropic API backend. There is no "go-around" path. When
that backend is overloaded and returns 529, the entire
parallel-dispatch flow is wedged at once, and it fails at three
distinct stages:

1. **Mid-flight crash.** An agent that has done substantial work hits a
   529 on a model call and dies. Its worktree filesystem state is
   preserved on disk, but uncommitted/unmerged; bd state may be
   in transit.
2. **Resume crash.** Central dispatches a resume agent into a still-sick
   API; it dies in **~4 seconds with 0 tool uses** — it never starts.
   Resume cannot begin until API health recovers.
3. **Sustained outage.** Several agents in one wave crash within
   seconds of each other (in liza_base, all three Wave C agents —
   wx7, 982, 9uo — went down on one 529 burst). Re-dispatching into
   the burst just burns context on agents that immediately die.

This section is the operator/central playbook for surviving the burst.
It is **doc-only** — there is no detect/pause script yet (building one
needs a live 529 to repro against). The four parts compose:
**DETECT** the burst → **don't resume into a sick API** → **resume from
the crashed agent's WIP** → and the whole time, the **drawer is the
only artifact that survives the crash**.

### Part A — DETECT: the API-health-pause heuristic

**The signal.** When **≥2 agents in one wave crash with a 529 in a
short window**, treat it as an API-overload burst, not as N independent
agent bugs. The diagnostic tell of a resume-too-early death is sharp:
the agent **dies in ~4s with 0 tool uses** — no smoke-battery output,
no Edit, nothing. A normal agent failure looks different (it gets
somewhere first); a 529 resume-death is near-instant and empty.

**The response — surface an "API health pause."** On the second
near-instant 529 death, central STOPS dispatching. Do not keep
throwing agents at the burst: each one dies in ~4s having accomplished
nothing but context spend, and the rapid-fire retries can deepen the
overload. Announce the pause to the user, note which beads are parked
mid-flight, and move to Part B (probe-before-resume) rather than
immediately re-dispatching. wx7 in the liza_base case **did** come back
on a later independent retry — the burst is transient, so the pause is
a wait, not an abort.

### Part B — HEALTH-PROBE-BEFORE-RESUME + exponential backoff

**Never resume straight into a sick API.** A blind re-dispatch during
the pause just reproduces the ~4s/0-tool-use death. Instead:

1. **Probe health first.** Send a single cheap call (a one-line
   throwaway agent, or any minimal model request) and watch whether it
   completes or 529s. The probe is the canary; the expensive
   resume-from-WIP agent only goes out once the canary returns clean.
2. **Back off exponentially between probes.** Start small (~30s) and
   double each failed probe (30s → 1m → 2m → 4m → …), capped at a
   few minutes. This avoids both extremes the sibling-concern names:
   **resume too early** → the agent dies again; **resume too late** →
   the crashed agent's untracked WIP keeps drifting stale relative to
   `main` (every intervening merge widens the gap the resume agent must
   rebase across). Exponential backoff threads between them — quick
   while the outage is short, patient when it sustains.
3. **Resume only after a clean probe.** Once a probe completes
   normally, dispatch the real resume-from-WIP agent (Part C). If it
   529s anyway, the burst is still live — fall back to the next backoff
   interval and re-probe.

### Part C — RESUME-FROM-WIP recipe shape

When a mid-flight agent died with work stranded in its worktree, the
resume agent does NOT start from scratch. Its brief is the shape
**"check what the previous agent left in the worktree, verify it,
finish what's left"**:

1. **Inventory the WIP.** In the crashed agent's worktree, run
   `git status` + `git diff` + `git log --oneline main..HEAD` to see
   what was committed, and `git status --porcelain` to see what is only
   on disk (untracked / unstaged). The crash froze the worktree at an
   arbitrary point — committed work, staged work, and bare-on-disk WIP
   can all coexist.
2. **Preserve untracked WIP across any rebase.** The crashed worktree's
   base may now trail `main`. Do NOT plain `git rebase main` — on a
   branch with bare untracked files that can lose them, and the smoke
   battery's step 5 rebase only handles the no-WIP case. Use
   **`scripts/loom-rebase-worktree main`** (loom-azt): it snapshots
   untracked files, pre-detects collisions, rebases, and restores the
   files afterward. This is the same WIP-preservation the smoke battery
   references for crash recovery — see the **Base-freshness check**
   section above and
   [`docs/reference/loom-rebase-worktree.md`](../../docs/reference/loom-rebase-worktree.md).
3. **Verify before extending.** Re-run the bead's RED test / the suite
   against the recovered state to learn exactly how far the dead agent
   got — what is already GREEN, what is still RED. Trust the test, not
   the dead agent's last (possibly truncated) report.
4. **Finish only the remainder.** Implement the still-RED slice, commit
   on the same `frank/<bead-id>` branch, and hand back for integration
   as normal. The resume agent re-runs the worker-side pre-flight smoke
   battery at the top of its session like any dispatched worker.

### Part D — DRAWER-AS-RECOVERY-SURFACE

**File the decision drawer FIRST — it is the only crash-resilient
artifact.** The worktree filesystem can be stranded unmerged, and bd
state may be mid-flight; both are volatile under a 529 burst. The
**MemPalace decision drawer lives outside the worktree and outside bd**,
so it survives every crash mode in Part A. Therefore the drawer is
written **before** the dispatch, not deferred to the phase-D3 capture
fan-out, and its body must be **detailed enough to rebuild the
implementation from the drawer alone**: the locked contract, the `RED:`
spec, the chosen approach, the file plan, and any non-obvious
constraints. A resume agent (or the next session) that finds a
half-finished worktree reads the drawer to reconstruct *intent*, then
uses Part C to reconcile that intent against whatever the dead agent
actually left on disk.

This promotes the old "file the drawer first" convention to a
**recipe requirement** — see the corresponding MANDATORY note in the
Dispatch-discipline section of
[`skills/bead-lifecycle-shell/SKILL.md`](../../skills/bead-lifecycle-shell/SKILL.md).
The D3 capture then *updates* the already-existing drawer with
verification-at-close + landing SHAs rather than authoring it from
scratch. Operator-facing walkthrough:
[`docs/how-to/recover-from-dispatch-crash.md`](../../docs/how-to/recover-from-dispatch-crash.md).
