#!/usr/bin/env bash
# rust4pm_wasm_build.sh -- builds the ONE process-mining engine: the
# native/rust4pm-wasm crate (process_mining =0.6.2, default-features off --
# several default features do not compile for wasm32-wasip1) as a cdylib
# targeting wasm32-wasip1. The output module is hosted inside BEAM by
# wasmex; BeamPM.Rust4PM (lib/beam4pm_rust4pm.ex) resolves it at the
# repo-root-relative path printed at the end, and the Erlang/Gleam facades
# delegate to that module -- no process-mining algorithm exists outside
# this .wasm. Architecture spike-proven end-to-end (29MB XES import,
# log_stats, discover_dfg) before this crate was integrated.
#
# Same crate conventions as native/rf1-dfg-oracle / rf2-conformance-oracle:
# Cargo.lock IS committed, native/*/target/ is gitignored (rebuilt here, by
# the Dockerfile, and by CI).
set -euo pipefail
cd "$(dirname "$0")/.."

CRATE_DIR="native/rust4pm-wasm"
WASM_REL="$CRATE_DIR/target/wasm32-wasip1/release/rust4pm_wasm.wasm"

# --- real-toolchain guards: fail actionably, never silently ---------------
command -v cargo >/dev/null 2>&1 || {
    echo "ERROR: cargo is not installed / not on PATH -- install the Rust" >&2
    echo "toolchain via rustup (https://rustup.rs) first." >&2
    exit 1
}

if command -v rustup >/dev/null 2>&1; then
    # Idempotent: a no-op when the target's std is already installed.
    rustup target add wasm32-wasip1
else
    # No rustup (e.g. distro cargo): verify the target std is present the
    # same way scripts/oracle_check.sh does, and say exactly what is missing.
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

# --- build ----------------------------------------------------------------
(cd "$CRATE_DIR" && cargo build --release --target wasm32-wasip1)

# --- verify the artifact the Elixir wrapper resolves actually exists ------
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

echo "rust4pm wasm engine built at (repo-root-relative, the exact path"
echo "BeamPM.Rust4PM.wasm_path/0 expands): $WASM_REL"
