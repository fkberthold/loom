# Claude Workflow Walkthrough

> A narrative session walkthrough showing what Frank's experience looks
> like end-to-end. Companion to `claude-workflow-manual.md` (the
> reference) — this file shows the workflow in motion using a real bead
> from the HAW project (`hundred-acre-woods-80v`: remove the diagnostic
> fingerprint logging from poe_server + server).
>
> Format: "**You:**" lines are what you type; "**Claude:**" lines are
> the assistant's response (sometimes summarized, sometimes verbatim);
> indented italic blocks are commentary on what's happening behind the
> scenes. Hook output appears in `[brackets]` when relevant.
>
> Honesty caveat: the recipe was shipped 2026-05-02 and verified at the
> primitive level (skill files exist, hooks smoke-test correctly,
> commands and agents are written). The end-to-end live-firing behavior
> below is the *designed* experience; some details (settings.json
> hot-reload, slash command auto-dispatching subagents) await
> confirmation on the first real session that uses the new
> infrastructure. Where this walkthrough is aspirational rather than
> observed, a note flags it.
>
> **Updated 2026-05-03 for v1.5** — workflow modes (full/light/off),
> the per-project state file, the SessionStart onboarding hook, and
> the status line. v1.5-specific moments are tagged with **[v1.5]**.

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
/working-a-bead 80v
```

*The slash command fires. Because it has `disable-model-invocation:
true`, it only runs on explicit invocation — the model can't
auto-trigger it. The command body says "Invoke the working-a-bead
skill and follow it exactly as presented."*

**Claude:** *(loads `~/.claude/skills/working-a-bead/SKILL.md` and
walks step 1)*

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

### 5. TDD — RED first

**Claude:** *(invokes `superpowers:test-driven-development`)*

> Writing the failing test first. Since this is a removal, the test
> asserts the helper is GONE — `_credential_fingerprint` should not
> exist as a module attribute.

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

*RED confirmed. The helper is still there; the test correctly fails.*

**[v1.5]** *Claude updates the state file at the RED checkpoint per
the recipe's stage map:*

```bash
~/.claude/scripts/workflow-state set stage=tdd-red
```

*Status line:* `WORKFLOW: full | task:tdd-red | bead:80v | 0s`.

### 6. GREEN — minimal fix

**Claude:**

> Removing the helper, the log line, and the stranded import.

*Claude makes three edits: removes the function (lines 36-50), removes
the log call (lines 206-212), removes `import hashlib` (line 23).*

```bash
python3 -m pytest tests/test_poe_server_backend.py::test_credential_fingerprint_helper_removed -v
```

```
PASSED tests/test_poe_server_backend.py::test_credential_fingerprint_helper_removed
```

*GREEN.*

### 7. Bug-class coverage

**Claude:**

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

### 8. Full suite

```bash
python3 -m pytest -q
```

```
2167 passed, 16 skipped in 11.42s
```

*No enshrined tests surfaced — clean removal. (Compare 0qw which
surfaced 14 such tests; this bead is genuinely simpler.)*

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

### 11. Commit

```bash
git add engine/backends/poe_server.py tests/test_poe_server_backend.py
git commit -m "80v: remove 13p.3.11 diagnostic fingerprint logging

The _credential_fingerprint helper + per-outbound-call log emission
were added in commit c1f8812 to debug an 'Invalid API key' mystery
during the 13p.3.11 server-bot deploy day. That mystery resolved
to undeclared server_bot_dependencies + wrong calling pattern (fix
landed in commits 49645df + de50764 + a3483f2). The fingerprint
logging confirmed all three credential surfaces were identical
(sha256 a6d9970746, len=32) and is now noise on every outbound call.

- engine/backends/poe_server.py: remove _credential_fingerprint
  helper (lines 36-50), the logger.info call inside _stream_chunks
  (lines 206-212), and the now-stranded 'import hashlib' (line 23).
- tests/test_poe_server_backend.py: add instance test asserting the
  helper is removed + class test asserting no fingerprint-shaped
  logs in the outbound path (bug-class coverage per Frank's
  deploy-day rule).

2167 passed, 16 skipped (+2 new tests, no regressions).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

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

