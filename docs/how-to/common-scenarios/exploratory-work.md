# I want to do exploratory work

To run a spike that has no concrete bead yet, follow these steps.

## Precondition

- The work is exploratory: you do not yet know the contract, the
  scope, or whether it ships.
- No existing bead matches what you are about to do.

## Steps

1. **Skip the recipe.** The activity recipes are for new bead
   starts; they do not apply to spikes.

2. **Engage the brainstorming skill.** Invoke one of:
   - `beadpowers:brainstorming` if the output will be beads (epics +
     tasks).
   - `superpowers:brainstorming` if the output will be a spec or
     plan in `docs/`.

3. **Iterate through dialogue.** Refine the design, options,
   constraints, and unknowns until a concrete bead emerges.

4. **File the bead.** Run `beadpowers:create-beads` to write the
   bead (or epic + child beads) to the tracker.

5. **Engage the matching recipe.** Type
   `/working-a-bead <new-bead-id>`. The router dispatches to the
   shape that fits — see [Claim a bead](../claim-a-bead.md).

## Outcome

The spike has yielded a tracked bead. From here on, the standard
lifecycle takes over.

## Related

- For the brainstorming-variant boundary
  (`beadpowers` vs `superpowers`), see
  [reference: skills](xref:reference/skills/index.md).
- For why brainstorming is held outside the recipe, see
  [explanation: workflow modes](xref:explanation/workflow-modes.md).
