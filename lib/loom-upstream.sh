#!/usr/bin/env bash
# loom-upstream.sh — clone-cache helper for the upstream-a-bead recipe.
#
# Consumed by the recipe at M2 (cloning). Manages a central upstream
# cache under `~/.loom/upstream/<owner>/<repo>/` shared across all
# loom-managed projects, so we don't re-clone an upstream five times
# if five projects file PRs against it.
#
# Design source: drawer_loom_decisions_a6e64f9cfb21a9d16fc47604
# (loom/decisions wing, 2026-05-27). Tracks loom-k2g.2.
#
# Conventions:
#   - Single-purpose functions; this file is sourced, not executed.
#   - Sourcing the library has NO side effects.
#   - LOOM_HOME defaults to $HOME/.loom; tests can override.
#   - Owner/repo nesting handles collisions between repos sharing a
#     name (e.g. two different `beads` repos).
#
# Functions exported:
#   ensure_clone <owner> <repo>
#       Auto-clones via `gh repo clone` if the cache dir is absent.
#       No-op when present. Exits non-zero on clone failure.
#
#   gh_auth_check
#       Wraps `gh auth status`. Returns 1 with an error message if
#       gh is not authenticated.
#
#   canonical_owner_check <owner> <repo>
#       `gh repo view <owner>/<repo> --json owner` and compares the
#       returned login against the caller's <owner>. On mismatch
#       (loom-45i precedent: gastownhall vs steveyegge), warns on
#       stderr and prints the canonical owner to stdout for the
#       caller to consume. Returns 0 in both match and mismatch
#       cases — mismatch is a warning, not a fatal error.
#
#   fork_or_create <owner> <repo>
#       Detects the current gh user's fork via `gh repo view
#       <user>/<repo>`. If absent, runs `gh repo fork <owner>/<repo>
#       --remote=false` (recipe owns the explicit remote add).
#
#   refuse_if_stale <clone-path>
#       Refuses (returns non-zero) if the clone has uncommitted
#       changes (`git status --porcelain` non-empty) OR any local
#       branch carries commits not present on a remote (unpushed
#       work). Emits a refusal message naming the staleness
#       condition.

# Intentionally NO `set -euo pipefail` at sourcing time — callers
# manage their own shell options. Functions use explicit returns.

# Resolve the cache root. Tests override LOOM_HOME to isolate.
_loom_upstream_root() {
  echo "${LOOM_HOME:-$HOME/.loom}/upstream"
}

# ---------------------------------------------------------------------
# ensure_clone <owner> <repo>
# ---------------------------------------------------------------------
ensure_clone() {
  local owner="$1"
  local repo="$2"
  local root dest
  root=$(_loom_upstream_root)
  dest="$root/$owner/$repo"

  if [ -d "$dest" ]; then
    return 0
  fi

  mkdir -p "$root/$owner" || {
    echo "ensure_clone: cannot create cache parent $root/$owner" >&2
    return 1
  }

  # `gh repo clone <owner>/<repo> <dest>` — gh handles auth + URL
  # resolution. The recipe layer should have run gh_auth_check first.
  if ! gh repo clone "$owner/$repo" "$dest"; then
    echo "ensure_clone: gh repo clone $owner/$repo failed" >&2
    return 1
  fi

  return 0
}

