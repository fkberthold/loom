# loom-claim-provenance

> Central-side transcript reader that checks whether a dispatched
> worker's final report declared **how** each of its claims was
> established — failing on two mechanical conditions, and emitting
> every self-declared inference as a worklist for attended review.

## Why this exists

A worker's report blends rigorously-verified claims with unverified
inferences at uniform confidence, and the verified ones lend their
credibility to the inferred one. Central is not failing to examine the
report — it is correctly reading a report that erased a distinction its
own author held. Since that distinction existed at authoring time, the
worker states it as it writes, and this reader checks that it did.

The contract the reader enforces — the **evidence slot** — is specified
in `.claude/rules/dispatched-agents.md` ("Claim provenance in worker
returns"). The reasoning behind the reader's shape is in
[Claim provenance](../explanation/claim-provenance.md).

**It is a reader, not a hook.** `Stop` and `SubagentStop` do not
reliably fire on sidechains, so no hook can ever observe a dispatched
worker's return — see
[Claude Code hook semantics](claude-code-hook-semantics.md). Central
invokes the reader itself, after a dispatch returns. The interface
deliberately mirrors its sibling `loom-stage-spend` (basename-or-path
resolution, `--json`, exit-code verdict).

## Usage

```bash
~/.claude/scripts/loom-claim-provenance [--json] <transcript> [<transcript> ...]
```

| Argument | Meaning |
|---|---|
| `<transcript>` | An `agent-XXXX` / `agent-XXXX.jsonl` basename, **or** a path to a transcript file. One or more. |
| `--json` | Emit one JSON object per `INFERRED` claim instead of the human table. |
| `-h`, `--help` | Print usage and exit `2`. |

Flags may appear anywhere; every non-flag token is a transcript. An
unrecognised `--flag` is an error (exit `2`), not a transcript.

Typical invocation after a `/dispatch-middle` pipeline returns:

```bash
~/.claude/scripts/loom-claim-provenance agent-<test-author-id> agent-<implementer-id>
```

## How central obtains the `agent-<id>` values

The invocation above is runnable as written: the harness surfaces the
id to central through **three independent routes**, any one of which is
sufficient.

**1 — At dispatch time, from the `Agent` tool result.** Every `Agent`
call returns a result carrying the id on its own line:

```
agentId: a2eae422e1a2bf8f4 (internal ID - do not mention to user. ...)
```

The transcript for that worker is `agent-<agentId>.jsonl`. Central
knows the id the moment it dispatches, before the worker has done
anything.

**2 — At completion time, from the task notification.** A background
dispatch (loom's default) delivers a `<task-notification>` block whose
`<task-id>` is the same id, and — when `isolation: "worktree"` was
used — a `<worktree>` block naming the worktree:

```
<task-notification>
<task-id>a349f9a781c9d7829</task-id>
<tool-use-id>toolu_01PV97UJX6sek2vnmzcWWLN2</tool-use-id>
<status>completed</status>
...
<worktree><worktreePath>…/.claude/worktrees/agent-a349f9a781c9d7829</worktreePath>
<worktreeBranch>worktree-agent-a349f9a781c9d7829</worktreeBranch></worktree>
</task-notification>
```

The worktree **directory basename is the transcript basename** —
`.claude/worktrees/agent-<id>` ↔ `agent-<id>.jsonl`. So central can
also recover the id from a worktree path it already has in hand.

**3 — From the transcript directory itself.** Each transcript has a
sibling `agent-<id>.meta.json` describing the dispatch:

```json
{"agentType":"general-purpose",
 "worktreePath":"…/.claude/worktrees/agent-a349f9a781c9d7829",
 "worktreeBranch":"worktree-agent-a349f9a781c9d7829",
 "description":"loom-myhi.1 GREEN implementer",
 "toolUseId":"toolu_01PV97UJX6sek2vnmzcWWLN2",
 "spawnDepth":1,"model":"opus"}
```

`description` is the `description` central passed to the `Agent` call
and `toolUseId` is that call's id, so central can map a dispatch it
remembers back to a transcript basename without having recorded the id
at the time.

**One handling note.** The harness labels the `agentId` in route 1 as
internal metadata that should not be pasted into user-facing replies.
Passing it as an argument to this reader is a tool call, not a reply —
but when central *describes* a result to the user, refer to workers by
role or bead ("the test-author", "the `loom-myhi.1` implementer")
rather than by raw id.

## Transcript resolution

For each token, in order (first match wins):

1. the token itself, if it is an existing file;
2. `<transcript-dir>/<token>` with `.jsonl` appended if absent;
3. `<token>.jsonl` relative to the current directory.

If none resolve, the reader **fails loud** for that token rather than
skipping it — a transcript the reader cannot read is a transcript the
gate cannot see, which is the exact invisibility the contract exists to
kill.

`<transcript-dir>` is `$LOOM_CLAIM_PROVENANCE_TRANSCRIPT_DIR` when set;
otherwise the reader autodetects it as the **most recently modified**
`subagents/` directory under `~/.claude/projects`. The harness lays
these out as
`~/.claude/projects/<project-slug>/<session-uuid>/subagents/`.

!!! warning "Autodetect scans every project"
    The autodetect picks the newest `subagents/` directory across *all*
    projects, not just the current one. A concurrently active session
    in another repo can therefore win the mtime race. Set
    `LOOM_CLAIM_PROVENANCE_TRANSCRIPT_DIR` explicitly — or pass full
    paths — whenever more than one session is live.

## What the reader reads

Per transcript, two things:

- **The final report** — the **last** assistant record carrying any
  text, with its text blocks joined. Earlier assistant prose is
  in-flight thinking, not the report. This is pinned in both
  directions: a slot appearing in mid-transcript prose neither rescues
  a slotless final report nor condemns a clean one.
- **The tool calls** — every `tool_use` block's `.input.command`,
  newline-joined into one blob. Non-Bash tool calls carry no `command`
  and drop out harmlessly.

## Evidence slots — two surface forms

Both forms are recognised, and one report may carry both.

**Bracket form**, in prose reports. A trailing bracketed token ends the
claim line; the claim is the text before it:

```
FIFO ordering is broken by the map range.   [INFERRED]
The deleted test pinned FIFO.               [test_methods.go:151]
All 4 mutants die under the new test.       [go test -run TestScan -count=1 -> 4/4]
```

When a line carries several brackets, the **last** one is the slot.

**Field form**, in structured triple reports. The slot is a
**line-leading** `evidence:` field, matched anchored (`^\s*evidence:`)
in parallel with loom's `Files:` / `RED:` / `AUTOFAN-EXCLUDE:`
convention — so a mid-prose mention of the word is not a slot:

```
1. `subject` -> `predicate` -> `object`
   valid_from: YYYY-MM-DD
   source_closet: (optional drawer ref)
   evidence: <command + result, or file:line, or INFERRED>
   *Why*: <one sentence>
```

A field slot's **claim** is the block's header line — the nearest
preceding line that is neither blank, nor a recognised field
(`valid_from`, `source_closet`, `evidence`), nor the `*Why*` rationale.
The rationale deliberately stays out of the worklist entry: a citation
is a pointer, not a rationale, and folding `*Why*` in would re-merge
exactly what the contract splits apart.

## Slot payloads

| Payload shape | Read as | Checked? |
|---|---|---|
| contains an arrow — ASCII ` -> ` **or** Unicode ` → ` | **Command citation**: command before the arrow, result after | Yes — this is the only payload F2 examines |
| `path:line` | **File citation** | No — never resolved against the filesystem |
| the bare word `INFERRED` | **Marker** | No — emitted to the worklist |

Both arrow glyphs are accepted in **both** forms. This is not cosmetic:
loom's shipped agent definitions use the Unicode arrow exclusively
while prose and bead descriptions use ASCII, so a one-glyph reader
would miss real command citations.

## The two FAIL conditions

The gate is exactly two mechanical conditions. Both are structural
properties of the report; neither is a judgment about content.

| | Condition | Result |
|---|---|---|
| **F1** | The final report carries **zero evidence slots of either form** | non-zero exit, diagnostic names the report |
| **F2** | The report cites a command **absent from that worker's own tool calls** | non-zero exit, diagnostic names each claim + missing command |

Notes that matter:

- **F1 is "zero slots", not "zero brackets."** A bracket-free triple
  report whose triples each carry an `evidence:` line is fully
  evidenced and **passes**. Counting brackets would fail an entire
  agent's output for using the form that agent is specified to use.
- **Zero `INFERRED` is not F1.** A report whose slots are all citations
  succeeds with an empty worklist.
- **F2 matches by substring**, not equality. A citation of
  `go test -run TestScan -count=1` matches a tool call decorated with
  `2>&1 | tail -5`; requiring equality would manufacture false
  positives against every redirect and pipe a real call carries.
- **F2 is command-only.** File citations are never resolved on disk, so
  a `file:line` naming a path that does not exist is not a failure.
- **A failing transcript emits no worklist.** The report is to be fixed
  first. Other transcripts in the same invocation are still processed.

Everything else succeeds. The reader **never** judges whether an
`INFERRED` claim is *true* — that is attended judgment, and gating it
would produce a rubber-stamp.

## Output

The worklist goes to **stdout**; failure diagnostics always go to
**stderr** as human text in both modes, so `--json` stdout stays
machine-parseable.

**Human mode** (default) — one summary line per transcript, then one
line per inferred claim:

```
agent-good.jsonl: OK — 4 evidence slot(s), 2 INFERRED claim(s) for attended review.
  [INFERRED] FIFO ordering is broken by the map range.
  [INFERRED] The map iteration order is unspecified.
```

A failure instead prints, to stderr:

```
agent-nocite.jsonl: FAIL (F1) — the final report carries ZERO evidence slots.
    Every load-bearing claim needs a citation or the marker INFERRED,
    in bracket form ([...]) or as a line-leading `evidence:` field.
```

```
agent-badcmd.jsonl: FAIL (F2) — 1 cited command(s) absent from this worker's tool calls.
    claim:   All 4 mutants die under the new test.
    command: go test -run TestScan -count=1
```

**`--json` mode** — one JSON object per line, one per `INFERRED` claim:

```json
{"claim":"FIFO ordering is broken by the map range.","transcript":"agent-good.jsonl","form":"bracket"}
{"claim":"`loom-x4m` -> `composes_with` -> `loom-4um`","transcript":"agent-triples.jsonl","form":"field"}
```

| Field | Meaning |
|---|---|
| `claim` | The claim text — the line before the bracket, or the triple's header line |
| `transcript` | The transcript basename, including `.jsonl` |
| `form` | `bracket` or `field` |

A report carrying no `INFERRED` claims emits nothing and exits `0`.

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Every transcript clean (slots present, all cited commands found) |
| `1` | At least one transcript hit F1 or F2, or a token resolved to no file |
| `2` | Usage error — no transcripts given, `--help`, or an unknown flag |
| `3` | `jq` is not on `PATH` |

Across multiple transcripts the verdict is the worst one: a single
failing transcript makes the whole run non-zero, and the remaining
transcripts are still reported.

## Environment

| Variable | Effect |
|---|---|
| `LOOM_CLAIM_PROVENANCE_TRANSCRIPT_DIR` | Directory used to resolve bare `agent-*` basenames. Overrides autodetection. Mirrors `LOOM_STAGE_SPEND_TRANSCRIPT_DIR`. |

There is no skip/bypass variable: the reader is invoked explicitly by
central, so declining to run it needs no flag.

## What it deliberately does not do

- **It does not judge truth.** A report claiming the moon is made of
  cheese, marked `[INFERRED]`, passes — and lands on the worklist.
- **It does not review the diff.** It is not a code review and not the
  optional `/dispatch-middle` verifier stage; it checks only whether
  the *report* carried its premises.
- **It does not resolve file citations.**
- **It does not score, rank, or track agents** across runs.

## Files

- Script: `loom/scripts/loom-claim-provenance`
- Tests: `lib/tests/loom-claim-provenance.test.sh` (22 fixture blocks)
- Contract text: `.claude/rules/dispatched-agents.md` — "Claim
  provenance in worker returns"

## Lineage

- Closes `loom-myhi.1` (the reader) within epic `loom-myhi`; this page
  is `loom-myhi.5`.
- Design doc: MemPalace drawer
  `drawer_loom_decisions_1a296178707cdc55c872b467`, decisions **D2**
  (evidence-slot format), **D3** (central-side reader, not a hook), and
  **D4** (gate the structure, nudge the claims).
- Mechanism template: `loom/scripts/loom-stage-spend`, the earlier
  central-side transcript reader.
- Principle: [Gate, don't advise](../explanation/gate-dont-advise.md).
