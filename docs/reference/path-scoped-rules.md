# Path-scoped rules

Source: `<project>/.claude/rules/*.md` with YAML frontmatter
specifying `paths`.

A rule file auto-loads when Claude works with files matching one of
its `paths` globs. This conserves context against `CLAUDE.md` (which
loads every session regardless).

## File format

```markdown
---
paths:
  - <area>/**/*.py
description: <one-line description>
---

# <Area> discipline

(rules)
```

Length budget: ≤30 lines per rule file.

## Existing rules in HAW

| File | Paths | Captures |
|---|---|---|
| `tests.md` | `tests/**/*.py` | TDD non-negotiable + bug-class coverage rule + enshrined-test rule + lineage citation + no DB mocking |
| `engine.md` | `engine/**/*.py` | async/sync split + LLM via NarrativeBackend only + 13p.3.11 inter-bot credential rules + Postgres pool/timeout bounds + no recovery.py |
| `prompts.md` | `prompts/**/*.md` | JSON-Null Discipline (huu.15.2/0qw lineage) + bold reservation + self-check envelope + Milne voice register + gate-test round-trip |

## Adding a rule

See [How-to: add a path-scoped rule](../how-to/common-scenarios/add-path-rule.md).
