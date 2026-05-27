# Reference

The austere catalogue of what the project ships. Pages list exact
paths, signatures, flags, and behaviour. They are consulted, not read
sequentially.

> **What reference is not.** It does not teach, instruct, or argue.
> Recipes belong in [How-to](../how-to/index.md). Rationale belongs
> in [Explanation](../explanation/index.md). Step-by-step belongs in
> [Tutorials](../tutorials/index.md).

## Auto-discovered primitives

The four primitive catalogues below auto-include their source files
from this repository via `mkdocs-include-markdown` globs. Adding or
removing a primitive on disk changes the rendered docs at next build;
no nav or page edits are required.

| Catalogue | Source glob | Page |
|---|---|---|
| Skills | `skills/*/SKILL.md` | [Skills](skills/index.md) |
| Slash commands | `commands/*.md` | [Commands](commands/index.md) |
| Subagents | `agents/*.md` | [Agents](agents/index.md) |
| Hooks | `hooks/*.sh` | [Hooks](hooks/index.md) |

If your project does not have one of these primitive directories, the
matching catalogue page renders empty — that is the expected behaviour.
Delete the unused page (and its nav entry) if the project will never
have those primitives, or leave it in place if you might add them
later.

## Static reference pages

Add static reference pages here as the project grows: CLI surfaces,
configuration files, environment variables, schema definitions, etc.
Each gets its own page in this directory and an entry in the table
above (or in `mkdocs.yml`'s `nav` block).
