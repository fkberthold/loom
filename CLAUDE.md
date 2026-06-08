# loom — project instructions for Claude Code

> This file is read at session start when working in `~/repos/loom`.
> Loom is the workflow-infrastructure repo (the meta-project). It's
> not a deploy target; it's a collection of skills, hooks, agents,
> commands, and helpers that get installed into `~/.claude/` to shape
> how Claude Code itself works.

## What this repo is

A package of Claude Code primitives that integrates beads + MemPalace
+ superpowers + beadpowers into one disciplined workflow. See
[README.md](README.md) for the user-facing description and the
published docs site (https://fkberthold.github.io/loom/) for the
Diataxis-shaped reference, how-to guides, tutorials, and design
explanation.

**Not a code project**. Loom is mostly markdown (skills, agent
definitions, slash commands) + bash (hooks, helpers, scripts) + JSON
(settings snippets). No Python, no application code.

## Working on loom

### Recipe applies — but lighter

The activity recipes (today: `bugfix-a-bead`; in flight:
`feature-a-bead`, `refactor-a-bead`, `research-a-bead`,
`cleanup-a-bead`, `docs-a-bead`) apply to loom work too — pick the
recipe matching the bead's shape, or invoke `/working-a-bead <id>`
once the router lands. With these adjustments:

- **TDD scales differently for bash.** Use `bats` or shell-fixture
  tests under `lib/tests/`. The `light` workflow mode is appropriate
  for many loom changes (skill text edits, hook tweaks, doc updates).
- **Bug-family search is meta**: prior loom decisions live in this
  repo's beads + the original `hundred_acre_woods/decisions`
  MemPalace wing (where the design was locked 2026-05-02). Search
  both.
- **Capture in MemPalace** — loom decisions go in a new
  `loom/decisions` MemPalace wing (created on first use). Cross-
  reference back to `hundred_acre_woods/decisions` via tunnels when
  the lineage is HAW-rooted.

### Editing primitives

After install, `~/.claude/...` files are SYMLINKS into this repo.
Edit them either in `~/.claude/...` or here in `~/repos/loom/...` —
both paths point at the same underlying files. Changes take effect
immediately for the current session (settings.json file watcher
reloads hook config; skills load fresh per session).

### Beads tracker

This repo has its own `bd` workspace under `.beads/`. Active workflow
infrastructure beads live HERE, not in HAW. The original epic `2st`
(v1) and `bng` (v2) remain in HAW as historical record; new loom-side
work goes in loom's beads.

### MemPalace conventions

Loom decisions go in `loom/decisions` wing (or `loom/<topic>` rooms).
Diary entries can stay in `wing_claude-opus` (per-agent personal
wing). Cross-project tunnels:

- `loom/decisions ↔ hundred_acre_woods/decisions` for lineage to the
  v1/v1.5/v2 design drawers
- `loom/decisions ↔ <other_project>/decisions` when loom work was
  driven by experience in another project

### Testing changes

Most loom changes affect Claude Code's behavior live (hooks +
settings.json hot-reload). To smoke-test:

```bash
# Hook output JSON validation
echo '{"tool_name":"Bash","tool_input":{"command":"bd close foo"}}' | \
  bash hooks/bd-close-capture.sh; echo "EXIT: $?"

# State + statusline round-trip
~/.claude/scripts/workflow-state set stage=verify
bash ~/.claude/scripts/statusline.sh < /dev/null

# Mode resolution
~/.claude/scripts/workflow-state mode
```

For full lifecycle testing (hooks firing on real Claude Code tool
calls), open a fresh session in this repo and exercise the relevant
slash commands.

## Conventions

- **Use loom's own bead tracker for loom work.** Don't file loom
  beads in HAW or any other project.
- **One bead = one branch (`frank/<bead-id>`) = one worktree** when
  the change is non-trivial. Skip worktree for ≤1-line tweaks.
- **Worker-dispatch is the default for the variable middle.** Any
  bead whose middle has a RED→GREEN cycle defaults to a dispatched
  worker; inline (central edits directly) is the explicit exception,
  waved through without justification only when the change is ≤ ~15
  lines AND touches a single non-test file AND adds no new test. See
  the "Dispatch discipline" section of `bead-lifecycle-shell` for the
  full threshold + the `workflow-state` `dispatch` field recording.
