# Loom's shipped conventions

> **Loom owns this file. Do not edit it.**
>
> It is synced from loom's `templates/rules/loom-conventions.md` and is
> overwritten in place whenever loom's convention set moves. Anything
> you write here is lost on the next sync. Project-specific rules —
> your tooling, your hazards, your voice — belong in your own
> `CLAUDE.md` and your own `.claude/rules/*.md`, which loom never
> touches.
>
> Resync with `/audit-project --apply-drift` (per-item review; nothing
> is applied without an explicit approval). Disagree with something
> here? Take it up with loom rather than patching the copy — a local
> patch reverts silently and takes the disagreement with it.

These are the working conventions loom ships to every project it
manages. They are deliberately project-agnostic: nothing below assumes
a language, a test runner, a package manager, or a directory layout.
Where a convention needs a project-specific value, it names a slot
(your branch prefix, your canonical test command) rather than a value.

---

## Working a bead — isolation and dispatch

### One bead = one branch = one worktree

Non-trivial work happens on a dedicated branch (`<prefix>/<bead-id>`)
in an isolated git worktree, never directly on the default branch. Skip
the worktree only for genuinely trivial tweaks (≤1 line). The worktree
directory should be gitignored.

### Worker-dispatch is the default for the variable middle

**A worktree is not a dispatch.** Isolating central's own typing into a
worktree satisfies the rule above and satisfies *nothing* about who
does the work — central editing files inside a worktree is still
central editing files. Two independent decisions, and both have to
actually be made:

1. *Where do the edits land?* → the worktree.
2. *Who types them?* → **a dispatched worker, by default.**

**Any bead whose middle has a RED→GREEN cycle defaults to a dispatched
worker.** Inline — central editing directly — is the explicit
**exception**, waved through without justification only when the change
is **≤ ~15 lines AND touches a single non-test file AND adds no new
test**. Anything larger gets dispatched.

Record which one you chose. A ticked worktree box must never stand in
for a dispatch decision that never happened.

### Background dispatch is the DEFAULT

When dispatching a worker, use **`run_in_background: true` by
default.** A foreground dispatch holds central's turn idle until the
worker returns — central sits and waits for the whole RED→GREEN cycle.
Background dispatch lets central **yield the turn** and **resume on the
worker's completion event**, free meanwhile to converse, plan,
pre-stage the next bead, or revise the in-flight contract.

Foreground is the explicit exception, reserved for the narrow case
where the next step is immediate integration with nothing else
interleavable — a short dispatch central will merge and close the
instant it lands.

**One full gate run per repo at a time.** Backgrounding makes several
agents in flight cheap, but two full test-suite runs racing in one
working tree contend on shared git and tracker state and produce
nonsense numbers. Also beware CPU contention: gating while a dispatched
worker saturates the box flakes timing-sensitive tests into false REDs.

### Dispatch path discipline

`isolation: "worktree"` sets a worker's cwd but does **not** sandbox
filesystem operations — Edit/Write accept any absolute path, so a brief
full of main-repo absolute paths leaks the worker's writes into the
shared checkout. The flag itself is not a guarantee either: it has been
observed omitted, silently no-op'd on background dispatches, and
producing a worktree of the wrong repo entirely.

So: every committing dispatch runs the **pre-flight smoke battery** on
the way in; every worker verifies its own footprint through **git refs**
on the way out (`git diff --stat <default-branch> HEAD` — never a
`git -C <main-path>` redirect, which the isolation harness refuses);
every dispatcher verifies its own cwd and the default branch's tip
after a wave returns.

Your project's `.claude/rules/dispatched-agents.md` carries the battery
itself and the project-specific hazards. Read it before any dispatch.

### Cross-repo dispatch is unsupported

`isolation: "worktree"` worktrees the **dispatching session's** repo,
whatever the brief claims. It does not read the brief, and no parameter
selects a different repo — so **to dispatch a worker into project X,
the dispatching session must be in project X.** A brief naming any
other repo is a bug in the brief; state the repo from the output of
`git rev-parse --show-toplevel` rather than from memory of where the
session started.

A worker that finds the mismatch **aborts and reports** rather than
adapting. This is the one case where relative-path discipline turns
against you — in a wrong-repo worktree a relative path resolves to
*that* repo's real file of the same name, so obeying the brief is what
does the damage. The repo-identity check that catches it, and the
failure mode behind it, are in your
`.claude/rules/dispatched-agents.md`.

### Claim provenance in a worker's return

Every load-bearing claim in a worker's return carries **either** a
citation — the command run and its result, or a `file:line` — **or**
the literal marker `INFERRED`. Never neither. A citation is a
**pointer, not a rationale**: it says where to look, not why to
believe, so no justifying sentence belongs in the slot. Reasoning stays
wherever the report already keeps it.

A report that blends verified claims with unverified ones at uniform
confidence lets the verified lend their credibility to the rest. The
distinction exists while the worker is writing, so the worker states it
then rather than leaving a reader to re-derive it. Your
`.claude/rules/dispatched-agents.md` carries the two surface forms (a
prose report brackets the slot at the end of the claim; a structured
triple report uses a line-leading `evidence:` field), how a refuted
claim is dispositioned, and what central may act on without filing it
first.

---

## Bead conventions

### Declare `Files:` in every bead description

A comma-separated line of repo-relative paths the bead is expected to
touch:

```
Files: src/thing/operations.ext, tests/thing/test_operations.ext
```

