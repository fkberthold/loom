# I think I have seen this bug before

To find prior fixes, sibling bugs, and related decisions before
starting work, follow these steps.

## Precondition

- You have a symptom, error message, function name, or topic
  keyword to search on.
- You suspect the family has lineage in MemPalace or beads.

## Steps

1. **Run `/lineage <topic>`** for the one-shot path. The command
   dispatches the `bug-family-researcher` subagent with the topic.
   It returns a structured prior-art report: family lineage,
   relevant decision drawers, KG facts, bd memories, recommended
   approach, and open questions.

2. **Search MemPalace directly** if you want finer control:
   ```bash
   mempalace_search "symptom keywords"
   mempalace_kg_query "<entity-name>"     # function / error / file
   mempalace_diary_read "claude-opus" 10  # last 10 introspective notes
   ```

3. **Search beads** for related closed work:
   ```bash
   bd search "<keyword>"
   bd memories "<keyword>"
   ```

4. **Cross-reference the findings.** The prior-art report names
   sibling beads and drawer slugs. Open the highest-relevance
   drawer and read it before designing your fix.

## Outcome

You know whether the bug has a documented family, what fix patterns
applied, and what to cite when capturing the close drawer.

## Related

- For the family-researcher subagent's full recipe + output format,
  see [reference: subagents](../../reference/subagents/index.md).
- For why MemPalace bug-family search is the load-bearing first
  step, see [explanation: mental model](../../explanation/mental-model.md).
