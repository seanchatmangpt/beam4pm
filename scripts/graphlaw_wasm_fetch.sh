#!/usr/bin/env bash
# Install the graphlaw wasm module at native/graphlaw/graphlaw_wasm.wasm.
#   scripts/graphlaw_wasm_fetch.sh [VERSION]      # release asset via gh (default: the pin below)
#   scripts/graphlaw_wasm_fetch.sh --from <path>  # install a local build, print sha256
# Both install paths write the sha256 pin (native/graphlaw/graphlaw_wasm.wasm.sha256) that
# BeamPM.GraphlawAdmission.verify_artifact/1 checks before the engine child is started.
#
# PIN SOURCE: /Users/sac/ash_graphlaw/priv/graphlaw/MANIFEST.json ("graphlaw_version" and
# "artifacts[0].sha256") — the v26.9.29 WASI pin shared with the ash_graphlaw hex package.
# Update both constants together when rotating the pin.
#
# Downloaded artifacts are sha256-verified against GRAPHLAW_PINNED_SHA256 and REFUSED
# (exit 1, REFUSED:GRAPHLAW_WASM_DIGEST_MISMATCH) on mismatch instead of being installed.
# Exit 2 when the release or asset does not exist / cannot be downloaded.
set -euo pipefail

# Pinned upstream (ash_graphlaw priv/graphlaw/MANIFEST.json @ v26.9.29, abi_version 1).
GRAPHLAW_PINNED_VERSION="26.9.29"
GRAPHLAW_PINNED_SHA256="7bb2a7e5ebcef7584b0b960451272d56fa75414d76a12138d41e8973e126eee0"

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

VERSION="${1:-${GRAPHLAW_VERSION:-$GRAPHLAW_PINNED_VERSION}}"
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
  echo "graphlaw_wasm_fetch: REFUSED:GRAPHLAW_WASM_DIGEST_MISMATCH release-asset-sha256=$expected downloaded-sha256=$actual (version $VERSION)" >&2
  exit 1
fi
if [ "$VERSION" = "$GRAPHLAW_PINNED_VERSION" ] && [ "$actual" != "$GRAPHLAW_PINNED_SHA256" ]; then
  echo "graphlaw_wasm_fetch: REFUSED:GRAPHLAW_WASM_PIN_MISMATCH pinned-sha256=$GRAPHLAW_PINNED_SHA256 downloaded-sha256=$actual (version $VERSION == pin $GRAPHLAW_PINNED_VERSION)" >&2
  exit 1
fi

mkdir -p "$(dirname "$DEST")"
cp "$tmp/graphlaw.wasm" "$DEST"
printf '%s\n' "$actual" > "$PIN"
echo "installed $DEST (graphlaw $VERSION, sha256 $actual)"
