#!/usr/bin/env bash
# Real environment for RF2 (BeamPM.Rf2Conformance) and RF3 (BeamPM.RF3Ocel)
# Chicago-style Mix tests -- these spawn real Rust oracle subprocesses
# against real canonical datasets, no mocks. `source` this from beam4pm's
# repo root before `mix test`, `mix ggen_igniter.sync` (its own internal
# verification runs mix compile + mix test too), or in the Dockerfile.
#
# RF1 needs no env var -- its test hardcodes a relative path
# (native/rf1-dfg-oracle/target/release/rf1-dfg-oracle) directly.
ROOT="$(pwd)"

# RF2_CLEAN_XES and the three RF3_N*_FIXTURE paths are real, byte-identical
# checked-in copies of the canonical wasm4pm datasets (qualification/fixtures/
# receipt.xes, n05/n13/n14 -- verified via `diff` against ~/wasm4pm at copy
# time), NOT toy substitutes -- this is what makes the same real data
# portable to CI/Docker, which have no ~/wasm4pm checkout at all.
export RF2_ORACLE_BIN="$ROOT/native/rf2-conformance-oracle/target/release/rf2-conformance-oracle"
export RF2_CLEAN_XES="$ROOT/qualification/fixtures/receipt.xes"
export RF2_MUTATED_XES="$ROOT/qualification/fixtures/mutated_receipt.xes"

export RF3_ORACLE_BIN="$ROOT/native/rf3-ocel-oracle/target/release/rf3-ocel-oracle"
export RF3_POSITIVE_FIXTURE="$ROOT/qualification/fixtures/positive-self-authored.ocel.json"
export RF3_N13_FIXTURE="$ROOT/qualification/fixtures/n13-duplicate-object-id.ocel.json"
export RF3_N14_FIXTURE="$ROOT/qualification/fixtures/n14-undeclared-event-type.ocel.json"
export RF3_N05_FIXTURE="$ROOT/qualification/fixtures/n05-o2o-dangling.ocel.json"
