#!/usr/bin/env bash
# loom install.sh — symlink loom's files into ~/.claude/ and merge
# settings.snippet.json into ~/.claude/settings.json.
#
# Idempotent: re-running is safe. Existing files at the install paths
# are backed up (suffixed .pre-loom.bak) only on FIRST install; on
# subsequent runs the symlinks are reset but backups aren't re-created.
#
# Usage:
#   ./install.sh                    # install (default)
#   ./install.sh --check            # report what WOULD be done; no changes
#   ./install.sh --check-invocable  # verify shipped primitives are symlinked
#
# `--check-invocable` is a POST-INSTALL verification pass (no mutation):
# it asserts every shipped primitive (skills/*/SKILL.md, commands/*.md,
# agents/*.md, hooks/*.sh) has a LIVE ~/.claude/ symlink resolving back
# to the repo file, and exits NON-ZERO naming any un-invocable primitive
# (loom-7f3). It catches the "shipped but not invocable" gap — a
# primitive merged into the repo but never symlinked because install.sh
# was not re-run (observed for upstream-a-bead, loom-k2g.7). Distinct
# from `--check`, which is a dry-run PREVIEW of the install itself.
#
# Run from the loom repo root.

set -euo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
DRY_RUN=0
CHECK_INVOCABLE=0

case "${1:-}" in
  --check) DRY_RUN=1 ;;
  --check-invocable) CHECK_INVOCABLE=1 ;;
esac

log() { echo "[loom-install] $*"; }
do_or_print() {
  if [ "$DRY_RUN" = "1" ]; then
    echo "  WOULD: $*"
  else
    eval "$*"
  fi
}

