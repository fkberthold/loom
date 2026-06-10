#!/usr/bin/env bash
# SessionStart wrapper around `bd prime`.
#
# Problem (loom-nc2): `bd prime` output in projects with many `bd remember`
# entries balloons to ~150 KB because the `## Persistent Memories` section
# dumps full drawer-narrative bodies. That output is pinned into the
# SessionStart prefix and re-bills every turn until /clear, so a 6-fire
# session can burn ~900 KB before dedup.
#
# Approach: shell out to `bd prime`, then post-process its output:
#   1. Pass everything BEFORE `## Persistent Memories (N)` through verbatim.
#   2. Inside the memories block:
#      - Truncate each entry body to BD_PRIME_ENTRY_TRUNCATE_CHARS (default 200).
#      - Cap the total memories block at BD_PRIME_MEMORIES_MAX_BYTES (default
#        10000). Stop emitting entries once we'd exceed the cap; emit a single
#        `(... N entries elided to keep SessionStart prefix small)` footer.
#   3. Pass everything AFTER the memories block (if anything) through verbatim.
#
# Design lineage:
#   drawer_loom_decisions_3eec30046461f0766ac92eec — nsb dynamic-phase research
#     identified bd prime memories bloat as the bd-side bloat surface.
#
# Section detection: the memories block opens with a line matching
# `^## Persistent Memories(\b| )`. It ends at the next `^## ` line OR EOF.
# Individual entries are `^### <key>` followed by a body until the next
# `^### ` or section terminator.
#
# Test injection points (matching bd-close-capture.sh convention):
#   BD_BIN                          — bd binary path (default: bd)
#   BD_PRIME_ENTRY_TRUNCATE_CHARS   — per-entry body cap (default: 200)
#   BD_PRIME_MEMORIES_MAX_BYTES     — whole-block cap (default: 10000)
#
# Behavior on bd failure: if `bd prime` exits non-zero, emit a short note
# and exit 0 (we never want to block session startup over this).
#
# settings.json snippet (per-user, do NOT commit; install.sh wires this):
#
#   {
#     "hooks": {
#       "SessionStart": [
#         {
#           "hooks": [
#             { "type": "command",
#               "command": "bash $HOME/.claude/hooks/bd-prime-wrapper.sh" }
#           ]
#         }
#       ]
#     }
#   }

set -uo pipefail

BD_BIN="${BD_BIN:-bd}"
ENTRY_TRUNCATE_CHARS="${BD_PRIME_ENTRY_TRUNCATE_CHARS:-200}"
MEMORIES_MAX_BYTES="${BD_PRIME_MEMORIES_MAX_BYTES:-10000}"

# Subagent (sidechain) sessions don't structurally use the bd-prime
# preamble — the dispatch brief carries the intent. Skip silently when
# the stdin payload carries subagent markers (loom-w58) OR when app
# code has set LOOM_SUBAGENT_LEAN=1 to force slim emission (loom-b1l).
INPUT=$(cat 2>/dev/null || true)
# shellcheck source=../lib/subagent-detect.sh
. "$HOME/.claude/lib/subagent-detect.sh" 2>/dev/null || \
  . "$(dirname "${BASH_SOURCE[0]}")/../lib/subagent-detect.sh" 2>/dev/null || true
if declare -F loom_is_subagent_payload >/dev/null 2>&1; then
  loom_is_subagent_payload "$INPUT" && exit 0
fi

# Fail open when bd is not on PATH (loom-svcj): this hook does nothing
# but wrap `bd prime`, so in an apartment / non-loom session without bd
# it should no-op silently rather than fall through to the bd shell-out.
command -v "${BD_BIN}" >/dev/null 2>&1 || exit 0

# --- Fetch raw bd prime output -------------------------------------------

if ! PRIME_RAW=$("$BD_BIN" prime 2>/dev/null); then
  # Silent failure path — never block SessionStart over a missing bd or
  # a non-beads workspace.
  exit 0
fi

# --- Post-process via python (cap memories section) ----------------------

printf '%s' "$PRIME_RAW" | \
  BD_PRIME_ENTRY_TRUNCATE_CHARS="$ENTRY_TRUNCATE_CHARS" \
  BD_PRIME_MEMORIES_MAX_BYTES="$MEMORIES_MAX_BYTES" \
  python3 -c '
import os, re, sys

entry_cap = int(os.environ.get("BD_PRIME_ENTRY_TRUNCATE_CHARS", "200"))
total_cap = int(os.environ.get("BD_PRIME_MEMORIES_MAX_BYTES", "10000"))

text = sys.stdin.read()

# Find the start of the memories section.
mem_re = re.compile(r"^## Persistent Memories\b.*$", re.MULTILINE)
m = mem_re.search(text)
if not m:
    # No memories section — passthrough verbatim.
    sys.stdout.write(text)
    sys.exit(0)

pre = text[: m.start()]
mem_header_line = m.group(0)
body_start = m.end()

# Find end of memories section: next top-level "## " header, or EOF.
end_re = re.compile(r"^## (?!#)", re.MULTILINE)
n = end_re.search(text, body_start)
if n:
    mem_body = text[body_start:n.start()]
    post = text[n.start():]
else:
    mem_body = text[body_start:]
    post = ""

# Split memories body into preamble (before first ### entry) and entries.
# An entry is `^### <key>\n<body until next ### or end>`.
entry_re = re.compile(r"(?ms)^### .+?(?=^### |\Z)")
preamble_end = entry_re.search(mem_body)
if preamble_end:
    mem_preamble = mem_body[: preamble_end.start()]
    entries = entry_re.findall(mem_body)
else:
    mem_preamble = mem_body
    entries = []

def truncate_entry(entry: str) -> str:
    # Entry = header line "### key\n" + body lines.
    lines = entry.split("\n", 1)
    header = lines[0]
    body = lines[1] if len(lines) > 1 else ""
    # Trim trailing blank lines for measurement, then re-add a single \n.
    body = body.rstrip("\n")
    if len(body) > entry_cap:
        body = body[:entry_cap].rstrip() + "..."
    return header + "\n" + body + "\n"

# Build output, capping by total bytes.
out_chunks = [pre, mem_header_line, "\n", mem_preamble]
running = sum(len(c) for c in (mem_header_line, mem_preamble))
kept = 0
elided = 0
for e in entries:
    t = truncate_entry(e)
    if running + len(t) > total_cap and kept > 0:
        elided = len(entries) - kept
        break
    out_chunks.append(t)
    running += len(t)
    kept += 1
else:
    # All entries fit — no elision.
    pass

if elided == 0 and kept < len(entries):
    elided = len(entries) - kept

if elided > 0:
    out_chunks.append(
        f"\n*(... {elided} memory entries elided to keep SessionStart prefix "
        f"small; run `bd memories <keyword>` to fetch full bodies on demand.)*\n"
    )
elif kept > 0 and entries:
    # Note that per-entry truncation may still apply even with no elision.
    if any(len(e) > entry_cap + 100 for e in entries):
        out_chunks.append(
            "\n*(entry bodies truncated to "
            f"{entry_cap} chars; run `bd memories <key>` for full text.)*\n"
        )

if post:
    # Ensure separation between truncated memories and the next section.
    if not out_chunks[-1].endswith("\n"):
        out_chunks.append("\n")
    out_chunks.append(post)

sys.stdout.write("".join(out_chunks))
'
