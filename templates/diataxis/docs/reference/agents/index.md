# Agents

Source: `agents/*.md` in this repository. Each `.md` file is one
subagent definition. The list below is generated from the filesystem
at build time via `mkdocs-include-markdown`; if your project has no
`agents/` directory, the section below renders empty.

| Field | Value |
|---|---|
| Source glob | `agents/*.md` |
| Discovery | Build-time, via `mkdocs-include-markdown` |

## Full text

{%
  include-markdown "../../../agents/*.md"
  heading-offset=1
%}
