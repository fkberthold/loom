# Claude Workflow Walkthrough — Feature Shape

> A narrative session walkthrough showing what the feature-a-bead
> recipe looks like end-to-end. Companion to `walkthrough.md` (the
> bug-shaped walkthrough) — this file shows the *feature* recipe in
> motion using a real bead from the loom project (`loom-1ab`: turn
> `/working-a-bead` into a router that dispatches to the matching
> activity recipe by `bead.type` + description heuristics).
>
> Format: "**You:**" lines are what you type; "**Claude:**" lines are
> the assistant's response (sometimes summarized, sometimes verbatim);
> indented italic blocks are commentary on what's happening behind the
> scenes. Hook output appears in `[brackets]` when relevant.
>
> Honesty caveat: the bead is real and shipped on 2026-05-04 at
> commit `da939e6`. The close note explicitly read "End-to-end smoke
> test deferred to next session," so the verification described below
> is the *designed* shape — what the recipe asks for, not necessarily
> what every loom-1ab session produced. Where this walkthrough is
> aspirational rather than observed, a note flags it.
>
> Why feature-a-bead instead of bugfix? `loom-1ab` introduces a new
> behavior (a router) where none existed; there is no symptom to
> reproduce, only a contract to pin. That's the central inversion vs.
> the bug walkthrough — RED tests pin desired contract, not a failure.

---

## The session

You sit down to ship `loom-1ab`, the v2 router for `/working-a-bead`.
Five sibling recipes already shipped (`feature-a-bead`,
`refactor-a-bead`, `cleanup-a-bead`, `docs-a-bead`, plus the rename of
`working-a-bead → bugfix-a-bead` via `loom-lzi`); the router is the
last blocker before the manual + walkthrough bead (`loom-qj3`) can
move. The design is already locked in the MemPalace drawer
"RECIPE SHAPES — ACTIVITY MATRIX" (`hundred_acre_woods/decisions`,
2026-05-02) — Frank pinned six decisions there, including "router
goes straight to selector pattern, not phased intro" and "ambiguity
case lists candidates with one-line because, prompts user." Your job
is to translate the locked design into `commands/working-a-bead.md`.

### 0. Open terminal, launch Claude Code

```
$ cd ~/repos/loom
$ claude
```

*The shell launches Claude Code. You see the welcome message and the
prompt cursor blinks.*

**[v1.5]** *Status line at the bottom of the TUI now reads:*
`WORKFLOW: light | idle | 4h` *(populated from
`/home/frank/repos/loom/.claude/workflow-state.json`, mode resolved
from `workflow.json`. Loom uses `light` mode — most loom changes are
markdown skill text + small bash + no real test suite, so the full
ceremony is overkill and the `light` settings file ships in the
repo).*

### 1. Cold start — session prime

**You:**
```
/clear
```

*The `/clear` triggers a SessionStart event. Plugin hooks fire
automatically and silently: beads' hook runs `bd prime`; mempalace's
hook acknowledges the last stop checkpoint; superpowers + beadpowers
load their `using-*` meta-skills.*

**You:**
```
let's pick up where we left off
```

**Claude:** *(invokes `/session-startup`)*

> Workflow mode is `light` — abbreviated startup.
>
> **bd ready** leads with `loom-1ab` (P2, the `/working-a-bead`
> router). The four sibling recipes shipped earlier today (commit
> `2dfa53e`); `loom-1ab` is now unblocked. After that, only `loom-qj3`
> remains in epic `loom-0y6` (87% done).
>
> **In-progress:** none.
>
> **Recommendation:** ship `loom-1ab`. The design is locked in the
> "RECIPE SHAPES — ACTIVITY MATRIX" drawer (HAW decisions,
> 2026-05-02); this is execution against locked design, so brainstorm
> light. Bead is feature-shaped (new behavior) — `feature-a-bead`
> recipe applies.
>
> Proceed with `loom-1ab` via `feature-a-bead`?

