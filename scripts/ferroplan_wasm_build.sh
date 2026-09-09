#!/usr/bin/env bash
# ferroplan_wasm_build.sh -- builds the ferroplan planning engine (a second,
# independent BEAM-hosted WASM engine alongside rust4pm-wasm's process-mining
# engine): the ferroplan-wasm crate inside the native/ferroplan git submodule
# (seanchatmangpt/ferroplan, pinned at the checked-out commit) as a cdylib
# targeting wasm32-wasip1, exporting the same linear-memory JSON ABI shape as
# rust4pm-wasm -- fp_alloc/fp_call/fp_dealloc rather than
# r4pm_alloc/r4pm_call/r4pm_dealloc (see docs/reference/ferroplan-wasm-beam.md).
# The output module is hosted inside BEAM by wasmex; BeamPM.Ferroplan
# (lib/beam4pm_ferroplan.ex) resolves it at the repo-root-relative path
# printed at the end.
#
# Unlike native/rust4pm-wasm (a hand-authored crate living IN this repo),
# native/ferroplan is a git submodule: the ABI lives upstream in ferroplan's
# own repo (crates/ferroplan-wasm/src/wasi_abi.rs), built here by pointing
# cargo at the submodule's manifest -- no source is duplicated into beam4pm.
# Same conventions as rust4pm-wasm's build: native/ferroplan/target/ is
# gitignored (rebuilt here, by the Dockerfile, and by CI); the submodule
# commit pin (not Cargo.lock) is what's versioned in this repo.
set -euo pipefail
cd "$(dirname "$0")/.."

SUBMODULE_DIR="native/ferroplan"
MANIFEST="$SUBMODULE_DIR/Cargo.toml"
WASM_REL="$SUBMODULE_DIR/target/wasm32-wasip1/release/ferroplan_wasm.wasm"

# --- real-toolchain guards: fail actionably, never silently ---------------
command -v cargo >/dev/null 2>&1 || {
    echo "ERROR: cargo is not installed / not on PATH -- install the Rust" >&2
    echo "toolchain via rustup (https://rustup.rs) first." >&2
    exit 1
}

if [ ! -f "$MANIFEST" ]; then
    echo "ERROR: $SUBMODULE_DIR is empty -- run" >&2
    echo "  git submodule update --init --recursive" >&2
    echo "first, then re-run this script." >&2
    exit 1
fi

if command -v rustup >/dev/null 2>&1; then
    # Idempotent: a no-op when the target's std is already installed.
    rustup target add wasm32-wasip1
else
    # No rustup (e.g. distro cargo): verify the target std is present the
    # same way rust4pm_wasm_build.sh does, and say exactly what is missing.
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

# --- build ------------------------------------------------------------------
# -p ferroplan-wasm: the submodule is ferroplan's own multi-crate workspace;
# only the wasm adapter crate (and its wasi_abi module, cfg-gated to
# wasm32-wasip1) needs building here, not the CLI/MCP/bevy crates.
cargo build -p ferroplan-wasm --release --target wasm32-wasip1 --manifest-path "$MANIFEST"

# --- verify the artifact the Elixir wrapper resolves actually exists --------
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

echo "ferroplan wasm engine built at (repo-root-relative, the exact path"
echo "BeamPM.Ferroplan.wasm_path/0 expands): $WASM_REL"
