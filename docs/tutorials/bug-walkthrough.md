# Claude Workflow Walkthrough

> A narrative session walkthrough showing what a working session looks
> like end-to-end. Companion to the [Reference quadrant](../reference/index.md)
> — this file shows the workflow in motion using a real bead from the
> HAW project (`hundred-acre-woods-80v`: remove the diagnostic
> fingerprint logging from poe_server + server).
>
> Format: "**You:**" lines are what you type; "**Claude:**" lines are
> the assistant's response (sometimes summarized, sometimes verbatim);
> indented italic blocks are commentary on what's happening behind the
> scenes. Hook output appears in `[brackets]` when relevant.
>
> Honesty caveat: the recipe was shipped 2026-05-02 and verified at the
> primitive level (skill files exist, hooks smoke-test correctly,
> commands and agents are written). Subagent dispatch — the
> test-author → implementer pipeline this walkthrough shows — is now
> observed reality, not a design hope. A few peripheral details
> (settings.json hot-reload timing) still vary by Claude Code version;
> where this walkthrough is aspirational rather than observed, a note
> flags it.
>
> **Updated 2026-05-03 for v1.5** — workflow modes (full/light/off),
> the per-project state file, the SessionStart onboarding hook, and
> the status line. v1.5-specific moments are tagged with **[v1.5]**.
>
> **Updated 2026-06-07 for the dispatched middle** — the RED→GREEN
> core now runs through `/dispatch-middle` as a test-author →
> implementer pipeline of two independent subagents (epic loom-5m94).
> Central writes nothing in the middle. §5 and §6 below show the split.

---

## The session

You sit down to fix `hundred-acre-woods-80v` — a P3 cleanup bead that's
been sitting in the queue since the 13p.3.11 deploy day. The diagnostic
fingerprint logging in `engine/backends/poe_server.py` and `server.py`
was added to debug an "Invalid API key" mystery; that mystery was
solved (the credential flows correctly via `api_key=` of
`fp.stream_request`), and the logging is now noise.

### 0. Open terminal, launch Claude Code

```
$ cd ~/Working/hundred-acre-woods
$ claude
```

*The shell launches Claude Code. You see the welcome message and the
prompt cursor blinks.*

**[v1.5]** *Status line at the bottom of the TUI now reads:*
`WORKFLOW: full | idle | 12h` *(populated from
`/home/frank/Working/hundred-acre-woods/.claude/workflow-state.json`,
mode resolved from `workflow.json`).*

**[v1.5]** *If this were the first cold-start in a beads workspace
that has no `.claude/workflow.json`, the SessionStart hook
`workflow-mode-onboarding.sh` would fire and inject an
`additionalContext` block — Claude would then ask you to pick `full`,
`light`, or `off` before doing anything else, and write the answer to
`workflow.json`. Once written, future sessions skip the prompt
(ask-once-and-remember). HAW already has `workflow.json` set to
`full`, so the prompt doesn't fire here.*

### 1. Cold start — session prime

**You:**
```
/clear
```

*The `/clear` triggers a SessionStart event. Three plugin hooks fire
automatically and silently: beads' hook runs `bd prime`; mempalace's
hook acknowledges the last stop checkpoint; superpowers + beadpowers
load their `using-*` meta-skills.*

*The conversation buffer clears. You see the new session header.*

**You:**
```
let's pick up where we left off
```

**Claude:** *(invokes `/session-startup` because it matches the
trigger phrase)*

> Cold-start primed. State as of 2026-05-02:
>
> **bd ready** leads with two P0 beads:
> - `ypa` (Reset DB password leaked in chat 2026-05-02)
> - `ui1` (Rotate Poe sk-poe API key)
>
> Both are dashboard actions you do in DO Console + poe.com — not
> Claude work. After those, P2/P3 cleanup beads from the deploy-day
> follow-up: `0bu`, `bsc`, `3c3`, `80v`, `b5k`.
>
> **In-progress:** none.
>
> **MemPalace:** 5 drawers from the 2026-05-02 session document the
> three-bug fix arc + the workflow-infrastructure plan. Most recent
> diary entry is "workflow-infra-COMPLETE".
>
> **bd stale** shows nothing in flight from prior sessions.
>
> **Recommendation:** rotate the credentials yourself first (`ypa` +
> `ui1`), then we tackle `80v` (remove diagnostic fingerprint logging)
> as the first real test of the new workflow infrastructure. `80v` is
> code-shaped, has clear scope, and will exercise the
> bug-family-researcher subagent + the bd-claim-research hook.
>
> Proceed with `80v`?

