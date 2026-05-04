# `templates/diataxis/` — canonical Diataxis skeleton

This directory is the source-of-truth canonical Diataxis docs skeleton
that `/docs-scaffold` (loom-km8.2) copies into a target project. It is
also reusable directly: a maintainer can copy + substitute by hand
without invoking the slash command.

## What ships here

```
templates/diataxis/
├── README.md                                   ← this file
├── README.docs-pointer.md.template             ← snippet to splice into project README
├── mkdocs.yml.template                         ← MkDocs Material site config
├── requirements.txt                            ← pinned mkdocs deps
├── .github/workflows/docs.yml                  ← GitHub Pages publish workflow
└── docs/
    ├── index.md.template                       ← Material grid-cards landing
    ├── tutorials/
    │   ├── index.md                            ← orientation copy (verbatim)
    │   └── getting-started.md.template         ← Sequin-style thin tutorial
    ├── how-to/
    │   ├── index.md
    │   └── install.md.template
    ├── reference/
    │   ├── index.md
    │   ├── skills/index.md                     ← include-markdown glob over skills/
    │   ├── commands/index.md                   ← glob over commands/
    │   ├── agents/index.md                     ← glob over agents/
    │   └── hooks/index.md                      ← glob over hooks/
    └── explanation/
        ├── index.md
        └── mental-model.md.template
```

Files ending `.template` get variable substitution at scaffold time.
Files without the suffix copy verbatim.

## Variables

| Token | Replace with | Example |
|---|---|---|
| `{{ project_name }}` | The MkDocs `site_name` and surface label for the project | `acme-widgets` |
| `{{ repo_url }}` | HTTPS URL of the repository | `https://github.com/acme/widgets` |
| `{{ short_description }}` | One-line project description for the landing page | `Widget orchestration for the Acme platform.` |

## Substitution mechanism

The reference implementation is a four-line bash pass — no Python, no
external scaffold tool. `/docs-scaffold` (loom-km8.2) wraps this with
preview + per-file approval, but the underlying mechanic is portable:

```bash
TARGET=/path/to/project
PROJECT_NAME="acme-widgets"
REPO_URL="https://github.com/acme/widgets"
SHORT_DESCRIPTION="Widget orchestration for the Acme platform."

cp -r templates/diataxis/. "$TARGET/"

# substitute placeholders
find "$TARGET" -type f -exec sed -i \
  -e "s|{{ project_name }}|$PROJECT_NAME|g" \
  -e "s|{{ repo_url }}|$REPO_URL|g" \
  -e "s|{{ short_description }}|$SHORT_DESCRIPTION|g" \
  {} +

# rename *.template -> *
find "$TARGET" -type f -name '*.template' \
  -exec sh -c 'mv "$1" "${1%.template}"' _ {} \;
```

Choice rationale: `sed` keeps the substitution legible and works without
extra dependencies (loom is mostly markdown + bash + JSON; Python is out
of scope per `CLAUDE.md`). The `{{ token }}` shape was kept (over `$VAR`
+ `envsubst`) because it survives shell-quoting hazards in the template
files themselves and reads naturally to humans editing the templates.

## Acceptance test

`lib/tests/diataxis-template.test.sh` exercises the substitution + build
end-to-end: copies this directory into a tmp dir, runs the substitution
above, then runs `mkdocs build --strict`. The test asserts the build
succeeds, no `{{ ... }}` placeholders survive, and each quadrant
`index.md` carries non-empty Diataxis-discipline orientation copy
(R1 F3 anti-empty-stubs guard).

Run: `bash lib/tests/diataxis-template.test.sh`

## Lineage

- Design: `loom/decisions` drawer **DIATAXIS-FOR-MANAGED-PROJECTS — D1
  PLAN (loom-9z1.10)** — sign-off 2026-05-04.
- Phase-1 dogfood: loom's own `docs/` (loom-9z1.2 / loom-9z1.7), the
  reusable bones this skeleton lifts.
- R1 source: `loom/decisions` drawer **DIATAXIS DISCIPLINE — R1
  RESEARCH OUTPUT** — Procida verbatim + 10 fail patterns + the C1–C6
  loom accommodations.
