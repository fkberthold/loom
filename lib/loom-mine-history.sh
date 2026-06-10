#!/usr/bin/env bash
# loom-mine-history.sh — deterministic core of the brownfield
# "decision-archaeology" history miner.
#
# Mines a repo's merged PRs + merge/squash commits + release tags for
# decisions that were stated in-flight but never captured in MemPalace.
# Owns stages 1-4 of a 5-stage pipeline plus the manifest emit; the
# stage-5 *MCP palace filing* belongs to the later bn7.4 skill and is
# deliberately OUT OF SCOPE here. This lib's terminus is writing the
# draft + KG-triple manifest to disk for the skill to file.
#
# Design source: drawer_loom_decisions_e43e3693c8ee82e3bc6e34c6
# (loom/decisions wing). Tracks loom-bn7.1.
#
# Pipeline:
#   1. HARVEST          — gh PRs (if authed) + git log commits + tags,
#                         unified into source-tagged candidate records.
#                         gh-absent degrades to git-only, never aborts.
#   2. HEURISTIC GATE   — pure-bash scoring + threshold; no LLM.
#   3. COST-PREVIEW gate— MANDATORY stdout preview; --dry-run stops
#                         here; otherwise requires --yes / interactive y
#                         before any LLM spend.
#   4. LLM SALIENCE+DRAFT — per survivor, shell out to `claude -p`.
#                         Trust gate: {"salient":false} → no draft.
#   5. EMIT MANIFEST    — drafts.jsonl + kg-triples.jsonl (no palace
#                         writes here — that's bn7.4).
#
# Conventions (mirrors lib/loom-upstream.sh):
#   - This file is SOURCED, not executed. Sourcing has NO side effects.
#   - NO `set -euo pipefail` at sourcing time — callers own shell opts.
#   - Single-purpose functions; explicit returns.
#   - jq-free JSON: extraction via sed/grep; emission via printf with
#     manual escaping. The records we emit are simple flat objects.
#
# Entry point:
#   loom_mine_history <repo-path> [flags]
#     --since=DATE          only commits/PRs since DATE (git --since)
#     --since-release=TAG   only history after TAG
#     --since-sha=SHA       only history after SHA — the *consume* side
#                           of the watermark; harvests SHA..HEAD. Takes
#                           precedence over --since-release. (bn7.3)
#     --max-units=N         cap survivors fed to the LLM pass
#     --dry-run             stop after cost preview; zero spend
#     --yes                 auto-confirm the cost gate
#     --resume              with --out, skip survivors already processed
#                           in a prior run (recorded in <out>/.processed)
#                           so an interrupted run does not re-spend the
#                           LLM pass. Requires --out. (bn7.3)
#     --synthesize          tier-2: after tier-1, cluster salient units by
#                           shared decision-file-area; each cluster of >=2
#                           gets ONE LLM call narrating a "narrative arc"
#                           drawer that LINKS its constituents by anchor
#                           (no tier-1 verbatim duplication). Opt-in (extra
#                           per-cluster LLM cost); writes <out>/arcs.jsonl.
#                           No-op on --dry-run. (bn7.2)
#     --model=MODEL         claude model (default: a cheap tier)
#     --out=DIR             write candidates/drafts/triples into DIR.
#                           A real (non-dry-run) pass also writes
#                           <out>/watermark (the HEAD mined through, for
#                           the skill to file as the KG fact
#                           <repo> -> history_mined_through -> <SHA>).

# Intentionally NO `set -euo pipefail` at source time.

# Default cheap model tier for the salience pass.
_LMH_DEFAULT_MODEL="claude-haiku-4-5"

# ---------------------------------------------------------------------
# JSON-string escaping (jq-free). Escapes backslash, quote, newline,
# tab, carriage-return so a value can be embedded in our flat records.
# ---------------------------------------------------------------------
_lmh_json_escape() {
  # Reads stdin, prints the escaped string (no surrounding quotes).
  local s
  s=$(cat)
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\t'/\\t}
  s=${s//$'\r'/}
  # Encode embedded newlines as \n.
  s=${s//$'\n'/\\n}
  printf '%s' "$s"
}

# Extract a flat string field from one of OUR candidate records (the
# pipe-delimited internal format), NOT arbitrary JSON.

# ---------------------------------------------------------------------
# Heuristic scoring of a COMMIT.
#   args: subject, body, files (newline-joined)
#   echo: integer score; >=2 survives. Junk patterns force a hard drop
#   (score 0) regardless of other signals.
# ---------------------------------------------------------------------
_lmh_score_commit() {
  local subject="$1" body="$2" files="$3"
  local score=0
  local lc
  lc=$(printf '%s' "$subject" | tr '[:upper:]' '[:lower:]')

  # Hard-drop junk subjects — UNCONDITIONAL (must fire even when the
  # commit touches a decisiony file or has a body, like bump/wip). The
  # routine-churn patterns (upgrade / update-deps/packages / lint /
  # chore / de-flake) were added after the e2e-api-tests dogfood
  # (loom-mec) showed dependency-bump + lint commits scoring >=2 via a
  # config-file touch and surviving to the paid LLM pass.
  case "$lc" in
    wip*|*"wip:"*|fixup*|"fixup!"*|squash!*|typo*|*" typo"*|bump*|"merge main"*|"merge branch"*|revert*|*"revert \""*)
      echo 0; return 0 ;;
    upgrade*|*"upgrade "*|chore*|"chore:"*|lint*|*" lint "*|*"lint errors"*|*"lint fix"*|*"de-flake"*|*"deflake"*)
      echo 0; return 0 ;;
  esac
  # Routine dependency churn (update deps / update * packages / pkgs).
  if printf '%s' "$lc" | grep -qiE 'update .*(deps|dependenc|packages|pkgs)|bump .*(deps|dependenc)'; then
    echo 0; return 0
  fi
  # Revert anywhere in subject.
  if printf '%s' "$lc" | grep -qi 'revert'; then echo 0; return 0; fi

  # Substantial message body (multi-line rationale).
  local body_len
  body_len=$(printf '%s' "$body" | wc -c)
  [ "$body_len" -ge 40 ] && score=$((score + 1))

  # Subject is reasonably descriptive (not a one-word stub).
  local subj_words
  subj_words=$(printf '%s' "$subject" | wc -w)
  [ "$subj_words" -ge 3 ] && score=$((score + 1))

  # Touches a decision-shaped file.
  if _lmh_files_are_decisiony "$files"; then
    score=$((score + 2))
  fi

  # Rationale-shaped language in body.
  if printf '%s' "$body" | grep -qiE 'because|trade-?off|chose|decision|rfc|instead of|rather than'; then
    score=$((score + 1))
  fi

  echo "$score"
}

