# Real-transcript corpus — `scripts/loom-claim-provenance`

**Do not hand-edit these `.jsonl` files.** They are captured reality, not
authored fixtures. Editing one to make a test pass destroys the only
property that makes the corpus worth having.

## Why this directory exists (loom-agug)

`scripts/loom-claim-provenance` shipped with a 22-block fixture suite that
was **fully green over a reader that failed on 7 of 7 real worker reports**
(100% false-fail rate, measured 2026-07-31). The suite could not catch it:
every fixture in `lib/tests/loom-claim-provenance.test.sh` was written by an
author who shared the parser's assumption about how a worker formats a slot,
so the spec's blind spot and the test's blind spot were the same blind spot.
Synthetic fixtures cannot falsify an assumption they were built from.

This corpus is the structural answer. It is **captured, not authored**: every
byte of every final report here was written by a real dispatched worker that
had never seen the parser, under a brief that stated the evidence-slot
contract. A parse rule that is wrong about how workers actually write will
fail here regardless of what the rule's author believed.

## What each file is

One `agent-real-<transcript-id>.jsonl` per worker, reconstructed from that
worker's live subagent transcript:

| record | content |
|---|---|
| `1 … N-1` | one `assistant` / `tool_use` (`name: "Bash"`) record per real Bash call the worker made, in transcript order, `.input.command` **verbatim** |
| `N` | one `assistant` / `text` record carrying that worker's **verbatim final report** |

Nothing is paraphrased, redacted, truncated, or reordered.

## Derivation

Captured 2026-08-01 from
`~/.claude/projects/-home-frank-repos-loom/357c37e4-c583-4385-aa4d-ce34f16b5f8e/subagents/`
— the session in which epic `loom-myhi` (T1–T6) was built, i.e. the first
seven contract-briefed worker dispatches that ever existed. The extraction
used the reader's own `REPORT_JQ` / `CMDS_JQ` queries, so what the corpus
holds is exactly what the reader would have read from the live file.

Verified at capture time: running `scripts/loom-claim-provenance` over this
corpus reproduces the live measurement **verdict-for-verdict, count-for-count**
(5×F1, 2×F2 with 7 and 6 named commands respectively).

## The corpus

| file | worker | live verdict at capture |
|---|---|---|
| `agent-real-a83c0cc2d34744050.jsonl` | loom-myhi.3 — agent-definition edits | FAIL (F1) |
| `agent-real-a25b90f9a6cad014f.jsonl` | loom-myhi.1 test-author, **resumed** mid-session | FAIL (F2), 7 named |
| `agent-real-a349f9a781c9d7829.jsonl` | loom-myhi.1 GREEN implementer | FAIL (F1) |
| `agent-real-a2eae422e1a2bf8f4.jsonl` | loom-myhi.2 — rules-file section | FAIL (F2), 6 named |
| `agent-real-a53dacfbf75b8a671.jsonl` | loom-myhi.4 — skill wiring | FAIL (F1) |
| `agent-real-a698833afdad2798e.jsonl` | loom-myhi.5 — docs pages | FAIL (F1) |
| `agent-real-ae5325d47938a9e73.jsonl` | loom-myhi.6 / loom-kez0 — owned template | FAIL (F1) |

Every one of those verdicts was **wrong or partly wrong** at capture time; see
the `REAL-TRANSCRIPT ACCEPTANCE` section of
`lib/tests/loom-claim-provenance.test.sh` for what the suite now requires of
each.

## Honest limitations

Stated plainly, because a corpus that oversells itself is worse than none:

1. **Seven reports, one session, one project, one model.** This is the whole
   population of contract-briefed reports that existed when the bug was found,
   not a sample of a larger one. It is not representative of report styles
   loom has not yet seen.
2. **Only the final report and the Bash commands are captured.** Thinking
   blocks, non-Bash tool calls, `user`/`tool_result` records, timestamps and
   ids are dropped. That is exactly the projection the reader takes, so it is
   lossless *for this reader* — but a future rule that wanted, say, the
   tool_result text would find the corpus insufficient and must re-capture.
3. **Growth is manual.** Nothing automatically adds the next real transcript.
   When a new report shape shows up in the wild, a human adds it here; until
   then the corpus ages.
4. **It cannot prove the contract is right.** It proves the reader agrees with
   how workers *did* write. Where a report's citation is genuinely
   unverifiable (an elided `…`, a `<placeholder>`, a parenthetical annotation
   glued onto the command), the corpus records a real defect — the fix is in
   the worker's report or in the agent definitions, never in this directory.
