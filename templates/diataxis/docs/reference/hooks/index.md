# Hooks

Source: `hooks/*.sh` in this repository. Each `.sh` file is one hook
script; header comments at the top of each script document its
trigger and behaviour. The list below is generated from the
filesystem at build time via `mkdocs-include-markdown`; if your
project has no `hooks/` directory, the section below renders empty.

| Field | Value |
|---|---|
| Source glob | `hooks/*.sh` |
| Discovery | Build-time, via `mkdocs-include-markdown` |

## Full text

{%
  include-markdown "../../../hooks/*.sh"
  heading-offset=1
%}