*Behind the scenes: light mode skipped the `mempalace_status` and
`mempalace_kg_stats` calls but still ran the diary read + recent
decision drawer scan. The reconciliation step matched: `bd ready`
agrees with the latest `loom/decisions` drawer.*

**You:**
```
yes
```

### 2. Engage the recipe

*The `/working-a-bead` router doesn't exist yet — that's the bead
being built. And there's no direct `/feature-a-bead` slash command
(only `bugfix-a-bead` and `research-a-bead` ship as direct commands;
the other four shapes are reached via the router or via Skill-tool
auto-discovery on description match). So you describe the work
naturally and let Claude pick the recipe.*

**You:**
```
let's build the router for loom-1ab
```

**Claude:** *(matches the message against installed skill descriptions;
`feature-a-bead`'s description includes "build <bead-id>" as a
trigger phrase. Invokes `Skill(feature-a-bead)`, which loads
`~/.claude/skills/feature-a-bead/SKILL.md` — which defers to
`bead-lifecycle-shell` for phases A/B/C/D and walks phase A1 first)*

> Engaging `feature-a-bead` for `loom-1ab`. The bead is
> feature-shaped (new behavior: a router) and the locked design lives
> in HAW's "RECIPE SHAPES — ACTIVITY MATRIX" drawer. Phase A1 first.

> Step 1 — searching MemPalace for the router design family.

```
mempalace_search "/working-a-bead router selector dispatch"
mempalace_search "RECIPE SHAPES ACTIVITY MATRIX"
mempalace_kg_query "/working-a-bead"
bd memories router
```

**Claude:**

> Prior art for `loom-1ab: /working-a-bead becomes selector that
> dispatches by bead.type`:
>
> **Family lineage**: this is the v2 router — successor to the v1
> `working-a-bead` slash command (now renamed to `bugfix-a-bead` per
> `loom-lzi`). The design is captured in the MemPalace drawer
> "RECIPE SHAPES — ACTIVITY MATRIX" (`hundred_acre_woods/decisions`,
> 2026-05-02). Frank's 6 locked decisions, paraphrased:
>
> 1. Six recipes total (bug already exists; rename pending — done).
> 2. Shared shell as separate skill (shipped: `bead-lifecycle-shell`).
> 3. Router goes straight to selector pattern, not phased intro.
> 4. Full schema for state file with stage as first-class.
> 5. Default routing by `bead.type`; tasks scored on description
>    keywords.
> 6. Ambiguity case lists candidates with one-line "because" + prompts
>    user to pick (`--recipe=<name>` override).
>
> **Sibling drawer**: `loom/decisions` "V2 SIBLING RECIPES SHIPPED — 4
> IN PARALLEL" (2026-05-03) — confirms which recipes the router
> dispatches to and the variable-middle owned by each.
>
> **bd memories that apply**:
> - `loom-bead-shape-router-decision-2026-05-02` — the router never
>   claims; only inspects + dispatches.
> - `loom-recipe-six-shapes-locked-2026-05-02` — the six recipe
>   names are stable; no further additions in v2.
>
> **Recommended approach**: write the router as a markdown body that
> walks 5 steps: resolve bead → inspect via `bd show` → score against
> the six recipes → dispatch via the `Skill` tool → hand off cleanly.
> Keyword scoring sub-routine handles `type=task` per locked decision
> 5; ambiguity prompt per locked decision 6; epic guard (epics aren't
> work units; refer user to children) per session-2026-05-02 design
> notes.
>
> **Open questions**: none — the design is fully locked.

*That's the prior art. The bead is execution against locked design;
no fresh design judgement is needed beyond translating the
locked-decision list into router prose.*

### 3. Claim and isolate

**You:**
```
proceed
```

**Claude:**

```bash
bd update loom-1ab --claim
```