# Refuse to run from a linked worktree (loom-cuk). install.sh resolves
# LOOM_ROOT from BASH_SOURCE; when invoked at .worktrees/<id>/install.sh
# every `ln -s` bakes the worktree path as the symlink target. After the
# worktree is cleaned up post-merge, every ~/.claude/ symlink dangles at
# once (observed 2026-05-26: 95 dangling after loom-yjo cleanup).
#
# Detection: when LOOM_ROOT is inside a git checkout, compare it to the
# git-common-dir's parent directory. They match iff LOOM_ROOT is the
# main working tree. (`git-common-dir` always points at the shared
# admin dir, regardless of which worktree you're in; its parent is the
# main checkout's toplevel.)
#
# Falls through silently (no refusal) when:
#   - LOOM_ROOT is outside any git checkout (no git context to evaluate)
#   - The user sets LOOM_INSTALL_FROM_WORKTREE=1 (escape hatch for the
#     rare case where install-from-worktree is intentional)
#
# Backstop: scripts/loom-doctor (loom-cuk M5) reports already-dangling
# ~/.claude/ symlinks even when prevention slipped (e.g. older worktree
# installs from before this guard landed).
if [ "${LOOM_INSTALL_FROM_WORKTREE:-0}" != "1" ]; then
  if _loom_top=$(git -C "$LOOM_ROOT" rev-parse --show-toplevel 2>/dev/null) \
     && _loom_common=$(git -C "$LOOM_ROOT" rev-parse --git-common-dir 2>/dev/null); then
    # git-common-dir may be relative — anchor to LOOM_ROOT.
    case "$_loom_common" in
      /*) ;;
      *) _loom_common="$LOOM_ROOT/$_loom_common" ;;
    esac
    _loom_common=$(cd "$(dirname "$_loom_common")" && pwd)/$(basename "$_loom_common")
    _loom_main=$(dirname "$_loom_common")
    # Normalize both via realpath so symlinks (e.g. /home -> /Users on
    # mac) don't cause spurious mismatch.
    _loom_top_real=$(realpath "$_loom_top" 2>/dev/null || echo "$_loom_top")
    _loom_main_real=$(realpath "$_loom_main" 2>/dev/null || echo "$_loom_main")
    if [ "$_loom_top_real" != "$_loom_main_real" ]; then
      echo "[loom-install] ERROR: install.sh must be run from the main loom checkout, not a linked worktree." >&2
      echo "[loom-install]   current (worktree): $_loom_top_real" >&2
      echo "[loom-install]   main checkout:      $_loom_main_real" >&2
      echo "[loom-install]" >&2
      echo "[loom-install] Running from a worktree bakes the worktree path into every" >&2
      echo "[loom-install] ~/.claude/ symlink; post-merge worktree cleanup orphans them" >&2
      echo "[loom-install] all at once. Cd to the main checkout and re-run:" >&2
      echo "[loom-install]" >&2
      echo "[loom-install]   cd $_loom_main_real && ./install.sh${DRY_RUN:+ --check}" >&2
      echo "[loom-install]" >&2
      echo "[loom-install] (Override with LOOM_INSTALL_FROM_WORKTREE=1 if this is intentional.)" >&2
      exit 1
    fi
    unset _loom_top _loom_common _loom_main _loom_top_real _loom_main_real
  fi
fi

# Sanity check: are we in the loom repo?
for required in skills/bugfix-a-bead/SKILL.md hooks/bd-claim-research.sh settings.snippet.json; do
  if [ ! -f "$LOOM_ROOT/$required" ]; then
    echo "[loom-install] ERROR: not in loom repo root (missing $required)" >&2
    exit 1
  fi
done

# --check-invocable: post-install verification, NO mutation (loom-7f3).
#
# Assert that every shipped primitive has a LIVE ~/.claude/ symlink
# resolving back to the repo file it ships from. Catches the
# "shipped but not invocable" gap (loom-k2g.7): a skill/command/agent/
# hook can be merged into the repo yet never become invocable because
# install.sh was not re-run, leaving no symlink under $CLAUDE_HOME.
#
# Verifies the same four primitive categories install.sh symlinks as
# directly-invocable Claude Code primitives: skills/*/SKILL.md,
# commands/*.md, agents/*.md, hooks/*.sh. (lib/, lib/tests/, scripts/
# are support files, not user-invocable primitives, so they're out of
# scope for the invocability assertion.)
#
# A primitive is INVOCABLE iff $CLAUDE_HOME/<rel> exists, is a symlink,
# AND resolves (the link target exists) back to $LOOM_ROOT/<rel>. A
# missing link, a non-symlink shadowing the path, a dangling link, or a
# link pointing elsewhere all count as un-invocable. Each failure is
# named on stderr; the pass exits non-zero if any primitive failed,
# else 0. No files are created, removed, or modified.
if [ "$CHECK_INVOCABLE" = "1" ]; then
  log "Invocability check (--check-invocable): verifying ~/.claude symlinks"
  log "  loom root:    $LOOM_ROOT"
  log "  check under:  $CLAUDE_HOME"
  echo ""

  inv_fail=0
  inv_checked=0

  # assert_invocable <relpath-in-loom> <relpath-in-claude-home> <label>
  assert_invocable() {
    local src_rel="$1" dst_rel="$2" label="$3"
    local src="$LOOM_ROOT/$src_rel"
    local dst="$CLAUDE_HOME/$dst_rel"
    inv_checked=$((inv_checked + 1))

    if [ ! -L "$dst" ]; then
      if [ -e "$dst" ]; then
        echo "[loom-install] UN-INVOCABLE: $label '$src_rel' — $dst_rel exists but is NOT a symlink" >&2
      else
        echo "[loom-install] UN-INVOCABLE: $label '$src_rel' — no symlink at $dst_rel (shipped but not invocable)" >&2
      fi
      inv_fail=1
      return
    fi

    # Symlink exists. Must resolve (target present) AND point at our src.
    if [ ! -e "$dst" ]; then
      echo "[loom-install] UN-INVOCABLE: $label '$src_rel' — symlink at $dst_rel is BROKEN (target missing: $(readlink "$dst"))" >&2
      inv_fail=1
      return
    fi

    local target target_real src_real
    target="$(readlink "$dst")"
    target_real="$(realpath "$dst" 2>/dev/null || echo "$target")"
    src_real="$(realpath "$src" 2>/dev/null || echo "$src")"
    if [ "$target_real" != "$src_real" ]; then
      echo "[loom-install] UN-INVOCABLE: $label '$src_rel' — symlink at $dst_rel resolves to '$target_real', not '$src_real'" >&2
      inv_fail=1
    fi
  }

  for f in "$LOOM_ROOT"/skills/*/SKILL.md; do
    [ -e "$f" ] || continue
    rel="${f#"$LOOM_ROOT"/}"
    assert_invocable "$rel" "$rel" "skill"
  done

  for f in "$LOOM_ROOT"/commands/*.md; do
    [ -e "$f" ] || continue
    name=$(basename "$f")
    assert_invocable "commands/$name" "commands/$name" "command"
  done

  for f in "$LOOM_ROOT"/agents/*.md; do
    [ -e "$f" ] || continue
    name=$(basename "$f")
    assert_invocable "agents/$name" "agents/$name" "agent"
  done

  for f in "$LOOM_ROOT"/hooks/*.sh; do
    [ -e "$f" ] || continue
    name=$(basename "$f")
    assert_invocable "hooks/$name" "hooks/$name" "hook"
  done

  echo ""
  if [ "$inv_fail" = "0" ]; then
    log "Invocability check PASSED: all $inv_checked shipped primitives are symlinked + live."
    exit 0
  else
    log "Invocability check FAILED: one or more shipped primitives are NOT invocable (see above)."
    log "  Re-run ./install.sh to (re)create the missing symlinks."
    exit 1
  fi
fi

log "loom root:    $LOOM_ROOT"
log "install into: $CLAUDE_HOME"
[ "$DRY_RUN" = "1" ] && log "(dry-run mode — no changes)"
echo ""

# Ensure target directories exist.
for d in skills agents commands hooks lib lib/tests scripts; do
  if [ ! -d "$CLAUDE_HOME/$d" ]; then
    do_or_print "mkdir -p '$CLAUDE_HOME/$d'"
  fi
done

# install_link <relpath-in-loom> <relpath-in-claude-home>
# - if target exists and is NOT a symlink: back up to .pre-loom.bak (once)
# - if target is a symlink already: replace it
# - then symlink target → loom source
install_link() {
  local src_rel="$1"
  local dst_rel="$2"
  local src="$LOOM_ROOT/$src_rel"
  local dst="$CLAUDE_HOME/$dst_rel"

  if [ ! -e "$src" ]; then
    log "SKIP (source missing): $src_rel"
    return 0
  fi

  # Ensure parent dir exists (per-skill subdirs aren't pre-created above).
  local dst_parent
  dst_parent="$(dirname "$dst")"
  if [ ! -d "$dst_parent" ]; then
    do_or_print "mkdir -p '$dst_parent'"
  fi

  if [ -L "$dst" ]; then
    # Already a symlink. Reset it.
    do_or_print "rm '$dst'"
  elif [ -e "$dst" ]; then
    # Real file — back up if no backup exists yet.
    if [ ! -e "$dst.pre-loom.bak" ]; then
      do_or_print "mv '$dst' '$dst.pre-loom.bak'"
      log "  backed up existing $dst_rel → ${dst_rel}.pre-loom.bak"
    else
      do_or_print "rm '$dst'"
    fi
  fi

  do_or_print "ln -s '$src' '$dst'"
  log "  linked $dst_rel → loom/$src_rel"
}

# Prune dangling loom-owned symlinks (orphans from renamed/deleted
# loom files). Walks ~/.claude/{skills,agents,commands,hooks,lib,scripts}/
# symlinks; removes those whose target points into $LOOM_ROOT/ but
# the source file no longer exists. Preserves .pre-loom.bak files
# (regular files; the -type l filter excludes them).
log "Pruning dangling loom-owned symlinks..."
for dir in skills agents commands hooks lib scripts; do
  [ -d "$CLAUDE_HOME/$dir" ] || continue
  find "$CLAUDE_HOME/$dir" -maxdepth 3 -type l 2>/dev/null | while read -r link; do
    target=$(readlink "$link")
    case "$target" in
      "$LOOM_ROOT"/*)
        if [ ! -e "$target" ]; then
          do_or_print "rm '$link'"
          log "  pruned dangling: $link"
        fi
        ;;
    esac
  done
done

log "Linking skills..."
for f in "$LOOM_ROOT"/skills/*/SKILL.md; do
  rel="${f#$LOOM_ROOT/}"
  install_link "$rel" "$rel"
