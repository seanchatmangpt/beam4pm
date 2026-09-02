#!/usr/bin/env bash
# tract_wasm_build.sh -- builds the native/tract-wasm crate (sonos/tract,
# real ONNX inference -- the same crate Wasmtime's own WASI-NN
# implementation uses for this exact target) as a cdylib targeting
# wasm32-wasip1. Hand-authored crate living IN this repo (like
# native/rust4pm-wasm and native/petgraph-wasm), not a git submodule.
# The output module is hosted inside BEAM by wasmex; BeamPM.Tract
# (lib/beam4pm_tract.ex) resolves it at the repo-root-relative path
# printed at the end.
set -euo pipefail
cd "$(dirname "$0")/.."

CRATE_DIR="native/tract-wasm"
WASM_REL="$CRATE_DIR/target/wasm32-wasip1/release/tract_wasm.wasm"

command -v cargo >/dev/null 2>&1 || {
    echo "ERROR: cargo is not installed / not on PATH -- install the Rust" >&2
    echo "toolchain via rustup (https://rustup.rs) first." >&2
    exit 1
}

if command -v rustup >/dev/null 2>&1; then
    rustup target add wasm32-wasip1
else
    SYSROOT="$(rustc --print sysroot 2>/dev/null)" || {
        echo "ERROR: rustc is not runnable -- cannot verify the wasm32-wasip1 target." >&2
        exit 1
    }
    if [ ! -d "$SYSROOT/lib/rustlib/wasm32-wasip1" ]; then
        echo "ERROR: the rust wasm32-wasip1 std is not installed and rustup is" >&2
        echo "not on PATH to install it. Install rustup (https://rustup.rs) and" >&2
        echo "run \`rustup target add wasm32-wasip1\`, then re-run this script." >&2
        exit 1
    fi
fi

(cd "$CRATE_DIR" && cargo build --release --target wasm32-wasip1)

if [ ! -f "$WASM_REL" ]; then
    echo "ERROR: build reported success but no wasm module at $WASM_REL" >&2
    exit 1
fi

ls -la "$WASM_REL"
if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$WASM_REL"
else
    sha256sum "$WASM_REL"
fi

echo "tract wasm engine built at (repo-root-relative, the exact path"
echo "BeamPM.Tract.wasm_path/0 expands): $WASM_REL"
