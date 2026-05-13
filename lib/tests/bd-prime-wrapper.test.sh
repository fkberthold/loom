#!/usr/bin/env bash
# Fixture tests for hooks/bd-prime-wrapper.sh.
#
# Covers loom-nc2: cap verbose `## Persistent Memories` section in
# `bd prime` output so SessionStart prefix stays small (~5 KB instead of
# ~147 KB in liza_base).
#
# Fixture injection point:
#   BD_BIN — path to a fixture bd that emits canned `bd prime` output
#            (matches the BD_BIN pattern in hooks/bd-close-capture.sh).
#
# Optional overrides (defaults baked into the hook):
#   BD_PRIME_ENTRY_TRUNCATE_CHARS  (default 200)
#   BD_PRIME_MEMORIES_MAX_BYTES    (default 10000)
#
# Run:  bash lib/tests/bd-prime-wrapper.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$LOOM_ROOT/hooks/bd-prime-wrapper.sh"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /' | head -40; }

TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Make a fixture bd binary that emits the given file as `bd prime` output.
mk_bd_stub_from_file() {
  local out_file="$1"
  local f="$TMPDIR_ROOT/bd-stub-$RANDOM"
  cat > "$f" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "prime" ]; then
  cat "$out_file"
  exit 0
fi
exit 0
EOF
  chmod +x "$f"
  echo "$f"
}

# Build a bd-prime fixture WITH a verbose memories block.
# $1: path to write fixture to
# $2: number of memory entries
# $3: chars per entry body
mk_prime_with_memories() {
  local out="$1" n="$2" body_len="$3"
  {
    cat <<'HEAD'
# Beads Workflow Context

> Context Recovery: Run `bd prime` after compaction.

## Core Rules
- Default: Use beads for ALL task tracking
- Workflow: bd ready / bd show / bd update --claim / bd close

## Essential Commands
- bd ready
- bd show <id>
- bd close <id>

HEAD
    printf '## Persistent Memories (%d)\n\n' "$n"
    printf 'Stored via `bd remember`. Search with `bd memories <keyword>`.\n\n'
    local i body
    body=$(python3 -c "print('x' * $body_len)")
    for ((i = 1; i <= n; i++)); do
      printf '### entry-%03d-key-name-2026\n' "$i"
      printf 'entry-%03d body: %s\n\n' "$i" "$body"
    done
  } > "$out"
}

# Build a bd-prime fixture with NO memories section.
mk_prime_no_memories() {
  local out="$1"
  cat > "$out" <<'EOF'
# Beads Workflow Context

> Context Recovery: Run `bd prime` after compaction.

## Core Rules
- Default: Use beads for ALL task tracking

## Essential Commands
- bd ready
- bd close <id>

## Common Workflows

Starting work: bd ready; bd show <id>; bd update <id> --claim.
EOF
}

# ---------------------------------------------------------------------------
# 1. Verbose memories → entries truncated + block capped
# ---------------------------------------------------------------------------

echo "==> 1. Verbose memories get truncated and capped"

PRIME_BIG="$TMPDIR_ROOT/prime_big.md"
mk_prime_with_memories "$PRIME_BIG" 100 5000   # 100 entries × 5 KB each ≈ 500 KB
BD_BIG=$(mk_bd_stub_from_file "$PRIME_BIG")

out=$(BD_BIN="$BD_BIG" bash "$HOOK"); rc=$?
out_bytes=$(printf '%s' "$out" | wc -c)
input_bytes=$(wc -c < "$PRIME_BIG")

if [ "$rc" -eq 0 ]; then
  pass "wrapper exits 0 on verbose input"
else
  fail "wrapper non-zero exit (rc=$rc)" "$out"
fi

# Cap: total memories block must be ≤ ~10 KB. Allow some slack for header +
# truncation notice. Whole output should be < 25 KB.
if [ "$out_bytes" -lt 25000 ]; then
  pass "total output capped (${out_bytes} bytes < 25000; input was ${input_bytes})"
else
  fail "output still bloated: ${out_bytes} bytes" "$(printf '%s\n' "$out" | head -5)"
fi

# Pre-memories preamble must be preserved verbatim.
if printf '%s' "$out" | grep -q '^# Beads Workflow Context'; then
  pass "preamble preserved (## Beads Workflow Context header)"
else
  fail "preamble lost"
fi

# Memories header preserved.
if printf '%s' "$out" | grep -qE '^## Persistent Memories'; then
  pass "memories header preserved"
else
  fail "memories header lost"
fi

# Each individual entry truncated to <=~300 chars (200 cap + key header line).
# Use awk to find lines starting with 'entry-' body line and check max len.
max_body_len=$(printf '%s\n' "$out" | awk '/^entry-[0-9]+ body:/ { if (length($0) > max) max = length($0) } END { print max+0 }')
if [ "$max_body_len" -le 300 ]; then
  pass "individual entries truncated (max body line: ${max_body_len} chars ≤ 300)"
else
  fail "entries not truncated (max body line: ${max_body_len})"
fi

# Some entries should be dropped entirely (cap kicks in before 100 entries fit).
entry_count=$(printf '%s\n' "$out" | grep -cE '^### entry-')
if [ "$entry_count" -lt 100 ] && [ "$entry_count" -gt 0 ]; then
  pass "memory entries capped by total bytes (${entry_count} entries kept of 100)"
else
  fail "expected partial entry retention, got ${entry_count}"
fi

# Wrapper writes a truncation notice so the agent knows entries were dropped.
if printf '%s' "$out" | grep -qiE 'truncat|capped|elided|trimmed'; then
  pass "wrapper notes truncation in output"