# ---------------------------------------------------------------------
# gh_auth_check
# ---------------------------------------------------------------------
gh_auth_check() {
  if ! gh auth status >/dev/null 2>&1; then
    echo "gh_auth_check: gh is not authenticated — run 'gh auth login' before invoking upstream-a-bead" >&2
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------
# canonical_owner_check <owner> <repo>
# ---------------------------------------------------------------------
canonical_owner_check() {
  local owner="$1"
  local repo="$2"
  local json canonical

  # `gh repo view <owner>/<repo> --json owner` returns
  # {"owner":{"login":"<canonical>"}}. gh follows redirects, so a
  # transferred-ownership repo resolves to its new owner.
  if ! json=$(gh repo view "$owner/$repo" --json owner 2>/dev/null); then
    echo "canonical_owner_check: gh repo view $owner/$repo failed — repo may not exist or auth missing" >&2
    return 1
  fi

  # Parse {"owner":{"login":"<value>"}} without jq dependency. The gh
  # JSON output is stable enough for a regex extraction here; tests
  # exercise the exact shape.
  canonical=$(echo "$json" | sed -n 's/.*"login":"\([^"]*\)".*/\1/p')

  if [ -z "$canonical" ]; then
    echo "canonical_owner_check: could not parse owner from gh JSON: $json" >&2
    return 1
  fi

  if [ "$canonical" != "$owner" ]; then
    echo "canonical_owner_check: WARNING — $owner/$repo canonical owner is '$canonical', not '$owner'. Switching to '$canonical' (loom-45i precedent: e.g. gastownhall → steveyegge)." >&2
    echo "$canonical"
    return 0
  fi

  return 0
}

# ---------------------------------------------------------------------
# fork_or_create <owner> <repo>
# ---------------------------------------------------------------------
fork_or_create() {
  local owner="$1"
  local repo="$2"
  local user_json user

  if ! user_json=$(gh api user 2>/dev/null); then
    echo "fork_or_create: gh api user failed — auth missing?" >&2
    return 1
  fi
  user=$(echo "$user_json" | sed -n 's/.*"login":"\([^"]*\)".*/\1/p')

  if [ -z "$user" ]; then
    echo "fork_or_create: could not extract user login from gh api user JSON: $user_json" >&2
    return 1
  fi

  # Probe for existing fork. `gh repo view <user>/<repo>` succeeds if
  # the fork exists (or any repo by that name under the user); fails
  # otherwise.
  if gh repo view "$user/$repo" >/dev/null 2>&1; then
    return 0
  fi

  # Create the fork without auto-adding a remote — the recipe layer
  # adds it explicitly as `fork` so PR push targets are unambiguous.
  if ! gh repo fork "$owner/$repo" --remote=false; then
    echo "fork_or_create: gh repo fork $owner/$repo --remote=false failed" >&2
    return 1
  fi

  return 0
}

# ---------------------------------------------------------------------
# refuse_if_stale <clone-path>
# ---------------------------------------------------------------------
refuse_if_stale() {
  local clone="$1"

  if [ ! -d "$clone/.git" ] && ! git -C "$clone" rev-parse --git-dir >/dev/null 2>&1; then
    echo "refuse_if_stale: $clone is not a git repository" >&2
    return 1
  fi

  # Uncommitted changes (staged, unstaged, or untracked).
  local porcelain
  porcelain=$(git -C "$clone" status --porcelain 2>/dev/null)
  if [ -n "$porcelain" ]; then
    echo "refuse_if_stale: $clone has uncommitted changes — clean the cache before reuse:" >&2
    echo "$porcelain" | sed 's/^/  /' >&2
    return 1
  fi

  # Unpushed commits on any local branch. A branch with no upstream
  # tracking ref OR with commits ahead of its upstream counts as
  # stale work that the next recipe run would inherit.
  local unpushed
  unpushed=$(git -C "$clone" for-each-ref --format='%(refname:short) %(upstream:short) %(upstream:track)' refs/heads 2>/dev/null \
    | while read -r branch upstream track; do
        if [ -z "$upstream" ]; then
          echo "$branch (no upstream)"
        elif echo "$track" | grep -q "ahead"; then
          echo "$branch ($track)"
        fi
      done)

  if [ -n "$unpushed" ]; then
    echo "refuse_if_stale: $clone has unpushed branches — push or delete before reuse:" >&2
    echo "$unpushed" | sed 's/^/  /' >&2
    return 1
  fi

  return 0
}
