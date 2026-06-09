# Claude Code hook layering

> Claude Code merges hook registrations from four configuration
> layers **additively** — the union of all four, never an override.
> Empty arrays in a lower-precedence layer do NOT cancel a
> registration inherited from a higher one. This is the empirical
> reality that `/audit-project` item 12 resolves.

## Summary

Claude Code reads hook registrations from **four** layers and fires
the **union** of every `(event, matcher, command)` tuple it finds.
There is no override semantics: a layer can only ADD tuples to the
set, never remove one another layer registered.

| Layer | Source | Scope |
| --- | --- | --- |
| Plugin | `~/.claude/plugins/cache/*/*/*/{,.claude-plugin/}plugin.json` | per-installed-plugin |
| User-global | `~/.claude/settings.json` | per-machine, all projects |
| Project-tracked | `<project>/.claude/settings.json` | per-repo, checked in |
| Project-local | `<project>/.claude/settings.local.json` | per-repo, gitignored |

If the same `(event, matcher, command)` tuple is registered in two
layers, Claude Code fires it **once per layer that registers it** —
i.e. twice. That is the duplicate-hook drift `find-hook-dups.sh`
detects and `/audit-project` item 12 reports.

## Why empty arrays don't cancel

A natural-but-wrong mitigation for a duplicate registration is to
write an empty `hooks` block (or an empty matcher array) into the
lowest-precedence layer — `.claude/settings.local.json` — expecting
it to "cancel" the inherited registration. It does not.

Because layering is a **union, not an override**, an empty array in
`settings.local.json` contributes **zero** tuples to the merged set.
The tuples registered by the plugin, the user-global file, and the
project-tracked file are all still present in the union. The empty
array changes nothing; the duplicate still fires.

This is the same shape as set union: `A ∪ B ∪ C ∪ ∅ = A ∪ B ∪ C`.
The empty layer is inert by construction.

## Verified-empirical anchor

The additive-layering behavior was verified inert on **2026-05-27**
in the **e2e-api-tests** project (loom-jnn):

- `bd prime` was registered as a `SessionStart` hook in **three**
  layers simultaneously — the plugin manifest, the user-global
  `~/.claude/settings.json`, and the project-tracked
  `<project>/.claude/settings.json`.
- An empty-array override was written into
  `<project>/.claude/settings.local.json` to try to cancel the
  registration.
- In a **fresh session**, `bd prime` still fired **3 times** during
  `SessionStart` — once per registering layer. The empty-array
  override was confirmed completely inert.

That session also captured the durable knowledge-graph fact:
`Claude Code settings hooks → merge_semantics_are → additive across
all layers` (e2e-api-tests/decisions wing, 2026-05-27).

## What actually resolves a duplicate

Since no lower layer can cancel a higher one, the only working
resolutions act on the **project-tracked** layer's own copy — and
that is exactly what `/audit-project` item 12's two AUTOFIX paths do
(the duplicate-hook **detection** mechanism, `find-hook-dups.sh`, is
unchanged — only resolution was the gap):

1. **`[AUTOFIX:dedup-hook-skip-worktree]` — the DEFAULT, per-user,
   reversible.** `git update-index --skip-worktree
   .claude/settings.json` so git stops tracking local edits to the
   shared file, then strip the duplicate stanza from the local copy.
   This never changes shared content, so it cannot break a non-loom
   dev's checkout. The skip-worktree bit also defuses the "your local
   changes would be overwritten by checkout" error a later upstream
   `git pull` would otherwise raise; the recovery snippet for that
   next pull is logged to `.claude/loom-audit-state.json`:

   ```bash
   git update-index --no-skip-worktree .claude/settings.json
   git stash
   git pull
   git stash pop
   # then re-apply skip-worktree + strip via /audit-project --apply-onboarding
   ```

2. **`[AUTOFIX:dedup-hook-commit]` — the opt-in, commit-removal
   path.** Remove the duplicate stanza from the **tracked**
   `.claude/settings.json` and commit. Because this changes shared
   content, it is gated behind an explicit y/N confirmation that
   names the consequence — `Non-loom devs lose <hook-name>
   registration. Proceed? (y/N)` — and is **never** auto-applied by
   `--apply-onboarding`.

See the `/audit-project` skill's item 12 / Step 3.5 for the full
recipe specs and gating, and the
[`project-onboarder`](subagents/index.md) subagent's item 12 scan
for how the WARN is detected and tagged.

## Sibling pattern

The two-layer **env-block** override loom propagates via item 16
(`[AUTOFIX:loom-env-block]`) is the *opposite* merge shape and worth
contrasting:

- **Env keys are scalars that OVERWRITE.** Setting
  `CLAUDE_CODE_ENABLE_TASKS=false` in the project layer replaces any
  inherited value — a deep-merge of two known keys is bit-stable, so
  it is deterministically auto-fixable.
- **Hook entries are arrays that UNION.** Adding an empty array adds
  nothing; there is no value to overwrite, so the duplicate persists.

This asymmetry is exactly why loom-7ro's pure-additive env-block
recipe worked for ENV but a parallel approach does NOT work for
HOOKS. See [Loom env vars](loom-env-vars.md) for the env-block
pattern (loom-7ro lineage).

## Lineage

loom-jnn (item 12 resolution paths). Empirically verified in
e2e-api-tests 2026-05-27 immediately after loom-7ro shipped: a fresh
SessionStart fired 3 `bd prime` registrations from the three sources
(plugin + user-global + project-tracked) regardless of any
`settings.local.json` empty-array override. Detection was already in
place via loom-ann (`find-hook-dups.sh`, 2026-05-15); loom-jnn added
the two resolution AUTOFIX paths and this reference page as the
discovery surface for future Claude Code hook-layering findings.
