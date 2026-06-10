#!/usr/bin/env bash
# Git pre-push hook: run `mkdocs build --strict` if the push range
# touches docs/, mkdocs.yml, or skills/. WARN-only — never blocks the
# push.
#
# Closes loom-kbo. This is the third instance in 4 days of the
# broken-markdown-link-in-docs class (loom-59w 2026-05-15,
# loom-tx7 2026-05-19) — local enforcement at push time is now
# justified to short-circuit the CI round-trip.
#
# Defense-in-depth chain (each successive layer is the safety net
# for the prior):
#   1. bd-preflight-docs-strict.sh    (bd close / bd preflight)
#   2. pre-push-mkdocs-strict.sh      (this hook — git push)
#   3. Deploy docs CI workflow         (origin / GitHub Actions)
#
# This hook is intentionally permissive: rc=0 even on strict
# failure. The dispatcher workflow MUST NOT be wedged by a transient
# docs error — a noisy WARN is sufficient to redirect attention,
# and the CI is the authoritative blocker.
#
# Contract (pinned by lib/tests/pre-push-mkdocs-strict.test.sh):
#   - Reads pre-push stdin lines: <local_ref> <local_sha> <remote_ref>
#     <remote_sha>. Multiple lines for multi-ref pushes.
#   - For each line:
#       - branch-delete (local_sha=000…) → skip the line.
#       - new-branch    (remote_sha=000…) → diff against `main`
#         (since the remote has never seen this branch).
#       - normal update → diff $remote_sha..$local_sha.
#   - If any path matches ^(docs/|mkdocs\.yml$|skills/), mark the
#     push as relevant. Process the rest of stdin for completeness,
#     then run mkdocs once at the end.
#   - On strict pass → silent exit 0.
#   - On strict fail → WARN block on stderr + exit 0.
#   - Env bypass: LOOM_PRE_PUSH_MKDOCS_SKIP=1.
#   - mkdocs binary: MKDOCS_BIN env override; falls back to `mkdocs`
#     on PATH. If not found, silent skip (graceful).

set -uo pipefail

# shellcheck source=../lib/loom-hook-helpers.sh
. "$HOME/.claude/lib/loom-hook-helpers.sh" 2>/dev/null || \
  . "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/loom-hook-helpers.sh"

if loom_env_enabled LOOM_PRE_PUSH_MKDOCS_SKIP; then
  exit 0
fi

ZERO_SHA="0000000000000000000000000000000000000000"
RELEVANT_RE='^(docs/|mkdocs\.yml$|skills/)'
# A push that adds/removes a primitive OR edits a reference index table can
# drift the docs/reference/<category>/index.md inventory tables out of sync
# with the shipped primitives — the loom-wjuo catalogue-drift class. Catch
# it here (WARN-only) via scripts/loom-docs-catalogue, loom's own check.
CATALOGUE_RE='^(skills/|commands/|agents/|hooks/|docs/reference/)'

is_relevant=0
is_catalogue_relevant=0

while read -r _local_ref local_sha _remote_ref remote_sha; do
  # Empty line (eof / extra whitespace) → skip.
  [ -z "${local_sha:-}" ] && continue

  # Branch-delete push: nothing being uploaded → skip.
  if [ "$local_sha" = "$ZERO_SHA" ]; then
    continue
  fi

  # New-branch push: remote hasn't seen this branch → fall back to
  # diff against main. If `main` doesn't resolve (rare — repo with
  # no main branch), fall back to listing all files in local_sha
  # (overly broad but safe — we'd rather invoke mkdocs once than
  # silently miss a docs change).
  if [ "$remote_sha" = "$ZERO_SHA" ]; then
    if git rev-parse --verify --quiet main >/dev/null 2>&1; then
      base="main"
    else
      base=""
    fi
  else
    base="$remote_sha"
  fi

  if [ -n "$base" ]; then
    changed=$(git diff --name-only "$base..$local_sha" 2>/dev/null) || changed=""
  else
    changed=$(git show --name-only --pretty=format: "$local_sha" 2>/dev/null) || changed=""
  fi

  if echo "$changed" | grep -qE "$RELEVANT_RE"; then
    is_relevant=1
  fi
  if echo "$changed" | grep -qE "$CATALOGUE_RE"; then
    is_catalogue_relevant=1
  fi
done

# --- Catalogue drift check (loom-wjuo) ------------------------------------
# Runs only for loom's own repo (the check + the reference tables it audits
# are loom-specific) and only when a primitive or reference page changed.
# WARN-only, like the mkdocs check below — the suite test under `script/test`
# is the hard gate; this is the push-time nudge.
if [ "$is_catalogue_relevant" = "1" ] && [ -x scripts/loom-docs-catalogue ]; then
  if ! cat_output=$(scripts/loom-docs-catalogue --check 2>&1); then
    {
      echo ""
      echo "WARN: docs reference index tables drifted from shipped primitives; push proceeding"
      echo "$cat_output" | grep -E '^(MISSING|DUPLICATE|NOINDEX|loom-docs-catalogue:)' | sed 's/^/  /'
      echo ""
      echo "  Fix docs/reference/<category>/index.md before CI, or bypass once with:"
      echo "    LOOM_PRE_PUSH_MKDOCS_SKIP=1 git push"
      echo ""
    } >&2
  fi
fi

# --- Generated per-item nav drift check (loom-itph) -----------------------
# Same relevance + loom-only guard. WARN-only; the suite test under
# `script/test` is the hard gate. Catches a primitive added/removed without
# rerunning scripts/loom-docs-gen (stale wrapper pages or nav block).
if [ "$is_catalogue_relevant" = "1" ] && [ -x scripts/loom-docs-gen ]; then
  if ! gen_output=$(scripts/loom-docs-gen --check 2>&1); then
    {
      echo ""
      echo "WARN: generated per-item nav pages/block drifted from shipped primitives; push proceeding"
      echo "$gen_output" | grep -E '^(MISSING|STALE|ORPHAN|loom-docs-gen:)' | sed 's/^/  /'
      echo ""
      echo "  Run 'scripts/loom-docs-gen' to regenerate + commit, or bypass once with:"
      echo "    LOOM_PRE_PUSH_MKDOCS_SKIP=1 git push"
      echo ""
    } >&2
  fi
fi

if [ "$is_relevant" = "0" ]; then
  exit 0
fi

# --- mkdocs binary resolution ---------------------------------------------

MKDOCS="${MKDOCS_BIN:-mkdocs}"
if [ "$MKDOCS" = "mkdocs" ]; then
  command -v mkdocs >/dev/null 2>&1 || exit 0
else
  [ -x "$MKDOCS" ] || exit 0
fi

# --- Run mkdocs --strict --------------------------------------------------

build_output=$("$MKDOCS" build --strict 2>&1)
rc=$?

if [ "$rc" -eq 0 ]; then
  exit 0
fi

# Surface the first WARNING/ERROR line for compact context.
first_problem=$(echo "$build_output" | grep -E 'WARNING|ERROR|Aborted' | head -1)

{
  echo ""
  echo "WARN: mkdocs --strict failed — broken docs link or anchor; push proceeding"
  [ -n "$first_problem" ] && echo "  $first_problem"
  echo ""
  echo "  Fix locally before CI catches it on origin, or bypass once with:"
  echo "    LOOM_PRE_PUSH_MKDOCS_SKIP=1 git push"
  echo ""
} >&2

exit 0
