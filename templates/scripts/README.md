# `templates/scripts/` — canonical `script/` convention skeleton

The `templates/scripts/` directory is the source-of-truth canonical
skeleton for the loom **`script/` convention**: a small, fixed set of
normalized entry-point scripts every loom-managed repo carries, so a
contributor (or an automated agent, or CI) can `script/setup` and
`script/test` *any* project without learning its bespoke tooling.

The convention is loom's adaptation of GitHub's well-known "Scripts to
Rule Them All" pattern. `/audit-project` (loom-oxs.4) recognizes a
project's `script/` directory and offers to scaffold this skeleton when
it is missing.

## The 8 canonical scripts

```
script/
├── bootstrap   ← one-time machine prerequisites (toolchains, system pkgs)
├── setup       ← make a fresh checkout ready to run (install deps)
├── update      ← update an existing checkout (re-sync deps, migrate, regen)
├── server      ← start the app locally for development
├── test        ← run the fast unit suite (the canonical test command)
├── lint        ← run static analysis / style checks
├── cibuild     ← the full CI build + test pass (superset of test)
└── deploy      ← ship to the run target (image push, publish, release)
```

Convention pipeline: `bootstrap` → `setup` → (`update` on later pulls) →
`server` / `test` / `lint` during development → `cibuild` in CI →
`deploy` to ship.

## Directory naming

The directory is **`script/` (singular)** by convention — the GitHub
"scripts to rule them all" spelling. The loom recognizer also accepts
`scripts/` (plural) for projects that already use that name; new
projects should prefer the singular `script/`.

## What ships, and the not-implemented default

Every script ships as an **unedited stub** that, as shipped, does
exactly two things: echoes a clear "not implemented for this project"
message **to stderr**, and **exits non-zero (code 2)**. This is
deliberate — a half-wired project must fail loudly rather than let a
green `script/test` mean "no tests ran". The stub keeping stdout clean
(message on stderr only) means any adopter or CI step that parses a
script's stdout is not polluted by the placeholder text.

Each stub also carries **per-type comment hints** — a commented line
each for Go, Python, Node, and bash — that the adopter uncomments and
adapts. For example `script/test` ships:

```bash
#   # Go:     go test ./...
#   # Python: python -m pytest
#   # Node:   npm test
#   # bash:   bash lib/tests/*.test.sh
```

The hints are tailored per script (`setup` hints at dependency install
per type; `lint` hints at the linter per type; and so on).

## Adopting the skeleton

Copy the eight scripts into the target project's `script/` directory and
make them executable:

```bash
TARGET=/path/to/project
mkdir -p "$TARGET/script"
cp templates/scripts/bootstrap templates/scripts/setup \
   templates/scripts/update    templates/scripts/server \
   templates/scripts/test      templates/scripts/lint \
   templates/scripts/cibuild   templates/scripts/deploy \
   "$TARGET/script/"
chmod +x "$TARGET/script/"*
```

Then, per script, either:

1. **Wire it up** — uncomment the comment hint matching the project's
   stack, adapt it to the real command, and delete the `exit 2`
   placeholder body. Or
2. **Mark it N/A** — for a script that genuinely does not apply (the
   textbook case is `script/server` in a library: there is nothing to
   serve), downgrade the body to:

   ```bash
   echo "server: N/A for this project type"
   exit 0
   ```

   The N/A downgrade (`exit 0`) is the **adopter's edit**, never the
   shipped default. Shipping `exit 0` by default would let an
   unconfigured project look healthy; shipping `exit 2` forces a
   conscious choice — wire it up, or explicitly declare it N/A.

This `README.md` is documentation for the maintainer adopting the
convention. Delete it from the target's `script/` directory after
copying (or leave it as a crib sheet — it does nothing at runtime).

## Acceptance test

`lib/tests/scripts-template.test.sh` pins the invariant: all 8 scripts
present, each executable + shell-shebanged, each unedited stub exits 2
with a "not implemented" message on stderr (and nothing on stdout), and
each carries all four per-type comment hints. It also runs a negative
self-check — a synthetic skeleton missing a script is flagged — so the
all-present comparator can't rot to a vacuous no-op.

Run: `bash lib/tests/scripts-template.test.sh`

## Lineage

- Design: `loom/decisions` — the **loom-adm `script/`-convention
  drawer** (Q1 the 8-script set, Q2 the no-op / exit-2 semantics, Q4 the
  templates, Q5 the singular `script/` naming).
- Recognizer + scaffold consumer: loom-oxs.4 (`/audit-project` `script/`
  recognition + scaffold + `.deploy` migration).
- Deploy hint lineage: loom-0k0 (`workflow.json .deploy` surfaced at
  wrap-up) — `script/deploy` is the home for what `.deploy` points at.
