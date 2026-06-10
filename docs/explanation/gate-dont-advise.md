# Gate, don't advise

> **Thesis.** A correctness check that a human has to *remember to
> run* is not a check — it is a latent rot surface wearing a check's
> clothes. Every drift-detector or correctness invariant must be
> wired to a real enforcement gate (a suite test, a pre-push hook, or
> CI) so it fires on its own. Advisory-only checks rot silently: the
> drift they were built to catch returns the moment attention drifts
> elsewhere. This page explains the principle, the recurrence that
> motivated it, and why it is *distinct* from the deliberate
> nudge-not-block UX loom uses elsewhere.

## The principle

**Gate, don't advise.** When you write a check whose job is to keep
the system correct — a drift-detector, a consistency assertion, an
invariant verifier — wire it to a mechanism that runs it *without a
human in the loop*. Three gates qualify:

- a **suite test** that runs under the project's canonical test
  command (in loom, `script/test`);
- a **pre-push hook** that blocks the push when the check fails;
- a **CI job** that fails the build.

What does *not* qualify is "an advisory grep a maintainer is supposed
to run by hand." The moment a correctness check depends on human
memory, it has already failed — not because the check is wrong, but
because the human will, eventually and predictably, forget. The check
passes for as long as someone remembers it exists, then quietly stops
mattering.

## The recurrence that motivated it

Loom is the worked example, but the pattern is general. Loom shipped a
docs-drift detector — Check 4 of `/audit-project --check=docs`
(loom-9z1.9) — whose job was to catch divergence between the
documentation and the system it described. It worked. But it ran
*only on manual invocation*: nothing fired it automatically. As
attention moved to other work, nobody ran it, and the drift it was
built to catch silently returned. It surfaced later as the
loom-wjuo / loom-itph "ball of mud" — drift that had accumulated
unchecked until a human happened to eyeball the rendered docs site and
notice how far it had slid.

The detector was not buggy. It was *unwired*. That is the failure mode
gate-don't-advise names: a correct check, left advisory, becomes a
check in name only. The fix is never "remind people to run it more
often" — it is to *remove the person from the loop* by attaching the
check to a gate that runs on every push or every suite invocation.

This is a recurring shape, not a one-off. Any project accumulates
correctness checks faster than it accumulates the discipline to run
them by hand; the only durable home for such a check is an automatic
gate.

## Distinct from nudge-not-block

Loom deliberately uses **nudge-not-block** UX in many places — a
non-blocking advisory message that informs without halting. It is
tempting to read gate-don't-advise as contradicting that. It does not.
The two govern different things:

- **Nudge-not-block** is for an **attended decision** — a judgment a
  human *should* make, where blocking would be wrong because the right
  answer is context-dependent. A nudge surfaces information and trusts
  the human to decide. The whole point is that a person is in the
  loop, deliberately.
- **Gate-don't-advise** is for a **correctness invariant** — something
  that must hold *regardless of anyone's judgment or memory*. There is
  no attended decision here; there is only "is the system still
  correct, yes or no." Leaving such a check advisory is not a UX
  choice, it is an unguarded hole.

So the dividing question is simple: *is a human supposed to weigh in?*
If yes, a nudge is the right tool and blocking would be paternalistic.
If no — if the check just needs to be *true* — it must be gated, and
an advisory is a latent defect. Loom's own
[nudge-not-block](./workflow-modes.md) hooks and its gated suite tests
coexist precisely because they answer that question differently.

## Why this matters for current readers

When you add a check to loom (or to any loom-managed project), ask
which kind it is before deciding how to surface it. A correctness
check that ends life as a manual grep is a bug waiting for the next
lapse in attention — file it as one. The right reflex is to reach for
`script/test`, a pre-push hook, or CI *first*, and to treat "advisory
only" as a deliberate, justified exception reserved for genuinely
attended decisions — never as the default resting place for an
invariant.
