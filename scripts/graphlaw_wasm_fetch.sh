#!/usr/bin/env bash
# Install the graphlaw wasm module at native/graphlaw/graphlaw_wasm.wasm.
#   scripts/graphlaw_wasm_fetch.sh [VERSION]      # release asset via gh (default $GRAPHLAW_VERSION)
#   scripts/graphlaw_wasm_fetch.sh --from <path>  # install a local build, print sha256
# Both install paths write the sha256 pin (native/graphlaw/graphlaw_wasm.wasm.sha256) that
# BeamPM.GraphlawAdmission.verify_artifact/1 checks before the engine child is started.
# Exit 2 when the release or asset does not exist / cannot be downloaded.
set -euo pipefail

REPO="seanchatmangpt/graphlaw"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/native/graphlaw/graphlaw_wasm.wasm"
PIN="$DEST.sha256"

sha256_of() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'; else shasum -a 256 "$1" | awk '{print $1}'; fi; }

if [ "${1:-}" = "--from" ]; then
  src="${2:-}"
  [ -n "$src" ] && [ -f "$src" ] || { echo "graphlaw_wasm_fetch: --from needs an existing file" >&2; exit 2; }
  mkdir -p "$(dirname "$DEST")"
  cp "$src" "$DEST"
  sha256_of "$DEST" > "$PIN"
  echo "installed $DEST"
  echo "sha256 $(cat "$PIN")"
  exit 0
fi

VERSION="${1:-${GRAPHLAW_VERSION:-}}"
[ -n "$VERSION" ] || { echo "graphlaw_wasm_fetch: set GRAPHLAW_VERSION or pass a version" >&2; exit 2; }
command -v gh >/dev/null 2>&1 || { echo "graphlaw_wasm_fetch: gh CLI not found" >&2; exit 2; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if ! gh release download "$VERSION" --repo "$REPO" --dir "$tmp" \
     --pattern graphlaw.wasm --pattern graphlaw.wasm.sha256 2>"$tmp/err"; then
  echo "graphlaw_wasm_fetch: release $VERSION (or its graphlaw.wasm assets) not available in $REPO:" >&2
  sed 's/^/  /' "$tmp/err" >&2
  echo "Build locally and use: $0 --from <path-to-graphlaw_wasm.wasm>" >&2
  exit 2
fi

expected="$(awk '{print $1; exit}' "$tmp/graphlaw.wasm.sha256")"
actual="$(sha256_of "$tmp/graphlaw.wasm")"
if [ "$expected" != "$actual" ]; then
  echo "graphlaw_wasm_fetch: CHECKSUM MISMATCH expected=$expected actual=$actual" >&2
  exit 1
fi

mkdir -p "$(dirname "$DEST")"
cp "$tmp/graphlaw.wasm" "$DEST"
printf '%s\n' "$actual" > "$PIN"
echo "installed $DEST (graphlaw $VERSION, sha256 $actual)"