[bd-claim-research hook fires with additionalContext:
"About to claim loom-1ab. Per the workflow-infrastructure plan:
BEFORE designing the fix, dispatch the bug-family-researcher
subagent... Skip this only if the bug is truly novel territory."]

**[v1.5]** *Loom is in `light` mode, so the bd-claim-research hook
stays silent — no reminder injection. Status line just bumps:*
`WORKFLOW: light | feature:claim | bead:loom-1ab | 1s`.

*You already ran the prior-art search via the recipe step 1, so the
hook would have been redundant anyway.*

```bash
git worktree add .worktrees/loom-1ab -b frank/loom-1ab
cd .worktrees/loom-1ab
```

**Claude:**

> Worktree ready at `.worktrees/loom-1ab` on `frank/loom-1ab` from
> `main` (commit `2dfa53e`). No baseline test run — loom has no
> Python test suite; verification will be `bash` smoke + manual
> dispatch table walk-through at phase B.

### 4. M1 — Brainstorm the design

**Claude:** *(consults `superpowers:brainstorming` lightly because
the design is locked)*

> Brainstorm scope is narrow: the locked decisions specify
> *what* the router does, not *exactly* the prose voice and
> step-by-step structure. Two implementation choices to fix:
>
> 1. **Where keyword-scoring lives**: in-line in the router body
>    (visible to the user reading the file) or as a sub-routine
>    referenced by name. Decision: in-line. The router body is what
>    Claude reads + follows; keeping the scoring rule visible avoids
>    a hidden dispatch table.
> 2. **Tie-break behavior** when two recipes score equally: pick
>    silently? prompt? error? Decision per locked decision 6: prompt
>    with one-line "because" per candidate. Never guess on ties — a
>    silent wrong dispatch is worse than a 5-second prompt.
>
> Both choices flagged minor; surfacing them so we have a record.

**[v1.5]** *Stage update:* `~/.claude/scripts/workflow-state set
stage=designing` *→ status line:* `WORKFLOW: light | feature:designing
| bead:loom-1ab | 0s`.

*Light mode means the brainstorm is shorter than full mode would
demand — no expansion into adjacent design space, no
"alternatives-considered" exhaustive list. The locked drawer + two
fork decisions are enough.*

### 5. M2 — Plan if multi-task

**Claude:**

> M2 (`superpowers:writing-plans` + child beads) only applies when
> the feature is multi-task. `loom-1ab` is one file:
> `commands/working-a-bead.md`. No child beads. Skip M2.

*The recipe explicitly allows skip when single-task. State that
explicitly so future-me reviewing the recipe execution understands
the skip wasn't oversight.*

### 6. M3 — RED that pins desired contract

**Claude:** *(invokes `superpowers:test-driven-development`,
adapted for the prose-heavy primitive)*

> The router has no Python or bash code path to unit-test directly;
> it's a markdown body Claude reads + follows. The "RED" pins the
> *contract* the router must satisfy. Three assertions:
>
> 1. Given a bead with `type=bug`, the router selects
>    `bugfix-a-bead`.
> 2. Given a bead with `type=task` whose description contains
>    "remove" and "deprecated", the router scores `cleanup-a-bead`
>    higher than the others and dispatches to it.
> 3. Given a bead with `type=task` whose description contains both
>    "refactor" and "remove" equally, the router lists the tied
>    candidates with one-line "because" each and prompts the user
>    to pick.
>
> These are the contract. Pre-implementation, the file
> `commands/working-a-bead.md` doesn't exist — every assertion fails
> trivially (RED).

```bash
ls commands/working-a-bead.md
```

```
ls: cannot access 'commands/working-a-bead.md': No such file or directory
```

**[v1.5]** *Stage update:* `~/.claude/scripts/workflow-state set
stage=red`.

*RED confirmed. The contract is pinned; the file is absent.*

*A note on the limitation: this contract is enforced by the live
recipe-execution path, not a programmatic test runner. A future
loom test fixture might fire a real `Skill` dispatch through a
mock harness, but for loom v2 the contract is verified by walking
the dispatch table at phase B (and by the live recipe firing on
the first feature-shaped bead that uses `/working-a-bead`).*

### 7. M4 — Minimal GREEN implementation

**Claude:**

> Writing `commands/working-a-bead.md` minimally — 5 numbered steps
> matching the locked design. Each step has the exact behavior the
> contract assertions need.

```bash
$EDITOR commands/working-a-bead.md
```

*Claude writes the router body. Step 1 resolves the bead-id
argument (or runs `bd ready` if none given). Step 2 inspects via
`bd show <id>`. Step 3 scores against the six recipes — `type=bug`
→ `bugfix-a-bead`, `type=feature` → `feature-a-bead`, `type=epic`
→ epic-guard message (refer to children), `type=task` → keyword
scoring. Step 4 dispatches via `Skill(<recipe>-a-bead)`. Step 5
hands off cleanly.*

```bash
ls commands/working-a-bead.md
```

```
commands/working-a-bead.md
```

**[v1.5]** *Stage update:* `~/.claude/scripts/workflow-state set
stage=green`.

*The file exists. Walking the dispatch table:*

| Test bead | Expected route |
|---|---|
| `type=bug` | bugfix-a-bead ✓ |
| `type=task, desc="remove deprecated"` | cleanup (3 keywords) ✓ |
| `type=task, desc="refactor and remove"` | ambiguity (1 vs 1) ✓ |

*All three contract assertions pass. GREEN.*

### 8. M5 — Negative cases + integration coverage

**Claude:**

> Negative cases for the router are non-trivial — what counts as a
> "wrong dispatch" failure mode? Three categories worth covering:
>
> 1. **Bead doesn't exist**. `bd show <missing-id>` errors; router
>    surfaces the error and stops. Already in step 2 of the body.
> 2. **Bead is closed**. Router warns + asks whether to reopen
>    before proceeding. Already in step 2.
> 3. **`type=epic`**. Epics are containers, not work units. Router
>    refuses to dispatch + tells user to drill into children. Already
>    in step 3 (epic case).
>
> Integration coverage: confirm the `Skill` tool dispatch in step 4
> uses the canonical recipe slug (`bugfix-a-bead`, not `bugfix`).
> Walking the file: yes, all six dispatches use the full
> `<shape>-a-bead` form. Cross-checked against the six SKILL.md
> frontmatter `name:` fields — they match.

```bash
grep -E "Skill\((bugfix|feature|refactor|cleanup|docs|research)-a-bead\)" commands/working-a-bead.md
```

```
commands/working-a-bead.md:Skill(<recipe>-a-bead)
```

*One match — the parameterized form in step 4. The file uses
`<recipe>` as a metavariable, with the six valid values enumerated
in step 3. That's intentional: the body is read + executed by
Claude, not a literal switch statement. Each negative case is
covered in prose.*

**[v1.5]** *Stage update:* `~/.claude/scripts/workflow-state set
stage=integration`.

### 9. Multi-task / per-task review — N/A

*The recipe says steps 8-9 are "(Multi-task only)" / "(Per task)".
This is a single-file feature. Skip.*

### 10. Verification before completion

**Claude:** *(invokes `superpowers:verification-before-completion`)*

> Re-running smoke checks from a clean shell + checking diff scope.

```bash
ls commands/working-a-bead.md
wc -l commands/working-a-bead.md
git diff --stat
```

```
commands/working-a-bead.md
151 commands/working-a-bead.md

 commands/working-a-bead.md | 151 +++++++++++++++++++++++++++++++++++
 1 file changed, 151 insertions(+)
```

```bash
# Walk the dispatch table once more on a fresh read
head -50 commands/working-a-bead.md
```

*Output elided — Claude verifies steps 1–5 exist, the keyword-scoring
sub-routine is in step 3, the ambiguity-case prompt is in step 3,
the epic guard is in step 3, the dispatch is in step 4. All
contract assertions trace to specific lines.*

> Verification: contract pinned at M3 is satisfied by the file as
> written. Diff scope is one new file (151 lines), exactly the
> intended scope. Pass.

**[v1.5]** *Stage update:* `~/.claude/scripts/workflow-state set
stage=verify`.

### 11. Commit

```bash
git add commands/working-a-bead.md
git commit -m "loom-1ab: /working-a-bead router — dispatch by bead.type + heuristics

The router replaces the v1 bugfix-only working-a-bead command. It
inspects the bead via bd show, scores against the six activity
recipes, and dispatches via the Skill tool. type=bug → bugfix;
type=feature → feature; type=epic → guard message (refer to
children); type=task → keyword scoring across refactor, cleanup,
docs, research with bugfix as fallback. Ties surface a numbered
candidate list with one-line because per recipe and prompt the user
to pick or pass --recipe=<name> override.

Design source: 'RECIPE SHAPES — ACTIVITY MATRIX' drawer
(hundred_acre_woods/decisions, 2026-05-02), Frank's 6 locked
decisions. Sibling drawer: 'V2 SIBLING RECIPES SHIPPED'
(loom/decisions, 2026-05-03).

Verification: dispatch table walked manually for type=bug,
type=task with cleanup keywords, type=task with refactor+cleanup
tie. End-to-end smoke through a real Skill dispatch deferred to
next session.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

**[v1.5]** *Stage update:* `~/.claude/scripts/workflow-state set
stage=commit`.

### 12. Finish branch

**Claude:** *(invokes `superpowers:finishing-a-development-branch`)*

> Implementation complete, contract verified at the dispatch-table
> level. Four options:
>
> 1. Merge locally to main + push
> 2. Push branch + create PR
> 3. Keep branch open for further work
> 4. Discard
>
> Recommend option 1 — single-file feature, the change is contained
> within `commands/working-a-bead.md`, no reviewer needed beyond
> what's already verified. Proceed?

**You:**
```
1
```

```bash
cd ~/repos/loom
git merge --no-ff frank/loom-1ab -m "Merge branch 'frank/loom-1ab': /working-a-bead router"
ls commands/working-a-bead.md
```

```
commands/working-a-bead.md
```

*Clean merge. The file exists on `main`.*

### 13. Preflight + close + push

**You:**
```
/wrap-up
```

**Claude:** *(invokes the `/wrap-up` skill)*

> Running preflight + close + capture sequence.

```bash
bd preflight
```

```
✓ lint passed
✓ no stale beads (>30 days)
✓ no orphan dependencies
```

*Dispatching `drawer-author` and `kg-relationship-extractor`
subagents in parallel.*

**Claude:** *(when subagents return)*

> **Drawer draft** (for `loom/decisions`):
>
> Title: "ROUTER /working-a-bead SHIPPED — loom-1ab"
> Body summarizes: design source (locked drawer), 5-step structure,
> dispatch contract, deferred end-to-end smoke, commit ref.
>
> **KG triples drafted**:
> - `loom-1ab → implements → /working-a-bead-router`
> - `/working-a-bead-router → dispatches-to → bugfix-a-bead, feature-a-bead, refactor-a-bead, research-a-bead, cleanup-a-bead, docs-a-bead`
> - `loom-1ab → succeeds → working-a-bead-v1`
>
> Approve?

**You:**
```
yes
```

```bash
# duplicate-check before drawer write
mempalace_check_duplicate "ROUTER /working-a-bead SHIPPED — loom-1ab"
```

```
no near-duplicate found
```

```bash
mempalace_add_drawer wing=loom room=decisions ...
mempalace_kg_add subject=loom-1ab ...
mempalace_diary_write agent=claude-opus ...

bd close loom-1ab --reason="Router shipped at commands/working-a-bead.md. Dispatches by bead.type with keyword scoring for tasks, ambiguity prompt on ties, --recipe override, epic guard. End-to-end smoke test deferred to next session. commit da939e6."

bd dolt push
git push
git status
```

```
On branch main
Your branch is up to date with 'origin/main'.
nothing to commit, working tree clean
```

**[v1.5]** *Stage update:* `~/.claude/scripts/workflow-state set
stage=close`.

*Bead closed. Working tree clean. Push succeeded. Status line:*
`WORKFLOW: light | idle | 0s`.

### 14. Continue or stop

**Claude:**

> Closing `loom-1ab` unblocked `loom-qj3` (manual + walkthrough
> updates). That's the last open child of epic `loom-0y6` — closing
> it ends the v2 epic.
>
> Recommended next step: `/working-a-bead loom-qj3` (the router we
> just shipped — meta but real). The bead is docs-shaped, so the
> router will dispatch to `docs-a-bead`.
>
> Or stop here for the day. The session diary already saved a final
> checkpoint.

---

## What you noticed during the walkthrough

### Things the primitives did automatically (no remembering required)

- **Cold-start** primed beads + MemPalace + diary, even in `light`
  mode — the abbreviated startup is shorter, not absent.
- **Hook on `bd update --claim`** stayed silent in `light` mode (no
  reminder injection); contrast with `full` mode where the
  bug-family-researcher reminder fires.
- **Recipe routed via shape** — the feature-a-bead recipe ran the
  feature-specific middle (M1 brainstorm → M2 plan-skip → M3 RED
  contract → M4 GREEN → M5 negative cases) instead of the bugfix
  middle (debug → RED symptom → GREEN → bug-class → enshrined-sweep).
  Same shared shell on either side.
- **Subagent dispatches** kept main context clean — drawer-author +
  kg-relationship-extractor returned drafts you approved before
  filing.
- **Stop hook** fires the AUTO-SAVE checkpoint at session end.

### Things you did manually

- Decided which bead to work (recommendation came from
  session-startup, but the choice is yours).
- Pivoted from `/working-a-bead` to `/feature-a-bead` when the
  router itself was the bead being built (bootstrap awareness).
- Approved the drawer + KG triples after subagents drafted them.
- Chose the merge option in `finishing-a-development-branch`.

### Things the recipe enforced

- M1 brainstorm before M3 implementation, even with locked design
  (the brainstorm was short — minutes, not hours — but it surfaced
  the in-line vs sub-routine choice).
- M3 RED before M4 GREEN — the contract was pinned (3 assertions)
  before the file was written.
- M5 negative cases before commit — the bead-doesn't-exist /
  bead-closed / type=epic cases were explicitly walked.
- Verification (B1) confirmed diff scope matched intended scope
  before commit.
- Drawer + KG capture before close (via `/wrap-up`).
- Push + status check before declaring session done.

---

## Variations

### **[v1.5]** If your project has `mode: full`

Same recipe, more ceremony:
- Full M1 brainstorm — expand into adjacent design space, surface
  alternatives, document why each was rejected.
- Full M3 contract — for projects with a real test suite, write
  pytest/bats/etc. tests that fail before the implementation lands.
- Full M5 — exhaustive negative-case enumeration; if any case is
  unhandled in code, file a follow-up bead before claiming done.
- bd-claim-research hook fires its reminder; bd-close-capture hook
  blocks the close until drawer + KG are filed.

### **[v1.5]** If your project has `mode: off`

Recipe disabled. The shell refuses, the hooks stay silent, the
status line is empty. Drive the bead manually. The bd CLI still
works — you just lose the recipe and the capture enforcement.

Quick toggle for a single session:

```bash
CLAUDE_WORKFLOW_OFF=1 claude
```

### If the feature were multi-task

M2 fires non-trivially. Run `superpowers:writing-plans` to draft a
plan, then `beadpowers:create-beads` to spawn child beads. Each child
gets its own `/working-a-bead` invocation (which routes by *that*
child's shape — could be feature, refactor, etc.). The parent bead
becomes a coordinator; close it last with the `--reason="all
children shipped: <list>"` close note.

### If the contract had no test surface

For prose-heavy primitives (slash commands, agent definitions,
manual sections), the contract is verified by walking a dispatch
table or smoke-testing the live behavior — not by a programmatic
test runner. State this explicitly at M3 so the recipe execution
record makes the limit visible. A future loom-side test harness
might invert this; today it's a known gap.

### If the design wasn't already locked

M1 expands. Run `superpowers:brainstorming` (or
`beadpowers:brainstorming`) to converge on the contract. Capture
the brainstorm output as a MemPalace drawer in
`<project>/decisions` — the drawer becomes the source-of-truth that
M3 pins against. If the brainstorm produces multiple alternatives,
prototype each in M3 (one RED test per alternative); the surviving
contract is the one whose RED→GREEN cycle ships cleanest.

### If something went wrong

Three failure modes worth watching for:

1. **M3 RED pinned implementation, not contract.** Symptom: M4 GREEN
   passes the test but the feature still feels wrong. Diagnosis: the
   test pinned the *wrong* level. Rewrite the RED to assert on the
   observable surface (return value, output shape, log message), not
   on the internal call sequence. This is the #1 way feature TDD
   turns into theater.
2. **M2 plan understated the work.** Symptom: M4 GREEN balloons into
   multiple files; you're 4× over the bead's stated scope. Pause,
   re-run M2 properly, file child beads, claim one of them, close
   the parent as superseded.
3. **Locked design conflicts with new constraint.** Symptom: M3 RED
   can't be written cleanly because the locked design assumes
   something that's no longer true. File a research bead
   (`research-a-bead`) to revisit the design; close the feature
   bead with `--reason="superseded: design needs re-locking, see
   loom-XXX"`. Don't ship a feature that fights the design.

---

## What to expect over the first few sessions using this

The feature recipe will feel different from the bugfix recipe in
two specific ways:

- **No symptom to anchor on.** Bugfix recipe's M1 starts from a
  failing transcript or a reproducer; feature recipe's M1 starts
  from a contract you have to *invent*. The brainstorm step matters
  more than it does in bugfix — under-thinking the design produces
  features that work but are wrong.
- **RED feels weird at first.** Writing a test that fails because
  the feature doesn't exist yet seems redundant ("of course it
  doesn't exist — I haven't written it yet"). Resist the
  redundancy reading. The RED forces you to articulate the contract
  *before* you have implementation pressure pulling on it. That's
  the value.

If the recipe feels heavy on a small feature, drop into `light`
mode for that project (or pass `CLAUDE_WORKFLOW_OFF=1` for a single
session). The recipe scales down better than it scales up.

---

## Where to update what (quick recap)

If during a session you notice a friction point or want to tweak
behavior:

| Friction | Edit |
|---|---|
| The feature-shaped variable middle is wrong | `~/.claude/skills/feature-a-bead/SKILL.md` |
| Cross-activity lifecycle phase wrong | `~/.claude/skills/bead-lifecycle-shell/SKILL.md` |
| Router scoring picked the wrong recipe | `~/.claude/commands/working-a-bead.md` |
| Cold-start ritual missing something | `~/.claude/skills/session-startup/SKILL.md` |
| Subagent prompt unclear | `~/.claude/agents/<name>.md` |
| Hook fires wrong / too aggressively | `~/.claude/hooks/<name>.sh` |
| Permission keeps prompting | `~/.claude/settings.json` `permissions.allow` |
| Project convention I keep forgetting | project `CLAUDE.md` (or `.claude/rules/<area>.md` if path-scoped) |
| Decision worth capturing | `mempalace_add_drawer` |
| One-liner tribal fact | `bd remember "<insight>"` |
| Onboarding a new project | `/audit-project` (manual-only) |

The reference manual (`docs/manual.md`) section 16 has the full
matrix.