This is the input the fan-out detector uses to decide which ready beads
are safe to dispatch as one parallel wave: two beads are wave-compatible
iff they have **no dependency edge** between them **and** their `Files:`
sets are **disjoint**.

The detector **degrades conservative** — a bead with no `Files:` line is
treated as "footprint unknown, not provably disjoint" and is **excluded
from every proposed wave**, so it silently never gets parallelized.
`Files:` is also what a worker's ref-based leak check compares its
actual footprint against.

Format: comma-separated paths on a single line beginning `Files:`.
Trailing parenthetical or bracketed annotations and a leading `optional`
marker are tolerated and stripped during matching.

### `RED:` spec-line on a bead spawned from a testable design decision

A single line beginning `RED:` carrying the decision's executable spec
verbatim — a behavioral Given-When-Then scenario, or a structural
`INVARIANT: …`.

The implementation bead **inherits its RED test from this line**: the
recipe's RED→GREEN middle starts from the `RED:` text rather than
re-deriving the acceptance criterion.

Optional by construction. Soundness is two-tier — coherence is the
always-on floor; executable-spec emission is an optional ceiling for
decisions that have a natural testable altitude. A decision with no such
altitude omits the line, and that is expected, not a gap. Forcing a
`RED:` onto every bead re-imports the design→build mismatch the line
exists to remove.

### `AUTOFAN-EXCLUDE: <reason>` marker

A bead whose description carries a leading `AUTOFAN-EXCLUDE:` line is
excluded from every wave the fan-out detector proposes — for attended,
upstream, needs-decision, or design work that must **not** be
auto-dispatched into a parallel wave.

The detector matches the anchored line form (`^\s*AUTOFAN-EXCLUDE:`),
parallel to `Files:` and `RED:`; a bead that merely mentions the string
mid-prose is not excluded. `<reason>` is free text.

### Splitting heuristic at bead creation

When filing 2+ candidate items, ask: are they independent — no shared
files, no sequential dependency?

- **Yes** → file them as sibling beads under an umbrella feature/epic.
  The ready-work query will surface them for parallel dispatch.
- **No** (shared files, or one depends on the other's outcome) → file
  them as one bead.

This prevents the slip at the source; the within-bead parallel nudge in
the lifecycle shell only catches what gets through.

### Capture decisions in memory — and file the drawer BEFORE dispatching

Substantive decisions go to your project's memory substrate, not only to
the tracker. **The drawer is the design source-of-truth; the repo is the
implementation source-of-truth.** When they diverge, the drawer wins on
intent and the repo wins on what currently works.

The drawer is also the **only artifact that survives a mid-flight agent
crash** — a worktree can be stranded unmerged and tracker state can be
in transit, while the drawer lives outside both. So it is written
**before** the dispatch, not at close, and detailed enough to rebuild
the implementation from the drawer alone: the locked contract, the
`RED:` spec, the chosen approach, the file plan, and any non-obvious
constraints. The capture at close then *updates* it with verification
and landing SHAs rather than authoring it from scratch.

---

## Gate, don't advise

Every drift-detector or correctness check MUST be wired to a real
enforcement gate — a test in your canonical suite, a git hook, or CI —
**never left as an advisory grep a human has to remember to run.** An
advisory-only correctness check is a latent rot surface: the drift it
was meant to catch comes back silently, and nobody learns until someone
happens to eyeball the result.

This is **distinct** from a deliberate nudge. A nudge is the right shape
for an **attended decision** a human should weigh in on; gate-don't-advise
governs **correctness invariants** that must never depend on human
memory.

The dividing question: *is a human supposed to weigh in?*
If yes → nudge. If the check just needs to be **true** → gate.

---

## Above-bead work: explore → design → build

Neither exploration nor design is a bead. **Do not file one as a bead or
an epic.** Their state lives in the memory substrate, and they *emit*
beads once decisions lock.

- **`/explore <idea>`** opens a SUB-design exploration — four source
  tiers (self · repo + docs · web · peer-reviewed literature)
  converging on shared understanding before anything is design-ready.
  No soundness gate, no epic emission. Two user-declared exits: **REST**
  (the drawer stands as standing understanding) and **PROMOTE** (opens
  a design cycle grounded in it).
- **`/design-a-cycle <topic>`** drives a design cycle's
  Plan → Research → Architect cadence over the layered substrate and
  emits the implementation epic once decisions lock.

The governing posture is **reason-in-prose, precipitate-into-structure**:
in-flight thinking happens on a permissive prose surface, and as
decisions firm up they precipitate into the structured destination —
memory facts, locked-decision sections, and the `RED:` / `Files:` lines
on emitted beads. Opinionated about *where* locked structure lands and
*when*; permissive about how you got there.

**Peer-reviewed literature is included by default** in every deep-research
round, in any skill or recipe — not just `/explore`. The invoking brief
is the only lever that sets this, so it must say so explicitly.

---

## The project constitution is the tooling profile

`.claude/project-constitution.md` pins the shell envelope, package
manager, language runtime, the canonical build/test/lint/gen/dev
commands, and the `forbidden:` / `bypass_patterns:` lists — over a
human-authored prose body of rationale.

Dispatched workers read it as step 0 of the pre-flight battery, so they
run **your project's canonical command** instead of guessing one. That
guess — the wrong package manager, the wrong test command — is exactly
what the constitution exists to kill.

Evolve it via `/audit-project --check=constitution`, one field at a time
with confirmation, not by hand-editing past a field you have not
confirmed.
