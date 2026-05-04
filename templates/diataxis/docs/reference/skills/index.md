# Skills

Source: `skills/*/SKILL.md` in this repository. Each subdirectory of
`skills/` ships one `SKILL.md`. The list below is generated from the
filesystem at build time via `mkdocs-include-markdown`; if your
project has no `skills/` directory, the section below renders empty.

| Field | Value |
|---|---|
| Source glob | `skills/*/SKILL.md` |
| Discovery | Build-time, via `mkdocs-include-markdown` |

## Full text

{%
  include-markdown "../../../skills/*/SKILL.md"
  heading-offset=1
%}
