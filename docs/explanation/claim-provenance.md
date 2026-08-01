# Claim provenance

> **Thesis.** When an agent reports back, the costly failure is not
> that it was wrong — it is that its report gave you no way to tell
> *which* of its claims might be. A report that blends
> rigorously-verified findings with unverified inferences at uniform
> confidence has **flattened** a distinction its own author held, and
> the verified claims lend their credibility to the inferred ones. The
> fix is not a second agent that re-derives the distinction; it is to
> make the original author state it as it writes. This page explains
> why the mechanism is a *structural* check and not a critic, a
> confidence score, or a trust score — and why the enforcement line
> falls where it does.

## Provenance flattening

Consider a worker that returns four claims: three it established by
running a command, and one it inferred from reading the surrounding
code. Written out as prose, all four look the same. They carry the same
declarative grammar, the same confident tone, the same absence of
hedging. Nothing in the artifact marks the fourth as different in kind.

Central then reads that report and acts on it. This is usually
described as a review failure — central *should* have been more
skeptical. That framing is wrong, and getting it wrong is what sends
people reaching for the wrong fix. **Central is reading the report
correctly.** The report asserts four things at uniform confidence, and
central believes four things at uniform confidence. The defect is in
the artifact, not in the reading of it.

Worse, the flattening is not neutral: it is *credit-transferring*. The
three verified claims establish the report as careful and well-grounded,
and that established credibility attaches to the fourth claim by
adjacency. An inference embedded among verified findings is believed
*more* than the same inference stated alone.

The load-bearing observation is this: **the distinction existed at
authoring time.** The worker knew perfectly well which claims it had
run a command to establish and which it had inferred — it simply had no
obligation to say so, and prose does not force the issue. The
information was not lost because it was unavailable; it was lost
because nothing asked for it. That is why the fix does not need a
second agent to reconstruct anything. It needs the first agent to
write down what it already knew.

So the contract is minimal: every load-bearing claim carries **either**
the evidence that establishes it — the command run and its result, or a
`file:line` — **or** the literal marker `INFERRED`. Never neither. The
slot is a **pointer, not a rationale**: it says where to look, not why
to believe. Reasoning stays wherever the report already keeps it.

A worked example: in one incident, a reviewer's claim about FIFO
ordering in a queue implementation turned out to be wrong — and the
same claim had surfaced a real, untested liveness gap. That pairing
recurs, and it drives the refutation rule below. Any project running
agents that report findings will accumulate its own instances.

## Why not a critic agent

The reflex fix is another agent: dispatch a critic that reads the
worker's report and flags the shaky claims. It is rejected on **four
independent grounds** — independent in the sense that defeating any one
of them leaves the other three standing.

**1 — Same-family verification maximizes positivity bias.** A critic
drawn from the same model family as the worker shares its priors,
blind spots, and failure modes. It is disproportionately likely to
agree, and its agreement carries no information. The check that most
looks like verification is the one least able to perform it.

**2 — Debate rounds measurably lower accuracy.** Multi-agent
critique-and-revise loops do not reliably converge on the truth. Models
trained toward agreeableness yield under pushback regardless of whether
the pushback is correct, so an additional round can move a correct
answer to an incorrect one. Adding a critic is not a monotone
improvement — it has a real chance of making the output worse.

**3 — More agents stop helping past a saturation threshold.** Beyond a
certain capability level, adding agents yields no accuracy gain, and on
sequential work — where each stage depends on the last — it actively
hurts. A critic in a pipeline is exactly the sequential case.

**4 — The critic would re-derive information the worker already had.**
This is the decisive one, and it is the flattening argument turned
around. A critic's job would be to reconstruct which claims were
grounded and which were inferred — a fact the original worker knew for
free and discarded. Paying a second agent's full context and latency to
recover a discarded fact is strictly worse than not discarding it.

Ground 4 also explains why the other three are not merely a list of
risks to be mitigated. Even a *perfect* critic — no positivity bias,
no sycophancy, no saturation penalty — would still be doing redundant
work. The critic is not risky-but-necessary; it is unnecessary, and
also risky.

## Why not a confidence score

The next reflex is to have the worker rate itself: attach a confidence
percentage, or a high/medium/low band, to each claim. Then central
routes its attention by the number.

This fails because **verbalized model confidence is uncalibrated.** A
claim labeled 90% is not right nine times in ten, and the ordering
between a 90% claim and a 70% claim is not dependable either. A
miscalibrated score is worse than no score, because it *looks* like a
routing signal and central will route on it. The scrutiny goes where
the number points rather than where the risk is, and the appearance of
rigor makes that misallocation harder to notice.

The evidence slot is deliberately not a degree of belief. It states
**what the worker did** — a command it ran, a file it read, or nothing
retrievable at all. "I ran this command" is checkable against the
worker's own tool calls. "I am 90% sure" is checkable against nothing.
The slot sits on the retrievable side of that line by construction, and
that is what lets a mechanical reader verify it at all.