*Behind the scenes: the session-startup skill ran `bd stats`, `bd ready
-n 10`, `bd list --status=in_progress`, `mempalace_status`,
`mempalace_kg_stats`, `mempalace_search` for session-close drawers,
`mempalace_diary_read("claude-opus", 3)`, and `bd memories haw`. It
reconciled bead state vs MemPalace state and didn't find any divergence
to flag.*

**You:**
```
yes, 80v
```

**[v1.5]** *Status line still reads* `WORKFLOW: full | idle | 0s`
*— no bead claimed yet, so activity/stage stay idle.*

### 2. Engage the recipe

**You:**
```
/bugfix-a-bead 80v
```

*The slash command fires. Because it has `disable-model-invocation:
true`, it only runs on explicit invocation — the model can't
auto-trigger it. The command body says "Invoke the bugfix-a-bead
skill and follow it exactly as presented." (Once the
`/working-a-bead` router lands, you'll be able to type that and let
it pick the matching activity recipe by `bead.type`.)*

**Claude:** *(loads `~/.claude/skills/bugfix-a-bead/SKILL.md` —
which defers to `bead-lifecycle-shell` for phases A/B/C/D and walks
phase A1 first)*

> Step 1 — searching MemPalace for the `80v` bug family. Dispatching
> `bug-family-researcher` subagent with bead title + symptom.

*The subagent dispatches with these inputs. Latency 5-15s. While it
runs, your main context stays clean.*

**Claude:** *(returns when the subagent completes)*

> Prior art for `80v: Remove 13p.3.11 diagnostic fingerprint logging
> from poe_server + server`:
>
> **Family lineage**: this is a cleanup bead from the 13p.3.11
> deploy-day arc. The fingerprint logging was added in commit
> `c1f8812` (Bug 7b diagnostic) to confirm `POE_ACCESS_KEY` env var
> matched `request.access_key` matched `request.api_key`. All three
> were verified identical (sha256 prefix `a6d9970746`, len=32). The
> root cause turned out to be undeclared `server_bot_dependencies`
> + wrong calling pattern — see drawer "DEPLOY DAY — MASTER RECORD
> (2026-05-02)" in hundred_acre_woods/session-notes.
>
> **Relevant decision drawers:**
> - "DEPLOY DAY — MASTER RECORD (2026-05-02)" — names this logging
>   as Bug 7b instrumentation that's fulfilled its purpose.
> - "WORKFLOW INFRASTRUCTURE PLAN" notes this kind of cleanup as
>   exemplar deferred-polish work.
>
> **KG facts:**
> - `deploy_day_2026-05-02 → surfaced_bugs → t92+0qw+bi2_now_all_closed`
>   (this bead is in the same cleanup batch but P3).
>
> **bd memories that apply:** none directly; the credential discipline
> is captured in CLAUDE.md and architecture spec.
>
> **Recommended approach:** straight removal. The fingerprint helper
> + the log line in `_stream_chunks` (poe_server.py:36-50, 206-212)
> + any equivalent server.py instrumentation. No defensive coercion
> needed; this is purely additive cleanup.
>
> **Prior fixes that pattern-match:** `bi2` (cosmetic separator
> removal) and `b5k` (drop stale env-var ref) are sibling cleanups.
> Both were straightforward removals + test updates.
>
> **Open questions:** none.

*That's the prior art. You can tell the bead is straightforward; the
recommended approach matches your mental model.*

### 3. Claim and isolate

**You:**
```
proceed
```

**Claude:** *(runs the claim — and the bd-claim-research hook fires)*

```bash
bd update hundred-acre-woods-80v --claim
```

