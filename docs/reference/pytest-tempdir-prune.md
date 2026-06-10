# pytest-tempdir-prune hook

> SessionStart housekeeping hook that prunes STALE, project-scoped
> pytest temp dirs (`./tmp/pytest-of-*` older than 24h) so they stop
> accumulating and eating drive space. Non-blocking; always exits 0.

## Why this exists

Closes loom-skxj. pytest writes each test run's temp tree under
`<basetemp>/pytest-of-<user>/...`. Projects that point pytest's
basetemp at `./tmp/` — or that simply collect temps there — end up
with a `./tmp/pytest-of-<user>/` directory that nothing ever reaps.
Origin: a project whose `./tmp/pytest-of-frank` had grown huge.

The fix ships **two complementary pieces**:

- **PRUNE** (this hook) — a SessionStart sweep that removes the stale
  accumulation for projects that have not adopted the retention config
  yet, or for temps that predate it.
- **PREVENT** (the durable root-cause fix) — pytest's own retention
  config, documented [below](#prevent-the-durable-root-cause-fix). The
  recommended posture is to adopt the retention config AND keep the
  prune as a backstop sweep.

## What the hook prunes

On session start, for the current working directory:

1. `LOOM_PYTEST_TEMPDIR_PRUNE_SKIP=1` (literal "1") → exit 0 (no-op).
2. No `./tmp/` directory → exit 0 (no-op).
3. Otherwise, remove every entry that is **all** of:
   - a **direct child** of the cwd-relative `./tmp/` (`-maxdepth 1`),
   - whose basename matches **`pytest-of-*`** (`-name`),
   - that is a **directory** (`-type d`),
   - older than **24h** (`-mtime +1`).

The single `find` it runs:

```bash
find ./tmp -maxdepth 1 -name 'pytest-of-*' -type d -mtime +1 -exec rm -rf {} +
```

## Scope guard — why it cannot escape `./tmp/`

The scope is **strictly project-relative** and **deliberately narrow**.
The hook never touches:

| NOT touched | Why |
|---|---|
| `/tmp/pytest-of-$USER` and anything under the system `/tmp` | the `find` base is the relative `./tmp`, never `/tmp` — it is project-scoped, not machine-global |
| `./pytest-of-*` sitting in the project root (outside `./tmp/`) | only `./tmp/`'s children are scanned |
| `./tmp/keepme/`, `./tmp/notpytest`, any non-`pytest-of-*` sibling | excluded by `-name 'pytest-of-*'` (and `-type d`) |
| `./tmp/sub/pytest-of-deep` (nested below a direct child) | excluded by `-maxdepth 1` — only direct children of `./tmp/` |
| a fresh (`<24h`) `./tmp/pytest-of-*` from the current session | excluded by `-mtime +1`; the hook never races a just-started run |

The relative `./tmp` base + `-maxdepth 1` together make it
structurally impossible to reach the system `/tmp`, the project root,
or any nested subtree. The fixture suite asserts each of these
survivors explicitly (cases 4, 4b, 4c).

## Posture — non-blocking, always exit 0

This is a loom housekeeping hook (the same posture as
`context-budget-sensor.sh` and `worktree-bg-inventory.sh`). It
**NEVER blocks session start** and **NEVER emits blocking JSON**.
Every path exits 0 — absent `./tmp`, no matches, opt-out, or a
successful prune. A `find`/`rm` error (e.g. a permissions hiccup) is
swallowed (fail-open) so it can never wedge a session.

## Opt-out

```bash
LOOM_PYTEST_TEMPDIR_PRUNE_SKIP=1
```

Per the loom-b1l literal-"1" convention: `=yes`, `=true`, `=0`,
empty, and other truthy-looking values are all rejected — only the
literal `1` opts out. Set it when a project intentionally retains its
`./tmp/pytest-of-*` trees (e.g. for post-mortem inspection of an old
failing run).

## PREVENT — the durable root-cause fix

The non-destructive root fix is **pytest's own retention config**.
Downstream pytest projects should set, in `pyproject.toml`:

```toml
[tool.pytest.ini_options]
tmp_path_retention_count = 1
tmp_path_retention_policy = "failed"
```

- `tmp_path_retention_count = 1` — keep only the most recent run's
  temp tree per worker, not an unbounded pile.
- `tmp_path_retention_policy = "failed"` — keep temps only for
  **failed** runs (the ones worth inspecting); passing-run temps are
  removed automatically.

Together these keep `./tmp/pytest-of-*` from accumulating in the first
place, so the prune hook becomes a backstop rather than the primary
defense. Adopting the retention config is the recommended complement
to (not a replacement for) this hook: the config prevents new
accumulation, the hook reaps anything that predates it or was written
without it.

## Files

- Hook: `hooks/pytest-tempdir-prune.sh`
- Tests: `lib/tests/pytest-tempdir-prune.test.sh` (13 fixture cases)
- Registration: `settings.snippet.json` → `SessionStart` (wired into
  `~/.claude/settings.json` by `install.sh`'s snippet merge; the hook
  file itself is symlinked by install.sh's `hooks/*.sh` loop)

## Lineage

- Closes loom-skxj (feature)
- Literal-"1" opt-out convention: loom-b1l / loom-0hi
- Housekeeping-hook posture precedent: `worktree-bg-inventory.sh`
  (loom-z3m.7), `context-budget-sensor.sh`
- Possible follow-up: an `/audit-project` check that nudges downstream
  pytest projects to adopt the retention config above (not in scope
  for loom-skxj — PREVENT is kept at the doc level here).
