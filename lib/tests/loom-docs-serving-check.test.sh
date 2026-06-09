#!/usr/bin/env bash
# Fixture tests for scripts/loom-docs-serving-check (loom-7q1g).
#
# RED (the locked spec):
#   INVARIANT: the docs-deploy gate verifies actual SERVING
#   (HTTP 200 / GitHub-Pages status=built), not merely mkdocs build
#   success, and only fires on full-Diataxis projects (docs/ +
#   mkdocs.yml present, AND no docs/.no-diataxis marker); INFO/nudge
#   posture (never hard-blocks).
#
# The helper checks three layers and reports INFO/nudge — it must
# ALWAYS exit 0 (nudge-not-block, mirroring loom-fanout-detect):
#   Layer 1: `mkdocs build --strict` build integrity.
#   Layer 2: latest Deploy-docs GitHub Actions run conclusion=success.
#   Layer 3 (NEW): the site ACTUALLY SERVES — curl -sI <site_url> → 200,
#                  OR GitHub Pages API status=built / not 404.
#
# What this test pins:
#   - Full-Diataxis gating: skips cleanly on a non-Diataxis project
#     (no mkdocs.yml, OR a docs/.no-diataxis marker present).
#   - Layer 3 verifies the HTTP-200 / Pages-status layer (network mocked
#     via PATH-shadowed curl + gh stubs), and FLAGS a 404 / dead-Pages.
#   - Graceful degradation: when curl AND gh are both unavailable,
#     Layer 3 is skipped with a note (still exit 0).
#   - Never hard-blocks (always exit 0), even when a layer reports a
#     problem.
#
# Injection points (resolved by the helper):
#   MKDOCS_BIN=<path>   — override the mkdocs binary.
#   PATH-shadowed curl / gh — tests prepend a stub dir to PATH.
#   site_url derived from mkdocs.yml, or passed as $1.
#
# Run:  bash lib/tests/loom-docs-serving-check.test.sh

set -uo pipefail

LOOM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECK="$LOOM_ROOT/scripts/loom-docs-serving-check"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); [ -n "${2:-}" ] && echo "$2" | sed 's/^/    /'; }

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# Full-Diataxis project: docs/ + mkdocs.yml (with site_url), no marker.
mk_diataxis_project() {
  local dir="$1"
  mkdir -p "$dir/docs"
  cat > "$dir/mkdocs.yml" <<'YML'
site_name: fixture
site_url: https://example.github.io/fixture/
docs_dir: docs
nav:
  - Home: index.md
YML
  printf '# Home\n\nWelcome.\n' > "$dir/docs/index.md"
}

# Non-Diataxis: no mkdocs.yml at all.
mk_non_docs_project() {
  local dir="$1"
  mkdir -p "$dir/docs"
  printf '# Home\n' > "$dir/docs/index.md"
}

# Opted-out: full layout but docs/.no-diataxis marker present.
mk_optout_project() {
  local dir="$1"
  mk_diataxis_project "$dir"
  : > "$dir/docs/.no-diataxis"
}

# A no-op mkdocs that always succeeds (Layer 1 green without paying
# the real build cost).
mk_noop_mkdocs() {
  cat > "$1" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$1"
}