[bd-claim-research hook fires with additionalContext:
"About to claim hundred-acre-woods-80v. Per the workflow-infrastructure
plan: BEFORE designing the fix, dispatch the bug-family-researcher
subagent... Skip this only if the bug is truly novel territory."]

*You already ran the researcher in step 1. The hook reminder is
redundant in this case — Claude notes that and proceeds.*

**Claude:**

> Claim succeeded. Creating worktree per recipe step 2.

**[v1.5]** *The bd-claim-research hook side-effect updated the state
file: `activity=task` (or `bug` if the bead Type were `bug`),
`bead=hundred-acre-woods-80v`, `stage=claim`. Status line:*
`WORKFLOW: full | task:claim | bead:80v | 1s`.

```bash
git worktree add .worktrees/80v -b frank/80v
cd .worktrees/80v
python3 -m pytest tests/test_poe_server_backend.py -q
```

**Claude:**

> Worktree ready at `.worktrees/80v` on `frank/80v` from `main` (commit
> `c5fa8dc`). Baseline: 16 tests pass in `test_poe_server_backend.py`,
> the file most affected by the change.

### 4. Phase 1 — verify the bug's read

**Claude:** *(invokes `superpowers:systematic-debugging`)*

> Reading actual code paths the bead names. Let me look at
> `engine/backends/poe_server.py` lines 36-50 (the
> `_credential_fingerprint` helper) and lines 206-212 (the log
> emission), plus any equivalent in `server.py`.

*Claude reads the files, summarizes what each function does, and
confirms the cleanup is bounded.*

**Claude:**

> Confirmed scope. Three sites to remove:
>
> 1. `engine/backends/poe_server.py:36-50` — the
>    `_credential_fingerprint` helper function definition.
> 2. `engine/backends/poe_server.py:206-212` — the
>    `logger.info` call inside `_stream_chunks` that emits the
>    fingerprints on every outbound call.
> 3. `engine/backends/poe_server.py:23` — `import hashlib` (only
>    used by the helper; stranded after removal).
>
> No equivalent instrumentation in `server.py` to remove.
>
> The helper is referenced only by the one log line. Tests in
> `test_poe_server_backend.py` don't assert on fingerprint output, so
> removal shouldn't surface enshrined-test failures.

### 4b. M2 — bead-assumption audit

**Claude:** *(sets stage `assumption-audit`)*

```bash
~/.claude/scripts/workflow-state set stage=assumption-audit
```

> Before writing the RED test, comparing my M1 diagnosis against the
> bead's stated cause. The bead says "remove 13p.3.11 diagnostic
> fingerprint logging from poe_server + server." My read found the
> instrumentation lives entirely in `poe_server.py` (helper + log
> line + stranded import); there is no equivalent in `server.py`. The
> "+ server" in the title is stale — it reflected the filing-day
> guess, not the actual footprint.

*Bug fixes drift between filing date and claim date; the bead's framing
can quietly go wrong. The recipe makes Claude reconcile the two before
the RED test pins anything. Here the divergence is minor (a scope
overstatement, not a wrong root cause), so Claude corrects the bead
description rather than leaving future sessions to trust a stale
"+ server".*

```bash
bd update hundred-acre-woods-80v --description "Remove 13p.3.11 diagnostic fingerprint logging from poe_server (instrumentation confirmed poe_server-only; no server.py equivalent — corrected at claim per M2 audit)."
```

> Description corrected. Proceeding to the RED test.

### 5. TDD — RED first (the dispatched TEST-AUTHOR)

*Here is the structural change from the old single-actor walkthrough.
Central does not write this test. It invokes `/dispatch-middle`, which
spins up the shared worktree and dispatches a **test-author**
subagent. The brief carries only the contract — the verbatim symptom
the test must pin (here: "`_credential_fingerprint` is diagnostic
instrumentation that must be GONE") — plus the interface under test.
It does NOT carry central's reasoning or session history.*

**Claude:** *(dispatches the test-author via `/dispatch-middle`)*

> Dispatching the test-author into `frank/80v`. Its contract: the
> `_credential_fingerprint` helper from 13p.3.11 must no longer exist
> as a module attribute, and no fingerprint-shaped log line may remain
> in the outbound path. It will write the RED test, commit it, and
> return the failure output. It will NOT implement the removal.

*Inside the worktree, the test-author sets stage `tdd-red`, invokes
`superpowers:test-driven-development`, and writes:*

```python
def test_credential_fingerprint_helper_removed():
    """80v: the _credential_fingerprint helper was diagnostic
    instrumentation added during 13p.3.11 to debug an 'Invalid API
    key' mystery. The mystery was solved (server_bot_dependencies
    + fp.stream_request via api_key=). The helper has fulfilled
    its purpose; removal eliminates per-call log noise."""
    from engine.backends import poe_server as ps
    assert not hasattr(ps, "_credential_fingerprint"), (
        "diagnostic helper from 13p.3.11 should be removed"
    )
```

```bash
python3 -m pytest tests/test_poe_server_backend.py::test_credential_fingerprint_helper_removed -v
```

```
FAILED tests/test_poe_server_backend.py::test_credential_fingerprint_helper_removed
AssertionError: diagnostic helper from 13p.3.11 should be removed
```

*RED confirmed. The test-author commits ONLY the test and returns the
verbatim failure output to central as evidence that RED preceded
GREEN:*

```bash
git add tests/test_poe_server_backend.py
git commit -m "80v: RED — _credential_fingerprint helper must be removed"
```

**Claude:** *(test-author's return, relayed by central)*

> Test-author returned. RED test committed at
> `tests/test_poe_server_backend.py::test_credential_fingerprint_helper_removed`.
> Failure output (verbatim): `AssertionError: diagnostic helper from
> 13p.3.11 should be removed`. No implementation written.

**[v1.5]** *Status line:* `WORKFLOW: full | task:tdd-red | bead:80v | 0s`.

### 6. GREEN — minimal fix (the SEPARATE IMPLEMENTER)

*Now the second half of the pipeline. Central dispatches a **different
agent** — the implementer — into the same worktree, so the committed
RED test is already on disk. The implementer's brief carries the RED
test file path and the code area. It does **not** carry the
test-author's reasoning, the contract dialogue, or any explanation of
why the test is shaped the way it is. The implementer inherits the
test as an **artifact** and treats it as the spec.*

*This is the anti-tautology guarantee made mechanical. When one agent
writes both the test and the fix, the test tends to assert whatever
the fix already does — the RED→GREEN cycle verifies nothing. Two
independent agents, sharing only the committed file, cannot collude
that way: the implementer satisfies a public artifact, not a private
intent.*

**Claude:** *(dispatches the implementer via the same
`/dispatch-middle` pipeline)*

> Dispatching the implementer into the same worktree. Its spec is the
> committed RED test at
> `tests/test_poe_server_backend.py::test_credential_fingerprint_helper_removed`.
> Code area: `engine/backends/poe_server.py`. It will make the minimal
> change to turn the test GREEN. It must NOT modify the test — if the
> test looks wrong, it STOPS and reports to me rather than weakening
> it.

*Inside the worktree, the implementer sets stage `tdd-green`, reads
the RED test, and makes three edits: removes the function (lines
36-50), removes the log call (lines 206-212), removes
`import hashlib` (line 23).*

```bash
python3 -m pytest tests/test_poe_server_backend.py::test_credential_fingerprint_helper_removed -v
```

```
PASSED tests/test_poe_server_backend.py::test_credential_fingerprint_helper_removed
```

*GREEN. The implementer commits ONLY the implementation and returns
its pass count + commit SHA:*

```bash
git add engine/backends/poe_server.py
git commit -m "80v: GREEN — remove _credential_fingerprint helper + log emission"
```

**[v1.5]** *Stage update written inside the worktree:*
`~/.claude/scripts/workflow-state set stage=tdd-green` *→ status line:*
`WORKFLOW: full | task:tdd-green | bead:80v | 0s`.

### 7. Bug-class coverage

*Bug-class coverage extends the test surface, so it stays in the
pipeline. Central keeps the implementer on it here (the class test is
tightly coupled to the instance removal); for a class test that is a
genuinely fresh contract worth independent authoring, central would
hand back to a follow-on test-author instead.*

**Claude:** *(implementer, stage `bug-class`)*

```bash
~/.claude/scripts/workflow-state set stage=bug-class
```

> The bug class is "diagnostic instrumentation outliving its
> purpose." The instance test pins this specific helper. The class
> test should pin a broader principle — no module-level diagnostic
> functions named `_<purpose>_fingerprint` should accumulate without
> deletion. That's a bit speculative for a P3 cleanup; instead I'll
> add a test that asserts the log emission specifically is gone:

```python
def test_outbound_call_does_not_log_credential_fingerprints(caplog):
    """80v class: the credential fingerprint log line was specific to
    13p.3.11 debugging. Future regressions where someone re-adds
    diagnostic logging containing 'sha256' or 'fingerprint' in the
    outbound call path should fail this test."""
    # ... test setup that exercises an outbound call ...
    fingerprint_lines = [
        r for r in caplog.records
        if "sha256" in r.getMessage() or "fingerprint" in r.getMessage()
    ]
    assert not fingerprint_lines, (
        f"outbound call emitted fingerprint-shaped log: {fingerprint_lines}"
    )
```

*This is the bug-class layer. Future debugging sessions might add new
fingerprint logs; this test catches them so cleanup is reflexive.*

### 8. Full suite — enshrined-test sweep

**Claude:** *(implementer, stage `enshrined-sweep`)*

```bash
~/.claude/scripts/workflow-state set stage=enshrined-sweep
python3 -m pytest -q
```

```
2167 passed, 16 skipped in 11.42s
```

*No enshrined tests surfaced — clean removal. (Compare 0qw which
surfaced 14 such tests; each was a test that had locked in the buggy
contract and had to be updated, not worked around. This bead is
genuinely simpler.) With the sweep clean, the implementer hands the
pipeline's summary back to central: RED output, GREEN counts, both
commit SHAs. Central now owns verify + merge + close + capture — it
does not re-do the middle.*

**[v1.5]** *Stage update:* `~/.claude/scripts/workflow-state set
stage=verify` *→ status line:* `WORKFLOW: full | task:verify | bead:80v | 0s`.

### 9. Multi-task / per-task review — N/A

*The recipe says steps 8 + 9 are "(Multi-task only)" and "(Per task)".
This is a single small task. Skip.*

### 10. Verification before completion

**Claude:** *(invokes `superpowers:verification-before-completion`)*

> Re-running from a clean shell + checking diff scope.

```bash
python3 -m pytest -q 2>&1 | tail -3
git diff --stat
```

```
2167 passed, 16 skipped, 0 failed in 11.18s

 engine/backends/poe_server.py | 18 ------------------
 tests/test_poe_server_backend.py | 30 ++++++++++++++++++++++++++++++
 2 files changed, 30 insertions(+), 18 deletions(-)
```

*Pass count up by 2 (the two new tests). Scope: only the two intended
files. Verification passes.*

### 11. Commit — already split across two agents

*The pipeline already produced two commits in the worktree: the
test-author's RED commit and the implementer's GREEN commit. Central
does not re-commit the work — it reviews the combined log and, for a
clean bug-fix lineage, leaves the two commits as-is (the RED-before-
GREEN ordering is exactly the evidence trail the recipe wants
preserved).*

```bash
git log --oneline frank/80v -2
```

```
b3c1f09 80v: GREEN — remove _credential_fingerprint helper + log emission
a17e442 80v: RED — _credential_fingerprint helper must be removed
```

*Both agents used the loom co-author trailer on their commits:*

```
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
```

*If central wanted a single squashed commit with a full provenance
body, it would squash the two into one before merge — but a legible
RED→GREEN pair is usually worth keeping. The body of the GREEN commit
already names the symptom, root cause, fix, and family lineage (the
13p.3.11 deploy-day arc, fix commits 49645df + de50764 + a3483f2).*

### 12. Finish branch

**Claude:** *(invokes `superpowers:finishing-a-development-branch`)*

> Implementation complete, tests pass. Four options:
>
> 1. Merge locally to main + push
> 2. Push branch + create PR
> 3. Keep branch open for further work
> 4. Discard
>
> Recommend option 1 — this is a single-bead cleanup, no review
> needed beyond what's already committed. Proceed?

**You:**
```
1
```

```bash
cd ~/Working/hundred-acre-woods
git merge --no-ff frank/80v -m "Merge branch 'frank/80v': remove 13p.3.11 diagnostic fingerprint logging"
python3 -m pytest -q 2>&1 | tail -2
```

```
2167 passed, 16 skipped in 12.01s
```

*Clean merge, full suite green on the merged state.*

### 13. Preflight + close + push

**You:**
```
/wrap-up
```

**Claude:** *(loads `~/.claude/commands/wrap-up.md`)*

> Wrapping up `hundred-acre-woods-80v`. Step 1: preflight checks.

```bash
bd preflight
```

*(output: passes; no stale, no orphans, lint clean)*

```bash
python3 -m pytest -q 2>&1 | tail -3
git status
```

*(output: 2167 passed, working tree clean)*

> Preflight clean. Step 3: dispatching `drawer-author` and
> `kg-relationship-extractor` subagents in parallel.

*Two subagents fire simultaneously. Each reads `bd show 80v`,
`git show <sha>` for the merge + the original commit, and the prior
drawers referenced. Both return in 5-15s.*

**Claude:** *(presents drawer-author output)*

> Drafted decision drawer body for review:
>
> ```
> 80v — REMOVE 13P.3.11 DIAGNOSTIC FINGERPRINT LOGGING
>
> DECISION (locked 2026-05-02): the _credential_fingerprint helper
> + per-outbound-call log emission, added during 13p.3.11 deploy
> day to debug an 'Invalid API key' mystery, are removed in full.
> The mystery resolved to undeclared server_bot_dependencies + wrong
> calling pattern (fix landed in commits 49645df + de50764 +
> a3483f2). The instrumentation has fulfilled its purpose; removal
> eliminates per-call log noise.
>
> ROOT CAUSE (of the original instrumentation, not of a bug):
> Bug 7b in the deploy-day debugging arc needed to confirm whether
> POE_ACCESS_KEY env var, request.access_key, and request.api_key
> all carried the same value before pursuing other hypotheses. The
> _credential_fingerprint helper (sha256 prefix + length, no actual
> material exposed) made the comparison legible in deploy logs.
>
> PRIOR ART: cleanup batch from 13p.3.11 deploy day. Sibling beads:
> bi2 (cosmetic --- separator), b5k (stale env-var ref). All three
> are straightforward removals.
>
> WHAT SHIPPED:
> - engine/backends/poe_server.py: removed lines 36-50 (helper),
>   206-212 (log emission), 23 (import hashlib).
> - tests/test_poe_server_backend.py: +2 tests (instance + class
>   coverage per Frank's deploy-day rule).
>
> BUG-CLASS COVERAGE:
> - Instance: test_credential_fingerprint_helper_removed.
> - Class: test_outbound_call_does_not_log_credential_fingerprints
>   — pins that no future diagnostic logging containing 'sha256'
>   or 'fingerprint' accumulates in the outbound path without
>   review.
>
> VERIFICATION at decision time: 2167 passed, 16 skipped, 0 failed
> on commit <sha>.
>
> OPEN: none.
> ```
>
> Approve?

**You:**
```
approve
```

**Claude:** *(presents kg-relationship-extractor output)*

> Proposed KG triples (3 of allowed 5):
>
> 1. `80v` → `closed_at` → `2026-05-02_commit_<sha>`
>    valid_from: 2026-05-02
>    *Why*: every closed bead gets a closed_at triple linking to canonical commit.
>
> 2. `80v` → `is_sibling_of` → `bi2`
>    valid_from: 2026-05-02
>    *Why*: same deploy-day cleanup batch shape (straightforward removal of stale instrumentation).
>
> 3. `13p.3.11_deploy_day_instrumentation` → `removed_in` → `80v`
>    valid_from: 2026-05-02
>    *Why*: future searches for the deploy-day instrumentation
>    family find this removal.
>
> Approve all three?

**You:**
```
approve
```

**Claude:**

```python
# duplicate-check before drawer write
mempalace_check_duplicate(
  content="80v — REMOVE 13P.3.11 ...",
  threshold=0.9
)
# returns: no near-duplicate found

mempalace_add_drawer(
  wing="hundred_acre_woods",
  room="decisions",
  content="80v — REMOVE 13P.3.11 ...",
  added_by="claude-opus",
  source_file="2026-05-02 80v fingerprint logging removal"
)

mempalace_kg_add(subject="80v", predicate="closed_at",
                 object="2026-05-02_commit_<sha>", valid_from="2026-05-02")
mempalace_kg_add(subject="80v", predicate="is_sibling_of",
                 object="bi2", valid_from="2026-05-02")
mempalace_kg_add(subject="13p.3.11_deploy_day_instrumentation",
                 predicate="removed_in", object="80v",
                 valid_from="2026-05-02")

mempalace_diary_write(
  agent_name="claude-opus",
  topic="80v",
  entry="SESSION:2026-05-02|80v.deploy-day.fingerprint.logging.REMOVED|..."
)
```

*All filed. Now close + push.*

```bash
bd close hundred-acre-woods-80v --reason="Removed 13p.3.11 diagnostic fingerprint logging. Mystery (Bug 7b) resolved long ago via 49645df+de50764+a3483f2; helper was noise on every outbound call. Drawer + KG triples filed."
```

```
[bd-close-capture hook] 80v: 3/5 matchers (✓✓✓✗✗) — allowing.
```

*The close-capture hook is **evidence-aware** (loom-8vb). It checks
five matchers — drawer in the bead's wing, KG triple, diary entry, bd
memory, substantive close reason — and ALLOWS the close when ANY ONE
passes. Here three matched (the drawer, the KG triples, and the diary
entry you just filed), so the hook prints the `N/5 matchers` line and
lets the close through. It blocks only when **zero** evidence exists —
the case where someone tries to close a bead with nothing captured.*

**Claude:**

> Capture is done (3/5 matchers), so the hook allowed the close. No
> bypass needed.

```bash
bd dolt push
git push
git status
```

```
On branch main
Your branch is up to date with 'origin/main'.
nothing to commit, working tree clean
```

*If you were closing a wave of beads in a batch with no per-bead
drawer yet, you'd either add lineage to `--reason` (a substantive
reason ≥200 chars with a commit SHA or drawer ID satisfies matcher 5)
or, in the rare genuine case, bypass with `BD_CLOSE_FORCE=1 bd close
<id>` — the auditable env-var bypass, recorded in workflow state. The
old `--force` flag still works, but `BD_CLOSE_FORCE=1` is the headline
bypass.*

> 80v shipped. Want to clean up the worktree?

```bash
git worktree remove .worktrees/80v
git branch -d frank/80v
```

> Worktree removed. Anything else this session?

### 14. Continue or stop

**You:**
```
that's enough for tonight
```

**Claude:** *(notes the session is wrapping up)*

> Session summary: shipped `80v` (cleanup of 13p.3.11 diagnostic
> fingerprint logging) on commit `<sha>`. 2167 passed (+2 new
> tests). Drawer + 3 KG triples + diary entry filed.
>
> Remaining ready queue: P0 security beads `ypa` + `ui1` (your
> dashboard actions), then P2 `0bu`/`bsc`/`3c3`, then P3 `b5k`,
> then Phase 4 entry whenever you're ready (43 beads under `cy1`).
>
> Closing.

*You close the terminal. The mempal-stop-hook fires automatically and
saves a final checkpoint.*

---

## What you noticed during the walkthrough

### Things the primitives did automatically (no remembering required)

- **Cold-start** primed beads + MemPalace + diary + stale check.
- **Hook on `bd update --claim`** reminded to dispatch
  bug-family-researcher (redundant in this case because you'd already
  done it via the recipe step 1, but the hook is defense-in-depth).
- **`/dispatch-middle` ran the RED→GREEN core as two independent
  agents** — a test-author wrote and committed the RED test, then a
  separate implementer made it GREEN from the committed file alone.
  Central wrote nothing in the middle. The anti-tautology guarantee
  was structural, not a thing you had to police.
- **Subagent dispatches** kept main context clean — the
  bug-family-researcher's full search output, and the test/code churn
  of the two pipeline agents, never bloated your conversation.
- **Hook on `bd close`** checked capture evidence and **allowed** the
  close because three of five matchers passed (drawer + KG + diary).
  It would have blocked only on zero evidence.
- **Stop hook** fired the AUTO-SAVE checkpoint at session end.

### Things you did manually

- Decided which bead to work (recommendation came from
  session-startup, but the choice is yours).
- Approved the drawer + KG triples after subagents drafted them.
- Chose the merge option in `finishing-a-development-branch`.
- (You did NOT bypass the close hook — capture was done, so the
  evidence-aware hook allowed the close on its own.)

### Things the recipe enforced

- TDD red-green discipline, split across two independent agents (test
  first by the test-author, watch fail, then GREEN by the implementer).
- M2 bead-assumption audit — reconcile the bead's stated cause against
  the M1 diagnosis before pinning a test (the stale "+ server" caught).
- Bug-class coverage in addition to instance test.
- Verification with exact pass counts before claiming done.
- Drawer + KG capture before close (via /wrap-up).
- Push + status check before declaring session done.

---

## Variations

### **[v1.5]** If your project has `mode: light`

The recipe still runs, but Claude opens with a one-line warning:
*"workflow mode is light; recipe ceremony reduced — TDD/review
optional, drawer-capture still recommended."* The bd-claim-research
hook stays silent (no reminder injection). The bd-close-capture hook
never blocks — `bd close` proceeds without `--force`. The `git push`
hook still warns if `.beads/` has uncommitted changes. The status line
still populates.

Use case: a project where the full ceremony is overkill but you want
the visibility (status line, state file).

### **[v1.5]** If your project has `mode: off`

The session-startup skill skips itself. Every activity recipe
defers to `bead-lifecycle-shell`, which refuses with: *"workflow
mode is off; the recipe skill is disabled for this project. Bypass
via `CLAUDE_WORKFLOW_OFF=0` env or edit
`<project>/.claude/workflow.json`. To work the bead anyway, drive
it manually."* All three hooks are silent. Status line is empty.

Use case: a project where the workflow doesn't fit (a one-off script,
an exploratory spike, a non-engineering project). The bd CLI still
works — you just lose the recipe and the capture enforcement.

Quick toggle for a single session without editing files:

```bash
CLAUDE_WORKFLOW_OFF=1 claude
```

### If you were starting a feature, not a bug

Replace step 3 (Phase 1 systematic-debugging) with `superpowers:brainstorming`
or `beadpowers:brainstorming`. The two-agent `/dispatch-middle` split
still applies — the test-author pins the *contract* the brainstorm
produced (not a reproduced failure) and the separate implementer makes
it GREEN. Bug-class coverage becomes "test for the feature AND for the
negative cases." See [the feature walkthrough](./feature-walkthrough.md)
for the full feature-shaped pipeline.

### If you had 3 unrelated bugs to fix

There are two axes of parallelism, and they compose:

- **Across beads** — the fan-out detector (`scripts/loom-fanout-detect`,
  surfaced at selection by session-startup step 6a and the
  `/working-a-bead` router) checks the three beads' `Files:` lines. If
  no two share a file and none depends on another, it proposes a wave
  of file-disjoint beads to run in parallel via
  `superpowers:dispatching-parallel-agents` — one recipe per bug, each
  in its own worktree. (A bead with no `Files:` line is excluded from
  the wave: footprint unknown, not provably disjoint.)
- **Within each bead** — each bug in the wave still runs its own
  RED→GREEN middle through `/dispatch-middle` (test-author then
  implementer). So a 3-bug wave can fan out to as many as six
  pipeline agents, three test-authors and three implementers, plus the
  per-bead recipe orchestration.

After all complete, you batch-merge sequentially and fix any
cross-branch collateral in a single follow-up commit (this session's
t92/0qw/bi2 work hit one such collateral fix; it's normal).

### If the bead was a trivial 1-line fix

Skip steps 2 (worktree) and 12 (finishing-a-development-branch), and
skip `/dispatch-middle` — a genuinely trivial change (≤ ~15 lines, one
non-test file, no new test) is the inline exception, edited directly on
main. Record `dispatch=inline:<reason>` in workflow state so the
exception is auditable. Steps 4-7 (TDD + bug-class + full suite) still
apply — trivial fixes still get tests. The evidence-aware close hook
will block only if you filed no capture at all; for a one-liner,
either file a quick drawer or pass a substantive `--reason` (≥200
chars with a commit SHA), and consider `bd remember` for any one-liner
tribal fact that emerged. `BD_CLOSE_FORCE=1` remains the auditable
last resort.

### **[v1.5]** If you're onboarding a fresh project (or auditing an existing one)

Type `/audit-project` (manual-only — never auto-suggested). The
`audit-project` skill loads, dispatches the `project-onboarder`
subagent for a read-only scan, and returns a 9-item checklist:
git/branch hygiene, `.beads/`, bd hooks, `workflow.json`, MemPalace
wing, CLAUDE.md ≤200 lines, `.claude/rules/` for detected directories,
optional `.claude/agents/`+`commands/`, `bd memories`. For each
WARN/MISS item, the skill shows a template-based fix; you respond
`yes`, `edit`, or `skip` per item — nothing applies without explicit
per-gap approval. Re-run after material project changes (e.g., the
project gains a `prompts/` directory and now wants `prompts.md`).
Use `mode=off` on a project to opt out of the recipe; `/audit-project`
itself runs regardless of mode (since it's how a project enters or
changes its mode).

### If something went wrong

Three failure modes worth watching for:

1. **Hook didn't fire.** Try `/clear` to force settings.json
   reload. Smoke-test the hook script directly:
   ```bash
   echo '{"tool_name":"Bash","tool_input":{"command":"bd close foo"}}' | bash ~/.claude/hooks/bd-close-capture.sh; echo $?
   ```
2. **Subagent took too long.** Latency 5-15s is expected; >30s
   suggests the MemPalace MCP server may need `mempalace_reconnect`.
3. **Drawer + KG diverge from reality.** Both got filed but the
   commit didn't actually merge cleanly. Verify with `git log
   --oneline -3` and `bd show <id>` before trusting either.

---

## What to expect over the first few sessions using this

A few things still vary by environment more than by design:

- **Hot-reload of `settings.json`** for the hooks can lag by Claude
  Code version. If hooks don't fire on the first try, `/clear` and
  retry.
- **Slash commands dispatching subagents** is the pattern the whole
  middle rests on, and it is now observed working: `/dispatch-middle`
  routinely spins up a test-author then an implementer in one shared
  worktree. If a dispatch ever fails to fire, fall back to dispatching
  the Agent tool manually with the brief templates from
  `skills/dispatch-middle/SKILL.md`.
- **The close-capture hook is evidence-aware, not blocking-by-default.**
  It allows the close whenever ANY of its five matchers passes and
  blocks only on zero evidence — so a normal `/wrap-up` flow (drawer +
  KG + diary) closes cleanly without a bypass. If it still fires when
  you believe capture is done, check that the drawer landed in the
  bead's wing and that the bead ID appears in it; the `N/5 matchers`
  line in the hook output tells you exactly which matchers it saw.
- **Path-scoped rules in `.claude/rules/`** auto-load when matching
  files open. Verify by editing a test file and asking Claude what
  rules are in effect; the `tests.md` rules should appear.

When something doesn't work as designed: open the master plan drawer
("WORKFLOW INFRASTRUCTURE PLAN"), check the "Known limitations"
section, and append a status update drawer when you ship a fix.

---

## Where to update what (quick recap)

If during a session you notice a friction point or want to tweak
behavior:

| Friction | Edit |
|---|---|
| The bug-shaped variable middle is wrong | `~/.claude/skills/bugfix-a-bead/SKILL.md` |
| Cross-activity lifecycle phase wrong | `~/.claude/skills/bead-lifecycle-shell/SKILL.md` |
| Cold-start ritual missing something | `~/.claude/skills/session-startup/SKILL.md` |
| `/bugfix-a-bead` should do X | `~/.claude/commands/bugfix-a-bead.md` |
| Subagent prompt unclear | `~/.claude/agents/<name>.md` |
| Hook fires wrong / too aggressively | `~/.claude/hooks/<name>.sh` |
| Permission keeps prompting | `~/.claude/settings.json` `permissions.allow` |
| Project convention I keep forgetting | project `CLAUDE.md` (or `.claude/rules/<area>.md` if path-scoped) |
| Decision worth capturing | `mempalace_add_drawer` |
| One-liner tribal fact | `bd remember "<insight>"` |
| Onboarding a new project | `/audit-project` (manual-only) |

The [where-to-update-what guide](../how-to/where-to-update-what.md)
has the full matrix.
