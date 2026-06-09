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
# It delivers byte-stability on the CURRENT bd without upgrading the
# global binary — the backstop for downstream projects on an
# uncontrolled bd version. (The pinned v1.0.4 upgrade, which fixes
# this upstream, is handled separately; this wrapper can be retired
# once every consumer is on a deterministic bd.)
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

raw=$("$BD_BIN" export) || exit $?

# Non-memory (issue) rows pass through in input order; `_type:memory`
# rows are collected and sorted into a stable byte order, then appended.
# `sort` runs under LC_ALL=C so the order is locale-independent. The
# `|| true` keeps a no-match `grep` (exit 1) from leaking out as the
# script's exit status — e.g. a workspace with zero `bd remember`
# memories has no memory lines, which is not a failure.
printf '%s\n' "$raw" | grep -v '"_type":"memory"' || true
printf '%s\n' "$raw" | grep '"_type":"memory"' | LC_ALL=C sort

exit 0
