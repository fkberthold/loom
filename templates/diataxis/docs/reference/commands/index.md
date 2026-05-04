# Commands

Source: `commands/*.md` in this repository. Each `.md` file is one
slash command. The list below is generated from the filesystem at
build time via `mkdocs-include-markdown`; if your project has no
`commands/` directory, the section below renders empty.

| Field | Value |
|---|---|
| Source glob | `commands/*.md` |
| Discovery | Build-time, via `mkdocs-include-markdown` |

## Full text

{%
  include-markdown "../../../commands/*.md"
  heading-offset=1
%}
