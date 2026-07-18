# Reference

The austere catalogue of what loom ships. Pages list exact paths,
signatures, flags, and behaviour. They are consulted, not read
sequentially.

> **What reference is not.** It does not teach, instruct, or argue.
> Recipes belong in [How-to](../how-to/index.md). Rationale belongs
> in [Explanation](../explanation/index.md).

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

Hand-written reference pages, alphabetical by area. The full set is
in the **Reference** section of the site nav; the table below is the
complete static-page inventory at this commit (auto-generated
catalogue pages are listed separately above).

| Page | Covers |
|---|---|
| [Installed files](installed-files.md) | Plugin set, `~/.claude/` tree, per-project files, MemPalace location |
| [Path-scoped rules](path-scoped-rules.md) | `<project>/.claude/rules/*.md` mechanism and existing rule files |
| [Project constitution](project-constitution.md) | The `templates/project-constitution.md` template + per-project constitution file |
| [bd CLI](bd-cli.md) | Daily commands, bypasses, lifecycle hygiene, pointer to upstream docs |
| [bd-state integrity](bd-state-integrity.md) | The merge-driver + post-rewrite chain that keeps `.beads/issues.jsonl` aligned to dolt (loom-4um/yjo) |
| [MemPalace MCP tools](mempalace-mcp.md) | The 29 MCP tools by frequency tier, palace architecture vocabulary |
| [Loom env vars](loom-env-vars.md) | The harness env vars loom sets + the `LOOM_*_SKIP` bypass family |
| [Helper scripts](helper-scripts.md) | The `scripts/loom-*` helper family (fanout-detect, rebase-worktree, worktree-python, doctor, etc.) |
| [Decision tables](decision-tables.md) | Tool-selection lookups (`bd remember` vs drawer, skill vs hook, dispatch posture, design-cycle vs recipe, etc.) |
| [Glossary](glossary.md) | Term definitions (AAAK, bead, drawer, family, KG, recipe, dispatch-middle, design-a-cycle, etc.) |
| [Decision drawer scaffold (FIXME)](docs-scaffold-fixme.md) | Open scaffolding gaps tracked as FIXMEs |
| [/design-a-cycle](design-a-cycle.md) | The above-bead design-cycle orchestrator command + skill |
| [/dispatch-middle](dispatch-middle.md) | The test-author → implementer middle-dispatch pipeline command + skill |
| [Design-doc template](design-doc-template.md) | `templates/design-doc/` — the L2 design-doc drawer scaffold a cycle precipitates into |
| [upstream-a-bead](upstream-a-bead.md) | The upstream-contribution recipe (`--issue-only` / `--issue+pr` lanes) |
| [upstream:loom label](upstream-loom-label.md) | The `upstream:loom` bead-label convention + `/check-loom-upstream` sweep |
| [Downstream convention-drift detector](convention-drift-detector.md) | Manifest hash, sync stamp, SessionStart nudge, `/audit-project --check=drift` / `--apply-drift`, and the correctness gates (loom-ig3p) |

Per-hook, per-skill, per-command, and per-subagent reference pages
live under their respective subsections in the nav (and the full
verbatim source is auto-included on the catalogue pages above).
