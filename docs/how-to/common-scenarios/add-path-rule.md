# I need to add a path-scoped rule

To capture a directory's load-bearing conventions as a path-scoped
rule that auto-loads when Claude touches matching files, follow
these steps.

## Precondition

- You have identified a directory whose conventions Claude must
  always honor when editing inside it (e.g., `tests/`, `engine/`,
  `prompts/`).
- The conventions are stable enough to encode (not still-being-
  debated).

## Steps

1. **Create the rules directory** if it does not exist:
   ```bash
   mkdir -p <project>/.claude/rules/
   ```

2. **Write the rule file** with a YAML frontmatter `paths` field:
   ```bash
   cat > <project>/.claude/rules/<area>.md <<'EOF'
   ---
   paths:
     - <area>/**/*.py
   description: <one-line description>
   ---

   # <Area> discipline

   (rules go here)
   EOF
   ```

3. **Keep it short.** Aim for ≤30 lines per rule file. Long rules
   indicate the file is being asked to teach (move to Explanation)
   or to enumerate (move to Reference).

4. **Cite source lineage when applicable.** If the rule encodes a
   decision from a prior bead or drawer, name it (e.g., "huu.15.2 /
   0qw lineage").

5. **Verify the auto-load.** Open a fresh session, edit a file
   matching the path glob, and confirm Claude honors the rule
   without you re-stating it.

## Outcome

The rule is in place. Future edits inside the matching directory
load the convention automatically. CLAUDE.md is unaffected (and
shorter, since path-scoped content does not need to live there).

## Related

- For path-scoped vs always-on convention placement, see
  [reference: path-scoped rules](../../reference/path-scoped-rules.md).
- For why the rules system is split from CLAUDE.md, see
  [explanation: mental model](../../explanation/mental-model.md).