# ---------------------------------------------------------------------
# Heuristic scoring of a PR.
#   args: title, body, labels (comma-joined), files (newline-joined),
#         has_review (1/0)
#   echo: integer score; >=2 survives.
# ---------------------------------------------------------------------
_lmh_score_pr() {
  local title="$1" body="$2" labels="$3" files="$4" has_review="$5"
  local score=0

  # Review discussion present.
  [ "$has_review" = "1" ] && score=$((score + 1))

  # Body length.
  local body_len
  body_len=$(printf '%s' "$body" | wc -c)
  [ "$body_len" -ge 60 ] && score=$((score + 1))

  # Decision-flavored labels.
  if printf '%s' "$labels" | grep -qiE 'breaking|design|rfc'; then
    score=$((score + 2))
  fi

  # Closes an issue.
  if printf '%s' "$body" | grep -qiE 'closes #|fixes #|resolves #'; then
    score=$((score + 1))
  fi

  # Decision-shaped files.
  if _lmh_files_are_decisiony "$files"; then
    score=$((score + 1))
  fi

  # Rationale language in title/body.
  if printf '%s\n%s' "$title" "$body" | grep -qiE 'because|trade-?off|chose|decision|rfc|instead of|rather than|adopt'; then
    score=$((score + 1))
  fi

  echo "$score"
}

# True (rc 0) if any file path looks decision-shaped: schema,
# migrations, *.proto, interface files, *config*.
_lmh_files_are_decisiony() {
  local files="$1"
  printf '%s' "$files" | grep -qiE 'schema|migrat|\.proto$|interface|config' && return 0
  return 1
}

