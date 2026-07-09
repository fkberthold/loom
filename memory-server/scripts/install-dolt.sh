#!/usr/bin/env bash
# memory-server/scripts/install-dolt.sh — self-contained, no-root dolt
# install. Downloads the official linux-amd64 release tarball straight
# into memory-server/bin/dolt (gitignored — never committed; a 40+MB
# binary has no place in a markdown+bash repo). Idempotent: a no-op if
# bin/dolt already exists and reports a working version.
#
# Pinned to the version validated by SPIKE-1 (loom-zu91): 2.1.10. Set
# LOOM_DOLT_VERSION to override.
#
# Usage: scripts/install-dolt.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEMSERVER_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN_DIR="$MEMSERVER_ROOT/bin"
DOLT_BIN="$BIN_DIR/dolt"

DOLT_VERSION="${LOOM_DOLT_VERSION:-2.1.10}"

mkdir -p "$BIN_DIR"

if [ -x "$DOLT_BIN" ]; then
  INSTALLED_VERSION=$("$DOLT_BIN" version 2>/dev/null | awk '/dolt version/{print $3}')
  if [ -n "$INSTALLED_VERSION" ]; then
    echo "install-dolt: $DOLT_BIN already present (version $INSTALLED_VERSION) — skipping download." >&2
    exit 0
  fi
  echo "install-dolt: $DOLT_BIN exists but did not report a version — reinstalling." >&2
fi

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) PLATFORM=linux-amd64 ;;
  aarch64|arm64) PLATFORM=linux-arm64 ;;
  *) echo "install-dolt: unsupported architecture '$ARCH' — only linux-amd64/arm64 are handled." >&2; exit 1 ;;
esac

URL="https://github.com/dolthub/dolt/releases/download/v${DOLT_VERSION}/dolt-${PLATFORM}.tar.gz"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "install-dolt: downloading dolt $DOLT_VERSION ($PLATFORM) from $URL ..." >&2
curl -sL --max-time 180 "$URL" -o "$WORK_DIR/dolt.tar.gz"
tar xzf "$WORK_DIR/dolt.tar.gz" -C "$WORK_DIR"

cp "$WORK_DIR/dolt-${PLATFORM}/bin/dolt" "$DOLT_BIN"
chmod +x "$DOLT_BIN"

echo "install-dolt: installed $("$DOLT_BIN" version)" >&2
echo "install-dolt: binary at $DOLT_BIN (gitignored, not committed)." >&2