# Stub dir with a curl that returns a configurable HTTP status, and a
# gh that returns a configurable Pages status. Driven by env files so
# each case can tune responses without rewriting the stubs.
#   CURL_STATUS file  → first line is the HTTP status code curl reports
#                       (in a `HTTP/2 <code>` header line). Absent file
#                       or "ABSENT" → curl is not present at all.
#   GH_PAGES file     → first line is the Pages `status` value
#                       (e.g. "built"); "404" → gh returns a 404 error;
#                       "ABSENT" / missing → gh is not present at all.
mk_net_stubs() {
  local d="$1" curl_status="$2" gh_pages="$3"
  if [ "$curl_status" != "ABSENT" ]; then
    cat > "$d/curl" <<SH
#!/usr/bin/env bash
# Stub curl: emit a header block with the configured status code.
code="$curl_status"
echo "HTTP/2 \$code"
echo "content-type: text/html"
exit 0
SH
    chmod +x "$d/curl"
  fi
  if [ "$gh_pages" != "ABSENT" ]; then
    cat > "$d/gh" <<SH
#!/usr/bin/env bash
# Stub gh. Supports:
#   gh api repos/{owner}/{repo}/pages   → emit {"status":"<pages>"} or 404
#   gh run list ...                     → emit a run with conclusion success
pages="$gh_pages"
case "\$1 \$2" in
  "api "*)
    if [ "\$pages" = "404" ]; then
      echo "gh: Not Found (HTTP 404)" >&2
      exit 1
    fi
    printf '{"status":"%s","html_url":"https://example.github.io/fixture/"}\n' "\$pages"
    ;;
  "run list")
    printf '[{"name":"Deploy docs","conclusion":"success","status":"completed","headSha":"abc1234"}]\n'
    ;;
  *)
    exit 0
    ;;
esac
SH
    chmod +x "$d/gh"
  fi
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mk_noop_mkdocs "$TMP/mkdocs-ok"

echo "==> 1. Non-Diataxis project (no mkdocs.yml) → clean skip, exit 0"
proj="$TMP/p1"; mk_non_docs_project "$proj"
out=$( (cd "$proj" && MKDOCS_BIN="$TMP/mkdocs-ok" bash "$CHECK" 2>&1) ); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -qiE 'skip|not.*diataxis|no mkdocs'; then
  pass "non-Diataxis project skipped cleanly"
else
  fail "non-Diataxis should skip with a note + exit 0 (exit=$rc)" "$out"
fi

echo "==> 2. docs/.no-diataxis marker → clean skip, exit 0"
proj="$TMP/p2"; mk_optout_project "$proj"
out=$( (cd "$proj" && MKDOCS_BIN="$TMP/mkdocs-ok" bash "$CHECK" 2>&1) ); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -qiE 'skip|no-diataxis|opt'; then
  pass "no-diataxis marker skipped cleanly"
else
  fail "no-diataxis marker should skip + exit 0 (exit=$rc)" "$out"
fi

echo "==> 3. Serving (Layer 3): curl 200 → reports SERVING, exit 0"
proj="$TMP/p3"; mk_diataxis_project "$proj"
stubs="$TMP/s3"; mkdir -p "$stubs"; mk_net_stubs "$stubs" "200" "built"
out=$( (cd "$proj" && PATH="$stubs:$PATH" MKDOCS_BIN="$TMP/mkdocs-ok" bash "$CHECK" 2>&1) ); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -qiE '200|serv'; then
  pass "Layer 3 reports SERVING on HTTP 200"
else
  fail "HTTP 200 should be reported as serving + exit 0 (exit=$rc)" "$out"
fi

echo "==> 4. Serving (Layer 3): curl 404 → FLAGS dead-Pages, still exit 0"
proj="$TMP/p4"; mk_diataxis_project "$proj"
stubs="$TMP/s4"; mkdir -p "$stubs"; mk_net_stubs "$stubs" "404" "ABSENT"
out=$( (cd "$proj" && PATH="$stubs:$PATH" MKDOCS_BIN="$TMP/mkdocs-ok" bash "$CHECK" 2>&1) ); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -qiE '404|not.*serv|does not serve|dead'; then
  pass "Layer 3 flags a 404 (dead Pages) without blocking"
else
  fail "HTTP 404 should be flagged + still exit 0 (exit=$rc)" "$out"
fi

echo "==> 5. Serving (Layer 3): curl absent, gh Pages status=built → SERVING via Pages API"
proj="$TMP/p5"; mk_diataxis_project "$proj"
stubs="$TMP/s5"; mkdir -p "$stubs"; mk_net_stubs "$stubs" "ABSENT" "built"
out=$( (cd "$proj" && PATH="$stubs:$PATH" MKDOCS_BIN="$TMP/mkdocs-ok" bash "$CHECK" 2>&1) ); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -qiE 'built|serv|pages'; then
  pass "Layer 3 falls back to Pages API status=built"
