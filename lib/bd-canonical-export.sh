#!/usr/bin/env bash
# bd-canonical-export — run `bd export` and emit a BYTE-STABLE canonical form.
#
# Closes loom-0ahj.1 (subsumes loom-n1sk). `bd export` on loom's bd
# (v1.0.2) is NOT byte-stable across repeated runs on unchanged state:
# Go's randomized map iteration emits the `_type:memory` metadata rows
# in a per-process-random order. The issue rows are already position-
# stable; the ONLY non-determinism is a reorder of the memory lines.
# That spurious churn dirties `.beads/issues.jsonl`, which aborts the
# merge driver and strands closes (the loom-n1sk hazard).
#
# This is a thin loom-side canonicalizer: it sorts ONLY the
# `_type:memory` lines into a stable (LC_ALL=C byte) order and leaves
# every issue row in its existing position. Because the real `bd
# export` already emits the memory rows as a contiguous trailing
# block, collecting them to the end is a no-op for issue-row positions
# while guaranteeing a deterministic memory-row order.
#
# UPDATE (loom-hsm7): a v1.0.2 -> v1.0.4 upgrade was attempted and
# VALIDATED, then ROLLED BACK — loom STAYS on v1.0.2. v1.0.4 fixes the
# memory-row reorder upstream (beads #3474/#4086) BUT its throttled
# AUTO-export EXCLUDES memories by default with no working config
# (`export.include-memories` is accepted-but-ignored), so it silently
# strips loom's memories from issues.jsonl on every bd write. v1.0.2 +
# this canonicalizer already deliver determinism, so v1.0.4 is
# net-negative until upstream fixes auto-export. This wrapper is
# RETAINED (D8 — the determinism fix on v1.0.2) and was made
# version-ADAPTIVE here: it feature-detects `--include-memories` and
# passes it where supported, so it ALREADY retains memories on a FUTURE
# v1.0.4 adoption (and its LC_ALL=C sort is idempotent with v1.0.4's
# native sort). On v1.0.2 the flag is absent -> plain `bd export`
# (memories included by default).
#
# Usage:
#   bd-canonical-export.sh            # runs `bd export`, prints canonical JSONL to stdout
#   BD_BIN=/path/to/bd bd-canonical-export.sh
#
# Exit status mirrors `bd export`: a non-zero export propagates non-
# zero, so call sites keep their fail-safe semantics (they must NOT
# overwrite jsonl with empty/garbage on failure).

set -uo pipefail

BD_BIN="${BD_BIN:-bd}"

# loom-hsm7: bd v1.0.4+ EXCLUDES `bd remember` memories from `bd export`
# by default ("may contain sensitive agent context"); they require the
# `--include-memories` flag. bd v1.0.2 has NO such flag and includes
# memories by default. loom commits memories INTO .beads/issues.jsonl,
# so a bare `bd export` on v1.0.4 silently strips every memory row ->
# data loss on the next auto-export. Feature-detect the flag (not the
# version) and pass it where supported, so this canonicalizer retains
# memories on BOTH the controlled v1.0.4 and the downstream-backstop
# v1.0.2. The native v1.0.4 memory-key sort and the LC_ALL=C re-sort
# below are mutually idempotent — byte-stability holds either way.
mem_flag=""
if "$BD_BIN" export --help 2>/dev/null | grep -q -- '--include-memories'; then
  mem_flag="--include-memories"
fi
raw=$("$BD_BIN" export $mem_flag) || exit $?

# Non-memory (issue) rows pass through in input order; `_type:memory`
# rows are collected and sorted into a stable byte order, then appended.
# `sort` runs under LC_ALL=C so the order is locale-independent. The
# `|| true` keeps a no-match `grep` (exit 1) from leaking out as the
# script's exit status — e.g. a workspace with zero `bd remember`
# memories has no memory lines, which is not a failure.
printf '%s\n' "$raw" | grep -v '"_type":"memory"' || true
printf '%s\n' "$raw" | grep '"_type":"memory"' | LC_ALL=C sort

exit 0