## Why not a per-agent trust score

The third reflex is reputation: track how often each agent's claims
hold up, and scale scrutiny inversely to its track record. Trusted
agents get skimmed; unreliable ones get audited.

Two findings kill it.

**Track record does not transfer across claim kinds.** An agent
reliable at running tests and reporting results is not thereby reliable
at inferring architectural intent. A single scalar per agent averages
over kinds that have nothing to do with one another, so the score is
uninformative exactly where it would be used — deciding whether *this*
claim needs checking.

**Automation complacency is worst against highly reliable automation.**
This is the sharp one. Human oversight degrades *most* when the
automated system is *most* reliable, because reliability trains the
overseer to stop looking. A trust score does not merely fail to help —
it takes the psychological mechanism that produces oversight failure
and makes it explicit policy. It would formalize precisely the bias
that produces the incidents it is meant to prevent.

Note that all three rejected mechanisms share a shape: each tries to
tell central *how much to believe* a claim. The evidence slot refuses
that framing entirely. It tells central *how the claim was established*
and leaves belief to central.

## Gate the structure, nudge the claims

The remaining question is where enforcement bites — and this is where
[gate, don't advise](gate-dont-advise.md) applies to a case whose naive
reading picks the wrong target.

The obvious thing to gate is *"did central adequately examine the
advice?"* That is the wrong target, and gating it produces a
rubber-stamp. Adequacy of examination is attended judgment: it depends
on what the claim was, what else was known, and what was at stake. A
check that fires on every report containing any inference — which is
nearly all of them — drives dispositions into reflexive box-ticking.
The check would run constantly, be satisfied constantly, and mean
nothing. That is the alert-fatigue zone, and a check nobody reads is
not a check.

The right target is one step earlier: *"did the report carry its
premises?"* That is not a judgment at all. It is a **structural
property of an artifact** — either the slots are there or they are not,
either a cited command appears among the worker's tool calls or it does
not. It is decidable, it is cheap, and it can genuinely fail.

So the line runs between the two:

- **GATE the structure.** The reader fails on exactly two mechanical
  conditions: a report carrying zero evidence slots, and a report
  citing a command absent from that worker's own tool calls. Both are
  mechanical, so effective false positives are near zero — which is
  what keeps the gate credible enough to be worth reading.
- **NUDGE the claims.** Every claim marked `INFERRED` comes back as a
  **worklist**, not a failure. The reader never judges whether an
  inference is true. That judgment stays with central, where it
  belongs.

This is exactly the dividing question gate-don't-advise poses — *is a
human (or central) supposed to weigh in?* For "does this report have
slots," no: it just needs to be true, so it is gated. For "is this
particular inference correct," yes: it is an attended decision, so it
is surfaced and not blocked. The same page's principle, applied to a
contract where the tempting target and the correct one sit one step
apart.

Two consequences follow from putting the line there.

**Refutation is two fields, not a verdict.** When central examines an
inferred claim and rejects it, the disposition answers two *separate*
questions: was the claim true (**verdict**), and was it pointing at
anything real (**residue**)? Residue may be the literal `none`, but it
may not be absent. The FIFO claim above is the reason: it was wrong
*and* it surfaced a genuine gap, and the test that eventually landed
was strictly stronger than the property the reviewer had wrongly
defended. A binary accept/reject discards the claim and the gap
together. Splitting residue into its own field is what stops a
refutation from silently consuming a finding.

**Acting on an inference means filing it first.** Central may not make
a change on the basis of an `INFERRED` claim without filing it as a
tracked item — which is also where the verdict and residue land, giving
the two-field rule a mechanical home. This is deliberately **not**
size-scoped. A three-line change built on a wrong premise is still
wrong; size governs who does the work, not whether an unverified
premise gets acted on. Claims central does not intend to act on simply
stay in the worklist, with no ceremony at all.

## Why this is not just discipline

It would be possible to state all of the above as convention and stop
there — brief workers to include evidence slots, and trust the briefs.
That is the advisory-only shape, and it rots: the contract holds for as
long as everyone remembers it exists, then quietly stops mattering.

It is equally tempting to gate the *brief* instead — a test asserting
that the instruction text contains the required clause. That is a fake
gate. It verifies that loom asked for evidence slots, never that any
report contains one. A check that cannot fail on the actual defect is
not a check.

What makes this contract enforceable is that the returned report is a
real artifact: a worker's transcript records both its final report and
the tool calls it made, so a reader can compare a cited command against
whether the worker actually ran it. That is retrieve-and-compare, not
judge-plausibility — the only kind of verification a mechanical checker
can honestly perform. Everything in this design that looks like
restraint is really that constraint being respected: gate what can be
retrieved and compared, surface everything else, and never dress
judgment up as a check.

## See also

- [Gate, don't advise](gate-dont-advise.md) — the general principle
  this contract instantiates.
- [`loom-claim-provenance`](../reference/loom-claim-provenance.md) —
  the reader: slot forms, fail conditions, output, exit codes.