# ---------------------------------------------------------------------
# TIER-2 clustering key for a salient unit (bn7.2). Deterministic, no
# LLM: the first decision-shaped token its files match (in priority
# order), else the top-level directory of its first file. Units sharing
# a key are the same narrative arc.
# ---------------------------------------------------------------------
_lmh_cluster_key() {
  local files="$1" lc tok first
  lc=$(printf '%s' "$files" | tr '[:upper:]' '[:lower:]')
  for tok in schema migrat proto interface config; do
    if printf '%s' "$lc" | grep -q "$tok"; then echo "$tok"; return 0; fi
  done
  first=$(printf '%s' "$files" | tr ',' '\n' | grep -v '^$' | head -1)
  case "$first" in
    */*) echo "${first%%/*}" ;;
    "")  echo "_misc" ;;
    *)   echo "_root" ;;
  esac
}

# ---------------------------------------------------------------------
# LLM-failure threshold for the salience pass (loom-ug4p). A reply is a
# FAILURE (distinct from a valid {"salient":false}) when it is empty OR
# the call exited non-zero OR the reply is unparseable as the salience
# schema. A throttled / rate-limited / crashed claude returns FAILURES
# for most/all units; if the engine treated those as {"salient":false}
# it would write a clean near-0-draft "success" manifest (the loom-rnxp
# 0/353 + original 0/787 false-greens). Instead the pass ABORTS non-zero
# once the running failure fraction exceeds _LMH_FAIL_THRESHOLD_PCT over
# at least _LMH_FAIL_MIN_PROCESSED processed units (so a 1-of-1 hiccup
# on a tiny set doesn't trip the gate).
_LMH_FAIL_THRESHOLD_PCT=25
_LMH_FAIL_MIN_PROCESSED=4
# Per-unit retry budget for a FAILED claude call (transient throttles),
# with small exponential backoff between attempts.
_LMH_LLM_RETRIES=3

# ---------------------------------------------------------------------
# One claude salience call for a unit, WITH retry + backoff. Captures
# claude's stderr (NOT swallowed) so a real failure surfaces a
# diagnostic. Classifies the result:
#   - prints the cleaned reply on stdout AND returns 0 when the call
#     succeeded (rc 0, non-empty, parseable as a {"salient":...} object);
#   - returns 1 (FAILURE) when every attempt was empty / rc!=0 /
#     unparseable. On FAILURE the last attempt's stderr is echoed to the
#     engine's stderr so the operator sees WHY (rate-limit text, etc.).
# A valid {"salient":false} is a SUCCESS (rc 0) — it is a real model
# verdict, not a failure.
#   args: prompt, model
# ---------------------------------------------------------------------
_lmh_claude_salience() {
  local prompt="$1" model="$2"
  local attempt=1 reply rc errfile last_err="" backoff=1
  errfile=$(mktemp)
  while [ "$attempt" -le "$_LMH_LLM_RETRIES" ]; do
    # </dev/null on stdin: this call runs INSIDE the `while read ... done
    # < "$survivors"` salience loop, so without the redirect `claude -p`
    # inherits the survivors fd as stdin and READS it — slurping the
    # remaining units into its reply (derailing the per-unit verdict) AND
    # corrupting the loop's own read position. That stdin leak produced
    # the rnxp 0/787, 0/353, and 4/4-abort runs (masked by capped runs
    # where the tiny remaining stream didn't derail the reply). (rnxp)
    reply=$(claude -p "$prompt" --model "$model" --output-format text </dev/null 2>"$errfile")
    rc=$?
    last_err=$(cat "$errfile" 2>/dev/null)
    # Strip a ```json ... ``` markdown fence the model adds even when
    # asked for raw JSON, so the per-field sed sees clean JSON. (loom-bzl)
    reply=$(printf '%s' "$reply" | sed -e 's/^```[a-zA-Z]*[[:space:]]*$//' -e 's/^```[[:space:]]*$//')
    # SUCCESS iff rc 0 AND non-empty AND carries a parseable salient verdict.
    if [ "$rc" -eq 0 ] && [ -n "$reply" ] \
       && printf '%s' "$reply" | grep -qE '"salient":[[:space:]]*(true|false)'; then
      printf '%s' "$reply"
      rm -f "$errfile"
      return 0
    fi
    # FAILURE this attempt — back off and retry (unless out of budget).
    attempt=$((attempt + 1))
    [ "$attempt" -le "$_LMH_LLM_RETRIES" ] && { sleep "$backoff" 2>/dev/null || true; backoff=$((backoff * 2)); }
  done
  # Exhausted retries — surface the last stderr for the operator.
  [ -n "$last_err" ] && printf 'claude FAILED: %s\n' "$last_err" >&2
  rm -f "$errfile"
  return 1
}

# ---------------------------------------------------------------------
# HARVEST: git commits + tags. Emits one TSV record per commit on
# stdout: TYPE \t ID \t AUTHOR \t DATE \t SUBJECT \t BODY \t FILES \t ANCHOR
# Body/subject/files have embedded newlines escaped to \n already, so
# each record is exactly one line.
# ---------------------------------------------------------------------
_lmh_harvest_git() {
  local repo="$1" since="$2" since_release="$3" since_sha="$4"
  local rev_range=() log_args=()

  # --since-sha is the watermark consume side; it takes precedence over
  # --since-release (if you have a watermark you don't also need a tag
  # bound). Both express a <rev>..HEAD range.
  if [ -n "$since_sha" ]; then
    rev_range=("${since_sha}..HEAD")
  elif [ -n "$since_release" ]; then
    rev_range=("${since_release}..HEAD")
  fi
  if [ -n "$since" ]; then
    log_args+=("--since=$since")
  fi

  # Collect tag→commit map for release-commit tagging.
  local tagged_shas
  tagged_shas=$(git -C "$repo" for-each-ref --format='%(objectname:short) %(refname:short)' refs/tags 2>/dev/null)

  # Use a unit separator between records and a field separator that
  # won't appear in commit text. \x1f = field, \x1e = record.
  # The %b body (and rarely %s) carry embedded newlines; collapse ALL
  # whitespace newlines/tabs/CRs to spaces INSIDE awk before printing,
  # so each record is exactly one physical line. Otherwise the
  # downstream `read` stops at the first newline and TRUNCATES a
  # multi-line body to its first line — losing the rationale that most
  # substantial commits state on line 2+, which made the full e2e
  # dogfood return 0 drafts on 787 gated units. (loom-b10)
  git -C "$repo" log --no-merges \
      --pretty=format:'%x1e%h%x1f%an%x1f%aI%x1f%s%x1f%b%x1f' \
      "${log_args[@]}" "${rev_range[@]}" 2>/dev/null \
  | awk 'BEGIN{RS="\x1e";FS="\x1f"} NF>=4 {
      f1=$1; f2=$2; f3=$3; f4=$4; f5=$5
      gsub(/[\n\t\r]+/," ",f1); gsub(/[\n\t\r]+/," ",f2)
      gsub(/[\n\t\r]+/," ",f3); gsub(/[\n\t\r]+/," ",f4)
      gsub(/[\n\t\r]+/," ",f5)
      print f1 "\x1f" f2 "\x1f" f3 "\x1f" f4 "\x1f" f5
    }' \
  | while IFS=$'\x1f' read -r sha author date subject body; do
      [ -z "$sha" ] && continue
      local files
      files=$(git -C "$repo" show --name-only --pretty=format: "$sha" 2>/dev/null | grep -v '^$' | tr '\n' ',')
      # Tag this commit if it carries a release tag.
      local is_tag=""
      if printf '%s\n' "$tagged_shas" | grep -q "^$sha "; then
        is_tag="tag"
      fi
      printf 'COMMIT\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$sha" "$author" "$date" \
        "$(printf '%s' "$subject" | tr '\n\t' '  ')" \
        "$(printf '%s' "$body" | tr '\n\t' '  ')" \
        "$files" \
        "${is_tag}"
    done
}

# ---------------------------------------------------------------------
# HARVEST: gh merged PRs. Emits one TSV record per PR:
# TYPE \t NUMBER \t AUTHOR \t DATE \t TITLE \t BODY \t FILES \t URL \t LABELS \t HAS_REVIEW
# Degrades to nothing (rc 0) when gh is unauthenticated/absent.
# ---------------------------------------------------------------------
_lmh_harvest_gh() {
  local repo="$1"
  # Detect gh access. If unauthenticated, degrade gracefully.
  if ! command -v gh >/dev/null 2>&1; then return 0; fi
  if ! gh auth status >/dev/null 2>&1; then return 0; fi

  local json
  json=$(gh pr list --state merged \
           --json number,title,body,labels,files,author,mergedAt,url \
           2>/dev/null)
  [ -z "$json" ] && return 0
  [ "$json" = "[]" ] && return 0

  # jq-free parse: split the array into per-object chunks on '},{' and
  # extract flat fields with sed. The harvest JSON is machine-emitted
  # and stable enough for this; tests pin the exact shape.
  # Normalize: strip outer brackets, split objects.
  # NB: append a trailing newline (printf '%s\n') so `while read` does
  # not drop the final object on an unterminated last line.
  printf '%s\n' "$json" \
    | sed 's/^\[//; s/\]$//' \
    | sed 's/},[[:space:]]*{/}\n{/g' \
    | while IFS= read -r obj; do
        [ -z "$obj" ] && continue
        local number title body url author date labels files has_review
        number=$(printf '%s' "$obj" | sed -n 's/.*"number":\([0-9]*\).*/\1/p')
        title=$(printf '%s' "$obj"  | sed -n 's/.*"title":"\([^"]*\)".*/\1/p')
        body=$(printf '%s' "$obj"   | sed -n 's/.*"body":"\(.*\)","labels".*/\1/p')
        [ -z "$body" ] && body=$(printf '%s' "$obj" | sed -n 's/.*"body":"\([^"]*\)".*/\1/p')
        url=$(printf '%s' "$obj"    | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')
        author=$(printf '%s' "$obj" | sed -n 's/.*"login":"\([^"]*\)".*/\1/p')
        date=$(printf '%s' "$obj"   | sed -n 's/.*"mergedAt":"\([^"]*\)".*/\1/p')
        # Labels: collect every "name":"X" inside the labels array.
        labels=$(printf '%s' "$obj" | grep -oE '"name":"[^"]*"' | sed 's/"name":"//; s/"$//' | tr '\n' ',')
        # Files: collect every "path":"X".
        files=$(printf '%s' "$obj"  | grep -oE '"path":"[^"]*"' | sed 's/"path":"//; s/"$//' | tr '\n' ',')
        # Review discussion: probe gh api for review threads. The stub
        # may return nothing; treat non-empty as has_review=1.
        local rt
        rt=$(gh api "repos/{owner}/{repo}/pulls/$number/comments" 2>/dev/null)
        has_review=0
        [ -n "$rt" ] && has_review=1
        printf 'PR\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
          "$number" "$author" "$date" \
          "$(printf '%s' "$title" | tr '\n\t' '  ')" \
          "$(printf '%s' "$body"  | tr '\n\t' '  ')" \
          "$files" "$url" "$labels" "$has_review"
      done
}

# ---------------------------------------------------------------------
# loom_mine_history <repo-path> [flags]
# ---------------------------------------------------------------------
loom_mine_history() {
  local repo="" since="" since_release="" since_sha="" max_units="" out=""
  local dry_run=0 yes=0 resume=0 synthesize=0
  local model="$_LMH_DEFAULT_MODEL"

  # First positional is the repo path; flags may follow.
  if [ -n "${1:-}" ] && [ "${1#--}" = "$1" ]; then
    repo="$1"; shift
  fi

  while [ $# -gt 0 ]; do
    case "$1" in
      --since-sha=*)     since_sha="${1#--since-sha=}" ;;
      --since-release=*) since_release="${1#--since-release=}" ;;
      --since=*)         since="${1#--since=}" ;;
      --max-units=*)     max_units="${1#--max-units=}" ;;
      --dry-run)         dry_run=1 ;;
      --yes)             yes=1 ;;
      --resume)          resume=1 ;;
      --synthesize)      synthesize=1 ;;
      --model=*)         model="${1#--model=}" ;;
      --model)           shift; model="${1:-$model}" ;;
      --out=*)           out="${1#--out=}" ;;
      --out)             shift; out="${1:-}" ;;
      --since-sha)       shift; since_sha="${1:-}" ;;
      --since-release)   shift; since_release="${1:-}" ;;
      --since)           shift; since="${1:-}" ;;
      --max-units)       shift; max_units="${1:-}" ;;
      *)
        # Unrecognized — if repo unset, treat as repo path.
        if [ -z "$repo" ]; then repo="$1"; fi ;;
    esac
    shift
  done

  if [ -z "$repo" ]; then
    echo "loom_mine_history: missing <repo-path>" >&2
    return 2
  fi
  if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
    echo "loom_mine_history: $repo is not a git repository" >&2
    return 2
  fi
  # --resume needs a persistent dir to checkpoint into.
  if [ "$resume" -eq 1 ] && [ -z "$out" ]; then
    echo "loom_mine_history: --resume requires --out (nowhere to checkpoint)" >&2
    return 2
  fi

  # ---- STAGE 1: HARVEST ------------------------------------------
  local harvest
  harvest=$( { _lmh_harvest_gh "$repo"; _lmh_harvest_git "$repo" "$since" "$since_release" "$since_sha"; } )
  local harvested_count=0
  [ -n "$harvest" ] && harvested_count=$(printf '%s\n' "$harvest" | grep -c .)

  # ---- STAGE 2: HEURISTIC GATE -----------------------------------
  # Survivors written to a temp file as TSV records (same shape as
  # harvest). The candidate JSONL is built alongside.
  local survivors candidates_jsonl
  survivors=$(mktemp)
  candidates_jsonl=$(mktemp)

  printf '%s\n' "$harvest" | while IFS=$'\t' read -r typ id author date c1 c2 c3 c4 c5 c6; do
    [ -z "$typ" ] && continue
    local score=0 title="" body="" files="" url="" labels="" has_review="0"
    if [ "$typ" = "COMMIT" ]; then
      title="$c1"; body="$c2"; files="$c3"
      score=$(_lmh_score_commit "$title" "$body" "$files")
    elif [ "$typ" = "PR" ]; then
      title="$c1"; body="$c2"; files="$c3"; url="$c4"; labels="$c5"; has_review="$c6"
      score=$(_lmh_score_pr "$title" "$body" "$labels" "$files" "$has_review")
    fi
    if [ "${score:-0}" -ge 2 ]; then
      # Survivor record (keep all fields for the LLM pass).
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$typ" "$id" "$author" "$date" "$title" "$body" "$files" "$url" "$labels" >> "$survivors"
      # Candidate JSONL line.
      printf '{"source_type":"%s","source_id":"%s","author":"%s","date":"%s","title":"%s","anchor":"%s"}\n' \
        "$typ" \
        "$(printf '%s' "$id" | _lmh_json_escape)" \
        "$(printf '%s' "$author" | _lmh_json_escape)" \
        "$(printf '%s' "$date" | _lmh_json_escape)" \
        "$(printf '%s' "$title" | _lmh_json_escape)" \
        "$(printf '%s' "${url:-$id}" | _lmh_json_escape)" >> "$candidates_jsonl"
    fi
  done

  local gated_count=0
  # `grep -c` ALWAYS prints a count (0 on no-match) and exits 1 when
  # zero — so `|| echo 0` would APPEND a second 0 (gated_count="0\n0",
  # loom-6iy). Drop the `|| echo 0`; default the file-missing case via
  # ${gated_count:-0}. Mirrors the loom-bn7.2 n_clusters/n_arcs fix.
  [ -f "$survivors" ] && { gated_count=$(grep -c . "$survivors" 2>/dev/null); gated_count=${gated_count:-0}; }

  # Apply --max-units cap to survivors fed to the LLM pass.
  if [ -n "$max_units" ] && [ "$max_units" -ge 0 ] 2>/dev/null; then
    head -n "$max_units" "$survivors" > "${survivors}.capped" 2>/dev/null
    mv "${survivors}.capped" "$survivors"
    head -n "$max_units" "$candidates_jsonl" > "${candidates_jsonl}.capped" 2>/dev/null
    mv "${candidates_jsonl}.capped" "$candidates_jsonl"
    gated_count=$(grep -c . "$survivors" 2>/dev/null); gated_count=${gated_count:-0}
  fi

  # Write candidates.jsonl if --out given.
  if [ -n "$out" ]; then
    mkdir -p "$out"
    cp "$candidates_jsonl" "$out/candidates.jsonl"
  fi

  # ---- STAGE 3: COST-PREVIEW gate (MANDATORY) --------------------
  echo "cost-preview: ${harvested_count} harvested -> ${gated_count} gated -> ~${gated_count} LLM reads, est <= ${gated_count} model calls (model=${model})"

  if [ "$dry_run" -eq 1 ]; then
    # Side-effect-free: print gated summary, stop. No LLM, no drafts.
    echo "--dry-run: stopping before LLM pass (zero spend)."
    if [ -s "$candidates_jsonl" ]; then
      echo "gated candidates:"
      cat "$candidates_jsonl"
    else
      echo "gated candidates: (none survived the heuristic gate)"
    fi
    rm -f "$survivors" "$candidates_jsonl"
    return 0
  fi

  # Require confirmation before any LLM spend.
  if [ "$yes" -ne 1 ]; then
    if [ -t 0 ]; then
      printf 'Proceed with %s LLM reads? [y/N] ' "$gated_count" >&2
      local reply=""
      read -r reply
      case "$reply" in
        y|Y|yes|YES) : ;;
        *)
          echo "loom_mine_history: aborted at cost gate (no confirmation)." >&2
          rm -f "$survivors" "$candidates_jsonl"
          return 3 ;;
      esac
    else
      echo "loom_mine_history: aborted at cost gate — non-interactive and --yes not given." >&2
      rm -f "$survivors" "$candidates_jsonl"
      return 3
    fi
  fi

  # ---- STAGE 4 + 5: LLM SALIENCE + DRAFT, EMIT MANIFEST ----------
  # Output targets. With --out the manifest + checkpoint persist in
  # $out (enabling --resume); without --out we accumulate in temp files
  # and dump to stdout. The .processed checkpoint records every
  # processed source_id (salient or not) so a resumed run skips them.
  local drafts_jsonl triples_jsonl processed_file
  if [ -n "$out" ]; then
    mkdir -p "$out"
    drafts_jsonl="$out/drafts.jsonl"
    triples_jsonl="$out/kg-triples.jsonl"
    processed_file="$out/.processed"
    if [ "$resume" -eq 1 ]; then
      # Resume: preserve prior manifest + checkpoint; append + skip done.
      [ -f "$drafts_jsonl" ]   || : > "$drafts_jsonl"
      [ -f "$triples_jsonl" ]  || : > "$triples_jsonl"
      [ -f "$processed_file" ] || : > "$processed_file"
    else
      # Fresh run: start clean.
      : > "$drafts_jsonl"; : > "$triples_jsonl"; : > "$processed_file"
    fi
  else
    drafts_jsonl=$(mktemp)
    triples_jsonl=$(mktemp)
    processed_file=$(mktemp)
  fi

  # TIER-2 (bn7.2): accumulate one record per SALIENT unit for the
  # optional --synthesize clustering pass: id \t files \t decision \t anchor.
  local synth_units
  synth_units=$(mktemp)

  # LLM-failure accounting (loom-ug4p). A genuine throttle/crash returns
  # FAILURES for most units; a valid {"salient":false} is NOT a failure.
  # `read < file` runs the loop in THIS shell (no subshell), so these
  # counters survive each iteration — the abort check after the loop is
  # honest. Aborting MID-loop would risk a partial manifest looking
  # successful, so we run the whole gated set, then gate on the fraction.
  local n_processed=0 n_failed=0 llm_abort=0

  while IFS=$'\t' read -r typ id author date title body files url labels; do
    [ -z "$typ" ] && continue

    # Resume: skip survivors already processed in a prior run (no
    # re-spend on the LLM pass).
    if [ "$resume" -eq 1 ] && grep -qxF "$id" "$processed_file" 2>/dev/null; then
      continue
    fi

    # Build the prompt: a salience INSTRUCTION + output schema, THEN the
    # source unit. Without the instruction the model has no task and
    # won't emit the schema; the e2e-api-tests dogfood hit 0/787 drafts
    # partly because the prompt was raw source text only. (loom-bzl)
    local source_text
    source_text="You are mining a software project's history for DESIGN DECISIONS. Decide whether the source below records a real decision WITH A STATED RATIONALE (a why, not merely a what). If it states no rationale, respond with exactly {\"salient\":false}. Otherwise respond with ONLY a JSON object (no prose, no markdown) with keys: \"salient\":true, \"verbatim\" (the exact decision/rationale text quoted from the source), \"synthesis\" (a 1-2 sentence paraphrase), \"decision\" (the decision stated in a few words).