else
  fail "wrapper silent about truncation" "$(printf '%s' "$out" | tail -20)"
fi

# ---------------------------------------------------------------------------
# 2. No memories block → passthrough verbatim
# ---------------------------------------------------------------------------

echo "==> 2. Passthrough when no memories section is present"

PRIME_NOMEM="$TMPDIR_ROOT/prime_nomem.md"
mk_prime_no_memories "$PRIME_NOMEM"
BD_NOMEM=$(mk_bd_stub_from_file "$PRIME_NOMEM")

out=$(BD_BIN="$BD_NOMEM" bash "$HOOK"); rc=$?
expected=$(cat "$PRIME_NOMEM")
if [ "$rc" -eq 0 ] && [ "$out" = "$expected" ]; then
  pass "no-memories prime passes through unchanged"
else
  fail "no-memories prime altered (rc=$rc)" "diff:\n$(diff <(echo "$expected") <(echo "$out") | head -20)"
fi

# ---------------------------------------------------------------------------
# 3. Short memories block → no truncation (idempotent under cap)
# ---------------------------------------------------------------------------

echo "==> 3. Small memories block left alone"

PRIME_SMALL="$TMPDIR_ROOT/prime_small.md"
mk_prime_with_memories "$PRIME_SMALL" 5 80   # 5 short entries — fits well under 10 KB
BD_SMALL=$(mk_bd_stub_from_file "$PRIME_SMALL")

out=$(BD_BIN="$BD_SMALL" bash "$HOOK"); rc=$?
input_bytes=$(wc -c < "$PRIME_SMALL")
out_bytes=$(printf '%s' "$out" | wc -c)

# All 5 entries should survive.
entry_count=$(printf '%s\n' "$out" | grep -cE '^### entry-')
if [ "$entry_count" -eq 5 ]; then
  pass "all 5 short entries preserved"
else
  fail "expected 5 entries, got ${entry_count}"
fi

# Each entry's body line was 80 chars — should remain ≤200 (under truncation
# threshold), so unchanged.
if printf '%s' "$out" | grep -q 'entry-001 body: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx$'; then
  pass "short entry bodies preserved verbatim"
else
  fail "short entry body unexpectedly altered"
fi

# ---------------------------------------------------------------------------
# 4. Configurable thresholds via env
# ---------------------------------------------------------------------------

echo "==> 4. Env overrides for thresholds"

PRIME_MID="$TMPDIR_ROOT/prime_mid.md"
mk_prime_with_memories "$PRIME_MID" 10 1000
BD_MID=$(mk_bd_stub_from_file "$PRIME_MID")

# Override entry truncation to 50 chars.
out=$(BD_PRIME_ENTRY_TRUNCATE_CHARS=50 BD_BIN="$BD_MID" bash "$HOOK")
max_body_len=$(printf '%s\n' "$out" | awk '/^entry-[0-9]+ body:/ { if (length($0) > max) max = length($0) } END { print max+0 }')
if [ "$max_body_len" -le 150 ]; then  # 50 truncate + small prefix
  pass "BD_PRIME_ENTRY_TRUNCATE_CHARS=50 honored (max body line: ${max_body_len})"
else
  fail "entry truncate override ignored (max ${max_body_len})"
fi

# Override total cap to 500 bytes — should yield very few entries.
out=$(BD_PRIME_MEMORIES_MAX_BYTES=500 BD_BIN="$BD_MID" bash "$HOOK")
entry_count=$(printf '%s\n' "$out" | grep -cE '^### entry-')
if [ "$entry_count" -lt 10 ]; then
  pass "BD_PRIME_MEMORIES_MAX_BYTES=500 honored (only ${entry_count} entries)"
else
  fail "memories byte-cap override ignored (got ${entry_count} entries)"
fi

# ---------------------------------------------------------------------------
# 5. Section detection — only `## Persistent Memories` is treated as memories
# ---------------------------------------------------------------------------

echo "==> 5. Section detection robustness"

# A prime with memories header but ALSO subsequent ## sections (none expected
# in current bd prime, but defend against future structure).
PRIME_TRAIL="$TMPDIR_ROOT/prime_trail.md"
{
  printf '# Beads Workflow Context\n\n'
  printf '## Core Rules\n\n- one\n- two\n\n'
  printf '## Persistent Memories (3)\n\n'
  for i in 1 2 3; do
    printf '### key-%d\n' "$i"
    python3 -c "print('z' * 5000)"
    printf '\n'
  done
} > "$PRIME_TRAIL"
BD_TRAIL=$(mk_bd_stub_from_file "$PRIME_TRAIL")

out=$(BD_BIN="$BD_TRAIL" bash "$HOOK")

# Core Rules section (before memories) preserved verbatim including bullets.
if printf '%s' "$out" | grep -q '^## Core Rules' && printf '%s' "$out" | grep -q '^- one$'; then
  pass "sections before memories preserved verbatim"
else
  fail "pre-memories section disturbed" "$(printf '%s' "$out" | head -15)"
fi

# Each verbose entry body line (5000 chars of 'z') truncated. After
# truncation the body becomes "zzz...zzz..." so we check the longest
# line in the whole output stays small.
max_line=$(printf '%s\n' "$out" | awk '{ if (length($0) > max) max = length($0) } END { print max+0 }')
if [ "$max_line" -le 300 ]; then
  pass "verbose entry bodies truncated (longest output line: ${max_line})"
else
  fail "verbose bodies not truncated (longest line: ${max_line})"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
echo "Tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