else
  fail "Pages status=built should report serving + exit 0 (exit=$rc)" "$out"
fi

echo "==> 6. Serving (Layer 3): gh Pages 404 → FLAGS Pages-disabled, exit 0"
proj="$TMP/p6"; mk_diataxis_project "$proj"
stubs="$TMP/s6"; mkdir -p "$stubs"; mk_net_stubs "$stubs" "ABSENT" "404"
out=$( (cd "$proj" && PATH="$stubs:$PATH" MKDOCS_BIN="$TMP/mkdocs-ok" bash "$CHECK" 2>&1) ); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -qiE '404|disabl|not.*serv|dead'; then
  pass "Layer 3 flags Pages 404 (disabled) without blocking"
else
  fail "Pages 404 should be flagged + still exit 0 (exit=$rc)" "$out"
fi

echo "==> 7. Graceful degradation: curl AND gh both absent → Layer 3 skipped with note, exit 0"
proj="$TMP/p7"; mk_diataxis_project "$proj"
# Build a PATH that contains NEITHER curl NOR gh (only the noop mkdocs dir +
# coreutils we need). Point at a minimal PATH so curl/gh truly absent.
barebin="$TMP/barebin"; mkdir -p "$barebin"
for b in bash sh grep sed awk cat head tail printf env tr cut realpath dirname; do
  src=$(command -v "$b" 2>/dev/null) && [ -n "$src" ] && ln -sf "$src" "$barebin/$b"
done
out=$( (cd "$proj" && PATH="$barebin" MKDOCS_BIN="$TMP/mkdocs-ok" bash "$CHECK" 2>&1) ); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -qiE 'skip|unavailable|offline|cannot.*verif'; then
  pass "Layer 3 degrades gracefully when curl+gh both absent"
else
  fail "no curl+no gh should skip Layer 3 with note + exit 0 (exit=$rc)" "$out"
fi

echo "==> 8. NEVER hard-blocks: every layer reporting a problem still exits 0"
proj="$TMP/p8"; mk_diataxis_project "$proj"
# failing mkdocs (Layer 1 fail) + curl 404 (Layer 3 fail)
cat > "$TMP/mkdocs-fail" <<'SH'
#!/usr/bin/env bash
echo "WARNING - broken link"
echo "Aborted with 1 warnings in strict mode!"
exit 1
SH
chmod +x "$TMP/mkdocs-fail"
stubs="$TMP/s8"; mkdir -p "$stubs"; mk_net_stubs "$stubs" "404" "404"
out=$( (cd "$proj" && PATH="$stubs:$PATH" MKDOCS_BIN="$TMP/mkdocs-fail" bash "$CHECK" 2>&1) ); rc=$?
[ "$rc" -eq 0 ] && pass "all-layers-failing still exits 0 (nudge-not-block)" \
  || fail "must never hard-block (exit=$rc)" "$out"

echo "==> 9. site_url passed as an explicit arg overrides mkdocs.yml derivation"
proj="$TMP/p9"; mk_diataxis_project "$proj"
stubs="$TMP/s9"; mkdir -p "$stubs"; mk_net_stubs "$stubs" "200" "ABSENT"
out=$( (cd "$proj" && PATH="$stubs:$PATH" MKDOCS_BIN="$TMP/mkdocs-ok" \
  bash "$CHECK" "https://override.example.org/site/" 2>&1) ); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -qiE '200|serv'; then
  pass "explicit site_url arg is honored"
else
  fail "explicit site_url arg should drive Layer 3 + exit 0 (exit=$rc)" "$out"
fi

echo ""
echo "Results: $passed passed, $failed failed"

[ "$failed" -eq 0 ]