[bd-close-capture hook fires — but capture IS done, so the hook ALLOWS the close to proceed. Wait, no — the current implementation blocks unconditionally. You'd need --force or BD_CLOSE_FORCE=1.]

*That's a discovered limitation. The hook can't yet detect "drawer was just filed for this bead." Use --force.*

**Claude:**

> Close blocked by capture hook. Drawer + KG were just filed; using
> --force per the documented bypass.

```bash
bd close hundred-acre-woods-80v --force --reason="..."
bd dolt push
git push
git status
```

```
On branch main
Your branch is up to date with 'origin/main'.
nothing to commit, working tree clean
```

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
- **Subagent dispatches** kept main context clean — the
  bug-family-researcher's full search output never bloated your
  conversation.
- **Hook on `bd close`** blocked the close until you used `--force` —
  a known friction point that gets revisited if it becomes annoying.
- **Stop hook** fired the AUTO-SAVE checkpoint at session end.

### Things you did manually

- Decided which bead to work (recommendation came from
  session-startup, but the choice is yours).
- Approved the drawer + KG triples after subagents drafted them.
- Chose the merge option in `finishing-a-development-branch`.
- Used `--force` to bypass the close hook (justified: capture WAS done).

### Things the recipe enforced

- TDD red-green discipline (test first, watch fail, then implement).
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

The session-startup skill skips itself. The working-a-bead skill
refuses with: *"workflow mode is off; the recipe skill is disabled
for this project. Bypass via `CLAUDE_WORKFLOW_OFF=0` env or edit
`<project>/.claude/workflow.json`. To work the bead anyway, drive it
manually."* All three hooks are silent. Status line is empty.

Use case: a project where the workflow doesn't fit (a one-off script,
an exploratory spike, a non-engineering project). The bd CLI still
works — you just lose the recipe and the capture enforcement.

Quick toggle for a single session without editing files:

```bash
CLAUDE_WORKFLOW_OFF=1 claude
```

### If you were starting a feature, not a bug

Replace step 3 (Phase 1 systematic-debugging) with `superpowers:brainstorming`
or `beadpowers:brainstorming`. The TDD cycle still applies, but you're
defining behavior rather than reproducing a bug. Bug-class coverage
becomes "test for the feature AND for the negative cases."

### If you had 3 unrelated bugs to fix

After session-startup picks the first one, instead of `/working-a-bead
<id>`, invoke `superpowers:dispatching-parallel-agents`. That spawns
one subagent per bug — each runs the recipe in its own worktree,
fully isolated. After all complete, you batch-merge sequentially and
fix any cross-branch collateral in a single follow-up commit (this
session's t92/0qw/bi2 work hit one such collateral fix; it's normal).

### If the bead was a trivial 1-line fix

Skip steps 2 (worktree) and 12 (finishing-a-development-branch).
Fix on main directly. Steps 4-7 (TDD + bug-class + full suite) still
apply — trivial fixes still get tests. Use `bd close --force` since
the recipe didn't enforce drawer capture; consider `bd remember`
for any one-liner tribal fact that emerged.

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

You'll discover whether each piece of automation actually fires. Most
of the design is verified at the primitive level (smoke tests + file
existence) but not yet at the live-session level. Specifically:

- **Hot-reload of `settings.json`** for the new hooks needs verification.
  If hooks don't fire on the first try, `/clear` and retry.
- **Slash commands dispatching subagents** is the most novel pattern.
  If `/working-a-bead` doesn't auto-dispatch the bug-family-researcher
  at step 1, dispatch manually with the Agent tool and update the
  command to be more explicit.
- **The blocking close-capture hook** is the most likely friction
  point. If it fires too aggressively, consider tightening the
  matcher (e.g., only block if the bead's ID was recently in
  conversation context, suggesting active work) — design TBD; file
  a bead under epic `2st` if you want to evolve it.
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
| The recipe is wrong / missing a step | `~/.claude/skills/working-a-bead/SKILL.md` |
| Cold-start ritual missing something | `~/.claude/skills/session-startup/SKILL.md` |
| `/working-a-bead` should do X | `~/.claude/commands/working-a-bead.md` |
| Subagent prompt unclear | `~/.claude/agents/<name>.md` |
| Hook fires wrong / too aggressively | `~/.claude/hooks/<name>.sh` |
| Permission keeps prompting | `~/.claude/settings.json` `permissions.allow` |
| Project convention I keep forgetting | project `CLAUDE.md` (or `.claude/rules/<area>.md` if path-scoped) |
| Decision worth capturing | `mempalace_add_drawer` |
| One-liner tribal fact | `bd remember "<insight>"` |
| Onboarding a new project | `/audit-project` (manual-only) |

The reference manual (`~/repos/claude-workflow-manual.md`) section 16
has the full matrix.