Source type: $typ
Identifier: $id
Title: $title
Body: $body
Files touched: $files"

    # Shell out to claude (TEXT output, not json: the json envelope's
    # .result is an ESCAPED string the sed parse can't match through;
    # text returns the raw reply). The call goes through the retry helper
    # which captures stderr (NOT swallowed), retries transient FAILUREs
    # with backoff, and DISTINGUISHES a genuine failure (empty / rc!=0 /
    # unparseable) from a valid {"salient":false}. (loom-ug4p, loom-bzl)
    n_processed=$((n_processed + 1))
    local reply rc
    reply=$(_lmh_claude_salience "$source_text" "$model"); rc=$?

    if [ "$rc" -ne 0 ]; then
      # FAILURE (throttle / crash / unparseable) — NOT a {"salient":false}
      # verdict. Count it, emit no draft, and do NOT checkpoint it as
      # processed (so --resume re-tries it on a later, healthier run).
      n_failed=$((n_failed + 1))
      # Early-out: once the failure fraction is provably over threshold
      # for the rest of the run, stop spending — but DON'T silently
      # succeed; the post-loop gate turns this into a non-zero abort.
      if [ "$n_processed" -ge "$_LMH_FAIL_MIN_PROCESSED" ] \
         && [ $(( n_failed * 100 )) -gt $(( n_processed * _LMH_FAIL_THRESHOLD_PCT )) ]; then
        llm_abort=1
        break
      fi
      continue
    fi

    # Checkpoint this unit as processed BEFORE the trust gate, so a
    # salient=false unit (which emits no draft) is not re-spent on resume.
    printf '%s\n' "$id" >> "$processed_file"

    # Extract fields. Patterns tolerate a SPACE after the colon — real
    # claude pretty-prints `"verbatim": "..."` (the bare-JSON stub had no
    # space, which is why this shipped green). (loom-bzl)
    local salient
    salient=$(printf '%s' "$reply" | sed -n 's/.*"salient":[[:space:]]*\(true\|false\).*/\1/p' | head -1)

    if [ "$salient" != "true" ]; then
      # Trust gate: a genuine {"salient":false} verdict → emit NO draft.
      continue
    fi

    local verbatim synthesis decision
    verbatim=$(printf '%s' "$reply"  | sed -n 's/.*"verbatim":[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    synthesis=$(printf '%s' "$reply" | sed -n 's/.*"synthesis":[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    decision=$(printf '%s' "$reply"  | sed -n 's/.*"decision":[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    [ -z "$decision" ] && decision="$title"

    local anchor="${url:-$id}"

    # drawer_body = verbatim + separated synthesis + anchor line.
    local drawer_body
    drawer_body="${verbatim}"$'\n\n'"---"$'\n\n'"${synthesis}"$'\n\n'"Source: ${typ} ${id} (${anchor}) by ${author} on ${date}"

    # EMIT one draft.
    printf '{"source_id":"%s","source_type":"%s","anchor":{"id":"%s","url":"%s","date":"%s","author":"%s"},"verbatim":"%s","synthesis":"%s","drawer_body":"%s","room":"decisions","tags":["provenance:mined"]}\n' \
      "$(printf '%s' "$id" | _lmh_json_escape)" \
      "$typ" \
      "$(printf '%s' "$id" | _lmh_json_escape)" \
      "$(printf '%s' "$anchor" | _lmh_json_escape)" \
      "$(printf '%s' "$date" | _lmh_json_escape)" \
      "$(printf '%s' "$author" | _lmh_json_escape)" \
      "$(printf '%s' "$verbatim" | _lmh_json_escape)" \
      "$(printf '%s' "$synthesis" | _lmh_json_escape)" \
      "$(printf '%s' "$drawer_body" | _lmh_json_escape)" \
      >> "$drafts_jsonl"

    # EMIT KG triples: subject = the SOURCE unit (PR#/SHA), object of
    # `decided` = the decision (design: PR#->decided->X). Subject must
    # identify the source so the anchor is recoverable from the graph.
    local subject
    if [ "$typ" = "PR" ]; then subject="PR#$id"; else subject="$id"; fi
    printf '{"subject":"%s","predicate":"decided","object":"%s"}\n' \
      "$(printf '%s' "$subject" | _lmh_json_escape)" \
      "$(printf '%s' "$decision" | _lmh_json_escape)" >> "$triples_jsonl"
    printf '{"subject":"%s","predicate":"mined_from","object":"%s"}\n' \
      "$(printf '%s' "$subject" | _lmh_json_escape)" \
      "$(printf '%s' "$repo" | _lmh_json_escape)" >> "$triples_jsonl"
    printf '{"subject":"%s","predicate":"authored_by","object":"%s"}\n' \
      "$(printf '%s' "$subject" | _lmh_json_escape)" \
      "$(printf '%s' "$author" | _lmh_json_escape)" >> "$triples_jsonl"

    # Record this salient unit for the optional tier-2 clustering pass.
    # Tabs/newlines in the fields were already collapsed to spaces at
    # harvest, so one record == one line.
    printf '%s\t%s\t%s\t%s\n' "$id" "$files" "$decision" "$anchor" >> "$synth_units"
  done < "$survivors"

  # ---- LLM-FAILURE GATE (loom-ug4p) ----------------------------------
  # A throttled / rate-limited / crashed claude returns FAILUREs (empty /
  # rc!=0 / unparseable) for most units. Treating those as
  # {"salient":false} would write a clean near-0-draft "success" manifest
  # — the exact false-green that produced loom-rnxp's 0/353 and the
  # original 0/787. If the failure fraction over the processed set
  # exceeds the threshold, ABORT NON-ZERO with a diagnostic naming the
  # fraction, rather than emitting a manifest that looks successful.
  if [ "$llm_abort" -eq 1 ] \
     || { [ "$n_processed" -ge "$_LMH_FAIL_MIN_PROCESSED" ] \
          && [ $(( n_failed * 100 )) -gt $(( n_processed * _LMH_FAIL_THRESHOLD_PCT )) ]; }; then
    local pct=0
    [ "$n_processed" -gt 0 ] && pct=$(( n_failed * 100 / n_processed ))
    echo "loom_mine_history: ABORTING — claude FAILED on ${n_failed}/${n_processed} units (${pct}%, threshold ${_LMH_FAIL_THRESHOLD_PCT}%). This is a throttle/rate-limit/crash, NOT an all-{salient:false} result — refusing to emit a false-success near-0-draft manifest. Retry later or check claude auth/quota." >&2
    rm -f "$synth_units"
    if [ -z "$out" ]; then
      rm -f "$drafts_jsonl" "$triples_jsonl" "$processed_file"
    fi
    rm -f "$survivors" "$candidates_jsonl"
    return 4
  fi

  # ---- TIER-2 SYNTHESIS (bn7.2, opt-in via --synthesize) -------------
  # Cluster salient units by shared decision-file-area; clusters of >=2
  # get ONE LLM call to narrate the arc. Arc drawer LINKS constituents
  # by anchor and does NOT re-quote tier-1 verbatim. Never runs on
  # --dry-run (we returned at the cost gate before reaching here).
  local arcs_jsonl=""
  if [ "$synthesize" -eq 1 ]; then
    if [ -n "$out" ]; then arcs_jsonl="$out/arcs.jsonl"; : > "$arcs_jsonl"; else arcs_jsonl=$(mktemp); fi

    # Key each salient unit, then find keys with >=2 members.
    local keyed
    keyed=$(mktemp)
    while IFS=$'\t' read -r u_id u_files u_dec u_anchor; do
      [ -z "$u_id" ] && continue
      local k
      k=$(_lmh_cluster_key "$u_files")
      printf '%s\t%s\t%s\t%s\n' "$k" "$u_id" "$u_dec" "$u_anchor" >> "$keyed"
    done < "$synth_units"

    local clusters n_clusters
    clusters=$(cut -f1 "$keyed" | sort | uniq -c | awk '$1>=2 {print $2}')
    # NB: `grep -c` already prints 0 on no-match (exit 1); a trailing
    # `|| echo 0` would APPEND a second 0 → "0\n0". Default via ${x:-0}.
    if [ -n "$clusters" ]; then n_clusters=$(printf '%s\n' "$clusters" | grep -c .); else n_clusters=0; fi
    echo "synthesis: ${n_clusters} cluster(s) (>=2 units) -> ~${n_clusters} arc LLM read(s) (model=${model})"

    local key
    for key in $clusters; do
      # Gather this cluster's members.
      local members
      members=$(awk -F'\t' -v k="$key" '$1==k {print}' "$keyed")

      # Build the constituent list + the LLM prompt. The prompt MUST
      # contain "narrative arc" (the tier-2 trust/route marker).
      local constituents_json="" constituents_block="" prompt_units=""
      while IFS=$'\t' read -r c_key c_id c_dec c_anchor; do
        [ -z "$c_id" ] && continue
        if [ -n "$constituents_json" ]; then constituents_json="${constituents_json},"; fi
        constituents_json="${constituents_json}\"$(printf '%s' "$c_id" | _lmh_json_escape)\""
        constituents_block="${constituents_block}- ${c_id} (${c_anchor}): ${c_dec}"$'\n'
        prompt_units="${prompt_units}- ${c_id}: ${c_dec}"$'\n'
      done <<EOF
$members
EOF

      local arc_reply arc_title narrative
      # </dev/null on stdin (same discipline as the salience call): a
      # shelled-out `claude -p` in this engine must never read inherited
      # stdin. Defensive here (this call is in a `for key` loop, not a
      # file-read loop) but keeps the idiom consistent so a future nesting
      # can't reintroduce the survivors-stream leak. (rnxp)
      arc_reply=$(claude -p "Synthesize a narrative arc from these related decisions (theme: ${key}). Return JSON {\"arc_title\":...,\"narrative\":...}:
${prompt_units}" --model "$model" --output-format json </dev/null 2>/dev/null)
      arc_title=$(printf '%s' "$arc_reply" | sed -n 's/.*"arc_title":"\([^"]*\)".*/\1/p' | head -1)
      narrative=$(printf '%s' "$arc_reply" | sed -n 's/.*"narrative":"\([^"]*\)".*/\1/p' | head -1)
      [ -z "$arc_title" ] && arc_title="Arc: ${key}"

      # Arc drawer_body = narrative + constituent links. NO tier-1
      # verbatim duplication — references constituents by anchor only.
      local arc_body
      arc_body="${narrative}"$'\n\n'"Constituent decisions:"$'\n'"${constituents_block}"$'\n'"Theme: ${key} (mined from ${repo})"

      printf '{"arc_title":"%s","theme":"%s","narrative":"%s","constituents":[%s],"drawer_body":"%s","room":"decisions","tags":["provenance:mined","synthesis:arc"]}\n' \
        "$(printf '%s' "$arc_title" | _lmh_json_escape)" \
        "$(printf '%s' "$key" | _lmh_json_escape)" \
        "$(printf '%s' "$narrative" | _lmh_json_escape)" \
        "$constituents_json" \
        "$(printf '%s' "$arc_body" | _lmh_json_escape)" \
        >> "$arcs_jsonl"
    done

    local n_arcs
    n_arcs=$(grep -c . "$arcs_jsonl" 2>/dev/null); n_arcs=${n_arcs:-0}
    echo "emitted ${n_arcs} arc(s)."
    if [ -z "$out" ]; then echo "=== arcs ==="; cat "$arcs_jsonl"; rm -f "$arcs_jsonl"; fi
    rm -f "$keyed"
  fi
  rm -f "$synth_units"

  # EMIT MANIFEST / WATERMARK.
  if [ -n "$out" ]; then
    # drafts/triples already written in place. Record the watermark: the
    # HEAD we mined through, for the skill to file as the KG fact
    # <repo> -> history_mined_through -> <SHA> after the drawers land.
    # Emitted even with zero salient drafts — we DID examine through HEAD.
    git -C "$repo" rev-parse HEAD > "$out/watermark" 2>/dev/null || true
  else
    echo "=== drafts ==="
    cat "$drafts_jsonl"
    echo "=== kg-triples ==="
    cat "$triples_jsonl"
  fi

  local n_drafts
  n_drafts=$(grep -c . "$drafts_jsonl" 2>/dev/null); n_drafts=${n_drafts:-0}
  echo "emitted ${n_drafts} draft(s)."

  # Clean up temp files only — never the persistent $out manifest.
  if [ -z "$out" ]; then
    rm -f "$drafts_jsonl" "$triples_jsonl" "$processed_file"
  fi
  rm -f "$survivors" "$candidates_jsonl"
  return 0
}