- **Splitting heuristic at bead creation.** When filing 2+ candidate
  items, ask: are they independent (no shared files, no sequential
  dependency)? If yes, file as sibling beads under an umbrella
  feature/epic — `bd ready` will surface them for parallel dispatch
  via `superpowers:dispatching-parallel-agents`. If no (shared files,
  one depends on another's outcome), file as one bead. The
  recipe-middle within-bead parallel nudge in `bead-lifecycle-shell`
  ("Decision: parallel vs sequential" → "Within-bead") catches what
  slips through; this heuristic prevents the slip at the source.
- **Declare `Files:` in every bead description (loom-asr).** Add a
  `Files:` line listing the paths the bead is expected to touch, e.g.
  `Files: scripts/loom-foo, lib/tests/loom-foo.test.sh`. This is the
  input the fan-out detector (`scripts/loom-fanout-detect`, surfaced
  at selection by session-startup step 6a + the `/working-a-bead`
  router) uses to decide which ready beads are safe to dispatch as a
  parallel worker wave: two beads are wave-compatible iff they have
  NO dependency edge between them AND their `Files:` sets are
  DISJOINT. The detector **degrades conservative** without the line —
  a bead with no `Files:` declared is treated as "footprint unknown,
  not provably disjoint" and is EXCLUDED from any proposed wave, so
  it silently never gets parallelized. Format: comma-separated paths
  on a single line beginning `Files:`; trailing parenthetical/bracket
  annotations (`(router)`, `[optional]`) and a leading `optional `
  marker are tolerated and stripped during matching. Use relative
  repo paths (matching the worktree-relative convention dispatched
  workers use).
- **Capture decisions** in MemPalace drawers (`loom/decisions`
  room). The drawer is the design source-of-truth; this repo is the
  implementation source-of-truth. When they diverge, the drawer
  wins on intent, the repo wins on what currently works.
- **Status drawers** for incremental delivery — append-only updates
  to the master plan drawer (mirrors the `WORKFLOW INFRASTRUCTURE
  PLAN` pattern from HAW).
- **Parallel worker dispatch — use relative paths in prompts.**
  When dispatching workers via `Agent` + `isolation: "worktree"`,
  give them **relative** file paths (`commands/foo.md`), not
  main-repo absolutes. The harness creates the worktree but does
  NOT sandbox absolute-path Edit/Write calls — workers using
  `/home/frank/repos/loom/<path>` write into MAIN, bypassing the
  worktree. Avoid prompts that lead workers to do main-branch git
  archaeology (`git show <main-sha>`), since the resulting paths
  are easy to misinterpret as main-absolute. After workers return,
  verify with `git diff --stat` in BOTH the worktree and main to
  detect leaks. See `drawer_loom_decisions_df73c725b47dd67832935e3a`
  (loom-tag, 2026-05-04) for the full finding.
- **Parallel worker dispatch — stale-base hygiene.**
  `Agent({isolation: "worktree"})` does not guarantee that the
  worktree branches off the latest local `main`. In sessions with
  sequential dispatch waves, a later worktree can inherit a base
  from earlier in the session, missing intervening merges that the
  new bead depends on. Observed in liza_base 2026-05-06 across
  bqo/9uo/982 agents. Mitigation is convention-only — the Agent
  harness's base-ref behavior is opaque to loom. Worker briefs
  should run the pre-flight smoke battery in
  `.claude/rules/dispatched-agents.md` as the first bash call;
  step 4 of that battery compares `git merge-base HEAD main`
  against `git rev-parse main` and auto-rebases when stale.

  `git rebase main` alone is NOT sufficient — on an empty-branch
  worker (no commits yet) it returns rc=0 as a no-op even when the
  base trails main, and the staleness only surfaces post-commit as
  unrelated files in `git diff --stat main HEAD`. Surfaced by
  loom-b1l worker 2026-05-15, fixed in loom-6zi. The smoke battery's
  step 4 does the explicit merge-base check + conditional rebase
  that catches this.

  For WIP preservation across the rebase (mid-flight crashes that
  left untracked files), use `scripts/loom-rebase-worktree main`
  (loom-azt) instead of plain `git rebase main`. See
  `drawer_loom_decisions_ae64101e954f38d533d02466` (loom-azt closing
  drawer) and `drawer_loom_decisions_d09f9f243008f5a6731542e3`
  (loom-x4m closing drawer) for cluster context.
- **bd-state auto-merge protection (loom-4um, 2026-05-15).** Git's
  line-based three-way merge of `.beads/issues.jsonl` can silently
  reconcile bead-state lines across semantic boundaries when a
  feature branch based on stale main is merged into post-newer-work
  main. The `--ours` conflict-resolution pattern only fires on
  textual conflicts; auto-merges look successful but revert closed
  beads to in_progress. Structural fix: `.gitattributes` ships
  `.beads/issues.jsonl merge=bd-export`, `scripts/bd-merge-driver.sh`
  runs `bd export` to regenerate from the authoritative dolt store
  on every merge, and `install.sh` wires the driver into the loom
  repo's `.git/config`. Downstream projects adopting loom run a
  similar `git config merge.bd-export.driver` step (handled by
  `/audit-project` on first run). Composes orthogonally with the
  bd-worktree-preseed hook (loom-x4m).
- **Design-cycle KG predicate set — SOFT recommendation, not a
  locked schema (loom-tdua).** A design cycle's L1 spine (the
  queryable knowledge-graph layer of the layered design substrate)
  is the structured home for its locked structure + invariants. The
  recommended design-predicate vocabulary is `supersedes_design_of`
  (a new decision retires an earlier one), `grounded_in` (a decision
  rests on a finding / prior decision / external reference),
  `emits_bead` (a locked decision spawns the implementation bead that
  carries it forward), `soundness_tier` (which of the two-tier model
  the decision reached — see the RED: bullet below), and
  `depends_on_invariant` (a decision is contingent on a structural
  invariant holding). This is a *recommendation*, NOT a fixed schema:
  the KG is open, so these predicates compose with whatever
  project-local predicates already exist; a cycle that needs a
  different shape is free to deviate. The set exists so independent
  cycles converge on a shared vocabulary by default, not so the
  vocabulary is enforced.
