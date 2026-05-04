# Reference

The austere catalogue of what loom ships. Pages list exact paths,
signatures, flags, and behaviour. They are consulted, not read
sequentially.

> **What reference is not.** It does not teach, instruct, or argue.
> Recipes belong in [How-to](xref:how-to/index.md). Rationale belongs
> in [Explanation](xref:explanation/index.md).

## Auto-discovered primitives

The four primitive catalogues below auto-include their source files
from this repository via `mkdocs-include-markdown` globs. Adding or
removing a primitive on disk changes the rendered docs at next build;
no nav or page edits are required.

| Catalogue | Source glob | Page |
|---|---|---|
| Skills | `skills/*/SKILL.md` | [Skills](skills/index.md) |
| Slash commands | `commands/*.md` | [Slash commands](slash-commands/index.md) |
| Subagents | `agents/*.md` | [Subagents](subagents/index.md) |
| Hooks | `hooks/*.sh` (header comments) | [Hooks](hooks/index.md) |

## Static reference pages

| Page | Covers |
|---|---|
| [Installed files](installed-files.md) | Plugin set, `~/.claude/` tree, per-project files, MemPalace location |
| [Path-scoped rules](path-scoped-rules.md) | `<project>/.claude/rules/*.md` mechanism and existing rule files |
| [bd CLI](bd-cli.md) | Daily commands, bypasses, lifecycle hygiene, pointer to upstream docs |
| [MemPalace MCP tools](mempalace-mcp.md) | The 29 MCP tools by frequency tier, palace architecture vocabulary |
| [Decision tables](decision-tables.md) | Tool-selection lookups (`bd remember` vs drawer, skill vs hook, etc.) |
| [Glossary](glossary.md) | Term definitions (AAAK, bead, drawer, family, KG, recipe, etc.) |