done

log "Linking agents..."
for f in "$LOOM_ROOT"/agents/*.md; do
  name=$(basename "$f")
  install_link "agents/$name" "agents/$name"
done

log "Linking commands..."
for f in "$LOOM_ROOT"/commands/*.md; do
  name=$(basename "$f")
  install_link "commands/$name" "commands/$name"
done

log "Linking hooks..."
# install_link symlinks each hook back into the loom repo, so any
# in-file convention rides along automatically — e.g. the fail-open
# `command -v bd || exit 0` guard on the PURELY-bd subset
# (bd-prime-wrapper, post-rewrite, bd-worktree-preseed, git-push-bd-sync;
# loom-svcj) is shipped as part of the source file, not templated here.
# Hooks that also do non-bd work (pre-push-mkdocs-strict,
# bd-preflight-docs-strict, edit-after-failure-guard, cwd-drift-guard)
# deliberately do NOT carry that guard.
for f in "$LOOM_ROOT"/hooks/*.sh; do
  name=$(basename "$f")
  install_link "hooks/$name" "hooks/$name"
done

log "Linking lib..."
for f in "$LOOM_ROOT"/lib/*.sh; do
  name=$(basename "$f")
  install_link "lib/$name" "lib/$name"
done

log "Linking lib/tests..."
if [ -d "$LOOM_ROOT/lib/tests" ]; then
  for f in "$LOOM_ROOT"/lib/tests/*; do
    [ -e "$f" ] || continue
    name=$(basename "$f")
    install_link "lib/tests/$name" "lib/tests/$name"
  done
fi

log "Linking scripts..."
for f in "$LOOM_ROOT"/scripts/*; do
  name=$(basename "$f")
  install_link "scripts/$name" "scripts/$name"
done

# Make sure scripts + hooks are executable.
if [ "$DRY_RUN" = "0" ]; then
  chmod +x "$LOOM_ROOT"/hooks/*.sh "$LOOM_ROOT"/scripts/* "$LOOM_ROOT"/install.sh "$LOOM_ROOT"/uninstall.sh 2>/dev/null || true
fi

# Merge settings.snippet.json into ~/.claude/settings.json.
log ""
log "Settings.json merge:"
SETTINGS="$CLAUDE_HOME/settings.json"
SNIPPET="$LOOM_ROOT/settings.snippet.json"

if [ ! -f "$SETTINGS" ]; then
  log "  $SETTINGS does not exist — creating from snippet."
  do_or_print "cp '$SNIPPET' '$SETTINGS'"
else
  if [ "$DRY_RUN" = "1" ]; then
    log "  WOULD: merge $SNIPPET into $SETTINGS (additive; preserves existing keys)"
  else
    # Back up existing settings once.
    if [ ! -e "$SETTINGS.pre-loom.bak" ]; then
      cp "$SETTINGS" "$SETTINGS.pre-loom.bak"
      log "  backed up existing settings.json → settings.json.pre-loom.bak"
    fi

    # Merge using python (jq could also do this; python is more universally available).
    python3 - <<EOF
import json, sys
with open("$SETTINGS") as f:
    cur = json.load(f)
with open("$SNIPPET") as f:
    snip = json.load(f)
snip.pop("_comment", None)

# Deep-merge permissions.allow (union of lists).
if "permissions" in snip:
    cur.setdefault("permissions", {})
    cur_allow = set(cur["permissions"].get("allow", []))
    snip_allow = set(snip["permissions"].get("allow", []))
    cur["permissions"]["allow"] = sorted(cur_allow | snip_allow)

# Replace hooks.PreToolUse[matcher=Bash] and hooks.SessionStart with snippet versions
# (loom owns these specific stanzas).
if "hooks" in snip:
    cur.setdefault("hooks", {})
    cur["hooks"]["PreToolUse"] = snip["hooks"]["PreToolUse"]
    cur["hooks"]["SessionStart"] = snip["hooks"]["SessionStart"]

# Replace statusLine with snippet version (loom owns it).
if "statusLine" in snip:
    cur["statusLine"] = snip["statusLine"]

with open("$SETTINGS", "w") as f:
    json.dump(cur, f, indent=2)
    f.write("\n")
EOF
    log "  merged settings.snippet.json into settings.json"
  fi
fi

# Merge loom's canonical env block into <loom_root>/.claude/settings.json
# (loom-7ro). The harness ships two competing defaults that loom rules
# explicitly counter:
#   - CLAUDE_CODE_ENABLE_TASKS=false — silence the TaskCreate/TodoWrite
#     nudges (upstream #26038, #45986); loom rules require bd, not Tasks.
#   - CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 — disable the auto-spawned
#     MEMORY.md / bd remember surrogate (upstream #23544, #23750); loom
#     rules require bd remember + MemPalace, not MEMORY.md.
#
# Project-level, not user-global: targets the loom repo's own
# .claude/settings.json (and, by extension via /audit-project, each
# downstream loom-managed project's). Loom owns these two keys —
# conflicts on them OVERWRITE; other env keys preserved. First
# overwrite writes .claude/settings.json.pre-loom.bak.
log ""
log "Project env-block merge into $LOOM_ROOT/.claude/settings.json:"
PROJECT_SETTINGS_DIR="$LOOM_ROOT/.claude"
PROJECT_SETTINGS="$PROJECT_SETTINGS_DIR/settings.json"
if [ "$DRY_RUN" = "1" ]; then
  log "  WOULD: merge canonical env block (CLAUDE_CODE_ENABLE_TASKS=false,"
  log "         CLAUDE_CODE_DISABLE_AUTO_MEMORY=1) into $PROJECT_SETTINGS"
else
  mkdir -p "$PROJECT_SETTINGS_DIR"
  if [ ! -f "$PROJECT_SETTINGS" ]; then
    cat >"$PROJECT_SETTINGS" <<'JSON'
{
  "env": {
    "CLAUDE_CODE_ENABLE_TASKS": "false",
    "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1"
  }
}
JSON
    log "  created $PROJECT_SETTINGS with canonical loom env block"
  else
    # Deep-merge: loom's two env keys overwrite; other env keys
    # preserved; non-env top-level keys preserved. Backup on first
    # overwrite (mirrors the user-global settings.json.pre-loom.bak
    # pattern at line ~230). Log if a conflict was overwritten so the
    # user can audit.
    python3 - "$PROJECT_SETTINGS" <<'PYEOF'
import json, os, shutil, sys

path = sys.argv[1]
canonical = {
    "CLAUDE_CODE_ENABLE_TASKS": "false",
    "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1",
}

try:
    with open(path) as f:
        cur = json.load(f)
except Exception as e:
    print(f"[loom-install]   WARN: could not parse {path}: {e}", file=sys.stderr)
    sys.exit(0)

cur_env = cur.get("env", {}) if isinstance(cur.get("env"), dict) else {}
conflicts = []
additions = []
for k, v in canonical.items():
    if k in cur_env:
        if cur_env[k] != v:
            conflicts.append((k, cur_env[k], v))
    else:
        additions.append(k)

# Idempotent no-op: both canonical keys already canonical → no write,
# no backup.
if not conflicts and not additions:
    print(f"[loom-install]   loom env block already canonical in {os.path.basename(path)} (no change)")
    sys.exit(0)

# About to modify the file. Back up if there's no backup yet AND the
# pre-existing file had ANY content to preserve (which is anything
# other than the file we'd write fresh).
backup = path + ".pre-loom.bak"
if not os.path.exists(backup):
    shutil.copy2(path, backup)
    print(f"[loom-install]   backed up existing settings.json -> {os.path.basename(backup)}")

merged_env = dict(cur_env)
for k, v in canonical.items():
    merged_env[k] = v
cur["env"] = merged_env

with open(path, "w") as f:
    json.dump(cur, f, indent=2)
    f.write("\n")

for k, old, new in conflicts:
    print(f"[loom-install]   overwrote env.{k}: '{old}' -> '{new}' (loom canonical wins)")
for k in additions:
    print(f"[loom-install]   added env.{k} = '{canonical[k]}'")
print(f"[loom-install]   merged loom env block into {os.path.basename(path)}")
PYEOF
  fi
fi

# Stamp loom's own <loom_root>/.claude/.loom-sync (loom-ig3p.2). Same
# "loom dogfoods its own project-local .claude/ state" pattern as the
# env-block merge just above — loom IS "the target project" from
# install.sh's perspective (a genuine downstream/managed project's
# .claude/.loom-sync is stamped by /audit-project instead; see
# skills/audit-project/SKILL.md). Records loom's CURRENT convention-
# manifest hash (scripts/loom-convention-manifest, loom-ig3p.1) so a
# later detector (loom-ig3p.3) can compare a stamped hash against
# loom's current one to notice drift. Write logic lives in
# scripts/loom-sync-stamp (loom_write_sync_stamp), kept as a tiny
# standalone unit so it's independently testable without invoking
# install.sh end-to-end — see lib/tests/loom-sync-stamp.test.sh.
log ""
log "Stamping $PROJECT_SETTINGS_DIR/.loom-sync..."
if [ "$DRY_RUN" = "1" ]; then
  log "  WOULD: stamp $PROJECT_SETTINGS_DIR/.loom-sync with loom's current convention-manifest hash"
else
  _loom_sync_hash="$("$LOOM_ROOT/scripts/loom-convention-manifest")"
  if [ -n "$_loom_sync_hash" ]; then
    "$LOOM_ROOT/scripts/loom-sync-stamp" "$LOOM_ROOT" "$_loom_sync_hash"
    log "  stamped $PROJECT_SETTINGS_DIR/.loom-sync (hash=$_loom_sync_hash)"
  else
    log "  WARN: scripts/loom-convention-manifest produced no hash — skipping .loom-sync stamp"
  fi
  unset _loom_sync_hash
fi

# Wire the bd-merge-driver in loom's own .git/config (loom-4um).
# Merge drivers are stored in git config (not in the tree), so the
# repo's .gitattributes references `merge=bd-export` but nothing
# resolves that name until `git config merge.bd-export.driver` is
# set. Set it here so loom's own .beads/issues.jsonl is protected
# against the silent-auto-merge regression class.
#
# The configured driver (scripts/bd-merge-driver.sh) routes `bd
# export` through lib/bd-canonical-export.sh (loom-0ahj.1 / loom-hsm7),
# which keeps the export byte-stable AND memory-retaining across bd
# versions: on the controlled bd v1.0.4 it passes `--include-memories`
# (v1.0.4 excludes memories by default; the rows are sorted natively),
# and on the v1.0.2 downstream backstop it includes memories by default
# and sorts the `_type:memory` lines into a stable order — killing the
# loom-n1sk spurious memory-line churn that would otherwise re-dirty
# issues.jsonl on every merge. No config change is needed for the
# canonicalizer: it lives inside the driver script, so the same
# `merge.bd-export.driver` value benefits automatically.
#
# Downstream projects that adopt loom set the same `git config`
# entry in their own .git/config — that wiring is handled by
# /audit-project, not by this install.sh (loom's install only
# touches ~/.claude/ and the loom repo itself).
log ""
log "Wiring bd-merge-driver in loom's .git/config..."
if [ "$DRY_RUN" = "1" ]; then
  log "  WOULD: git -C '$LOOM_ROOT' config merge.bd-export.name 'bd-export merge driver (loom-4um)'"
  log "  WOULD: git -C '$LOOM_ROOT' config merge.bd-export.driver 'scripts/bd-merge-driver.sh %O %A %B %P'"
else
  git -C "$LOOM_ROOT" config merge.bd-export.name 'bd-export merge driver (loom-4um)' || true
  git -C "$LOOM_ROOT" config merge.bd-export.driver 'scripts/bd-merge-driver.sh %O %A %B %P' || true
  log "  set merge.bd-export.driver → scripts/bd-merge-driver.sh"
fi

# bd-version advisory (loom-hsm7). loom's controlled bd is PINNED at
# v1.0.2. v1.0.4+ DOES fix the v1.0.2 memory-row export non-determinism
# upstream (beads #3474/#4086) — but its `bd export` AND its throttled
# AUTO-export now EXCLUDE `bd remember` memories by default, and the
# `export.include-memories` config key is accepted-but-IGNORED by
# auto-export. Since loom commits memories INTO issues.jsonl (dolt is
# local-only), v1.0.4+ silently strips them on every bd write. This was
# validated then ROLLED BACK in loom-hsm7; the canonicalizer already
# delivers determinism on v1.0.2, so loom loses nothing by staying.
# Revisit once upstream makes auto-export honor memory inclusion. NUDGE,
# never a gate — never blocks install.
if command -v bd >/dev/null 2>&1; then
  _bd_ver="$(bd version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  if [ -n "$_bd_ver" ] && [ "$(printf '%s\n%s\n' '1.0.4' "$_bd_ver" | sort -V | head -1)" = "1.0.4" ]; then
    log "  ADVISORY: bd $_bd_ver >= 1.0.4 — its auto-export DROPS bd-remember"
    log "            memories from issues.jsonl (config key ignored; loom-hsm7);"
    log "            loom commits memories there. Consider pinning v1.0.2 until"
    log "            upstream fixes auto-export memory inclusion."
  fi
fi

# Wire the pre-push mkdocs-strict hook into loom's own .git/hooks/
# (loom-kbo). Git hooks are local-only state — like the merge driver
# above, the repo carries the script but each clone must opt-in via
# its own .git/hooks/ symlink. We do that wiring here for loom's own
# checkout. Downstream projects that adopt loom set up an equivalent
# .git/hooks/pre-push wiring via /audit-project, not this install.sh.
#
# If a pre-push hook already exists in .git/hooks/ as a non-symlink,
# the loom hook is NOT installed (we'd need a chained dispatcher and
# that's out of scope for loom-kbo). The install logs the skip and
# the user can integrate manually.
log ""
log "Wiring pre-push mkdocs-strict hook in loom's .git/hooks/..."
# Resolve the real .git/hooks/ dir — works from both the main
# checkout and from a linked worktree (where .git is a file
# pointing at the common dir's worktrees/<id>/ admin entry; the
# hooks live in the COMMON git dir, not the per-worktree admin).
GIT_COMMON_DIR=$(git -C "$LOOM_ROOT" rev-parse --git-common-dir 2>/dev/null)
if [ -z "$GIT_COMMON_DIR" ]; then
  log "  SKIP: $LOOM_ROOT is not inside a git checkout"
  GIT_COMMON_DIR="$LOOM_ROOT/.git"
fi
# git-common-dir may be relative — anchor to LOOM_ROOT.
case "$GIT_COMMON_DIR" in
  /*) ;;
  *) GIT_COMMON_DIR="$LOOM_ROOT/$GIT_COMMON_DIR" ;;
esac
PRE_PUSH_TARGET="$GIT_COMMON_DIR/hooks/pre-push"
PRE_PUSH_SOURCE="$LOOM_ROOT/hooks/pre-push-mkdocs-strict.sh"
if [ -e "$PRE_PUSH_TARGET" ] && [ ! -L "$PRE_PUSH_TARGET" ]; then
  log "  SKIP: $PRE_PUSH_TARGET already exists (non-symlink) — integrate manually"
elif [ -L "$PRE_PUSH_TARGET" ] && [ "$(readlink "$PRE_PUSH_TARGET")" = "$PRE_PUSH_SOURCE" ]; then
  log "  already linked: $PRE_PUSH_TARGET -> $PRE_PUSH_SOURCE"
else
  if [ "$DRY_RUN" = "1" ]; then
    log "  WOULD: ln -sf '$PRE_PUSH_SOURCE' '$PRE_PUSH_TARGET'"
  else
    ln -sf "$PRE_PUSH_SOURCE" "$PRE_PUSH_TARGET"
    log "  linked $PRE_PUSH_TARGET -> $PRE_PUSH_SOURCE"
  fi
fi

# Wire the post-rewrite hook into loom's own .git/hooks/ (loom-yjo).
# After git rebase / commit --amend, the hook re-exports .beads/
# issues.jsonl from dolt and auto-commits the result if it diverges
# from HEAD — automating the manual `git add .beads/issues.jsonl &&
# git commit -m 'bd: post-rebase re-export'` workaround. Composes
# orthogonally with the bd-merge-driver above (loom-4um covers git
# merge; this covers rebase-replay).
#
# Same symlink-with-non-symlink-skip pattern as pre-push above. Reuses
# GIT_COMMON_DIR already resolved earlier.
log ""
log "Wiring post-rewrite hook in loom's .git/hooks/..."
POST_REWRITE_TARGET="$GIT_COMMON_DIR/hooks/post-rewrite"
POST_REWRITE_SOURCE="$LOOM_ROOT/hooks/post-rewrite.sh"
if [ -e "$POST_REWRITE_TARGET" ] && [ ! -L "$POST_REWRITE_TARGET" ]; then
  log "  SKIP: $POST_REWRITE_TARGET already exists (non-symlink) — integrate manually"
elif [ -L "$POST_REWRITE_TARGET" ] && [ "$(readlink "$POST_REWRITE_TARGET")" = "$POST_REWRITE_SOURCE" ]; then
  log "  already linked: $POST_REWRITE_TARGET -> $POST_REWRITE_SOURCE"
else
  if [ "$DRY_RUN" = "1" ]; then
    log "  WOULD: ln -sf '$POST_REWRITE_SOURCE' '$POST_REWRITE_TARGET'"
  else
    ln -sf "$POST_REWRITE_SOURCE" "$POST_REWRITE_TARGET"
    log "  linked $POST_REWRITE_TARGET -> $POST_REWRITE_SOURCE"
  fi
fi

log ""
log "Install complete."
log ""
# Derive the expected PreToolUse-Bash hook count from the snippet so this
# hint stays accurate as hooks are added (e.g. loom-z3m.7's
# worktree-bg-inventory.sh, loom-8jz's constitution-enforce.sh) instead
# of drifting against a hardcoded number. The new hook is symlinked by
# the `hooks/*.sh` loop above and wired into the chain by the
# settings.snippet.json merge; no per-hook install step is needed.
# Falls back to "the" when jq is unavailable.
BASH_HOOK_COUNT="the"
if command -v jq >/dev/null 2>&1; then
  BASH_HOOK_COUNT=$(jq '[.hooks.PreToolUse[] | select(.matcher=="Bash") | .hooks[]] | length' "$SNIPPET" 2>/dev/null || echo "the")
fi
log "Next steps:"
log "  1. Verify with: /hooks (in Claude Code) — should list $BASH_HOOK_COUNT PreToolUse Bash hooks + 1 SessionStart hook"
log "  2. Confirm status line in Claude Code TUI shows 'WORKFLOW: ...'"
log "  3. For per-project setup, run /audit-project from inside a beads workspace"