- **`RED:` spec-line on beads spawned from a Tier-1 design decision
  (loom-tdua, lineage loom-5w6).** Soundness is two-tier: Tier 0 is
  coherence (the always-on floor); Tier 1 is *executable-spec
  emission* — an OPTIONAL ceiling where a locked decision that has a
  natural testable altitude carries its spec forward as the handoff
  bead's RED test. When a bead is filed from such a decision, add a
  `RED:` line to its description carrying the decision's executable
  spec verbatim — a behavioral Given-When-Then scenario, or a
  structural `INVARIANT: …`. This is parallel to the loom-asr `Files:`
  line: a single structured line in the bead description that a
  downstream consumer reads. The implementation bead *inherits its
  RED test from this line* — the recipe's RED→GREEN middle starts
  from the `RED:` text rather than re-deriving the acceptance
  criterion. A decision with no testable altitude carries Tier 0 only
  and its bead omits the line (expected, not a gap); forcing a `RED:`
  on every bead would re-import the design→build mismatch loom-l0f
  diagnosed, so the line is optional by construction. Format:
  single line beginning `RED:`.
- **A design cycle is an above-bead orchestrator, NOT a bead/epic
  (loom-tdua).** Do not file a design cycle as a bead or epic. Its
  state lives in the layered substrate — the L2 design-doc drawer's
  header (status, in-flight reasoning, locked-decision sections) plus
  the L1 KG (structure + invariants, queryable + update-in-place).
  The cycle *emits* beads (via `emits_bead`) once decisions lock; it
  is not itself one. The governing posture is **reason-in-prose,
  precipitate-into-structure**: in-flight thinking happens on a
  permissive prose surface, and as decisions firm up they precipitate
  into the structured destination (KG facts + drawer locked-decision
  sections + `RED:`/`Files:` lines on emitted beads). Loom is
  **opinionated about the structured destination + cadence**
  (where locked structure lands and when), **permissive about the
  prose reasoning surface** (how you get there is yours), and
  **generative about human Diataxis** (the four-quadrant human docs
  are a downstream projection rendered from the substrate, never the
  substrate itself — precedence system/beads/MemPalace > docs, per
  loom-9z1.10).

## Tools

The `bd`, MemPalace MCP tools, and superpowers/beadpowers skills all
work normally here. The hooks + statusline are loom-installed (this
repo's own files) — meta-recursion is fine, the hooks operate on bd
commands regardless of which project you're in.

## Don't

- Don't commit `~/.claude/settings.json` — it's user-machine-specific
  and contains stuff outside loom's scope.
- Don't commit symlinks — install.sh creates them on a per-machine
  basis. The repo holds the canonical files; symlinks are
  per-installation.
- Don't add HAW-specific content to `docs/` — pages there are
  project-agnostic. HAW-specific examples should mention HAW as one
  example, not as the only example.
- Prefer committing from the main repo path
  (`~/repos/loom/`) over committing from inside a worktree
  (`.worktrees/<bead>/`). The bd pre-commit hook in worktree mode
  has been observed exporting `issues.jsonl` to the worktree root
  instead of (or in addition to) `.beads/issues.jsonl` (loom-22h).
  `/issues.jsonl` is gitignored as a defense. The
  `hooks/bd-worktree-preseed.sh` PreToolUse hook (loom-x4m) now
  pre-seeds the worktree's bd dolt + applies
  `export.git-add=false` + adds `.beads/issues.jsonl` to the
  worktree's `.git/info/exclude` on first write-class bd call —
  so dispatched workers no longer wipe main's bd state. Even with
  that fix, the recommended workflow is still: do the bead's work
  in the worktree, then `cd ~/repos/loom && git merge --no-ff
  frank/<bead>` from main.


<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:ca08a54f -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase=merges  # preserves --no-ff bead-merge bubbles (loom-6z3)
   # Guard: skip bd dolt push for solo workspaces (no remote configured) — loom-hsb.
   if bd dolt remote list --json 2>/dev/null | grep -q '"name"'; then
     bd dolt push
   else
     echo "(solo bd workspace; no Dolt remote — skipping bd dolt push)"
   fi
   git push
   git status  # MUST show "up to date with origin"
   ```
   Repo-local `pull.rebase=merges` is set so plain `git pull` would
   also do the right thing; the explicit flag matches the convention.
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
<!-- END BEADS INTEGRATION -->
