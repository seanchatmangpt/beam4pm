#!/usr/bin/env bash
# GATE M6 — fresh-user end-to-end playground.
#
# From a fresh `git clone --recurse-submodules` of beam4pm, this single
# command exercises the entire fresh-user workflow: toolchain check ->
# submodules -> manufacture (ggen sync run) -> both BEAM test suites ->
# Gleam build/test/demo -> real process-mining demos in Erlang and Elixir ->
# GATE M5 cross-language roundtrip. It is ops tooling only: every module it
# executes is ggen-manufactured (see the header comment in each file, not directory placement).
#
# Fail-closed discipline (same pattern as ggen-ecosystem's
# tests/test_container_smoke.sh): a missing required tool exits 2 (BLOCKED)
# with the real reason, never a fake pass.
#
# Parity with .github/workflows/beam4pm-ci.yml's `test` job (GENERATED from
# ontology.ttl's bex:ciTest gha:Step facts): the RF1/RF2/RF3 Chicago-style
# `mix test` suites spawn real Rust oracle subprocesses and hard-`raise`/
# `System.fetch_env!` when the oracle binaries or env vars are absent (see
# test/beam4pm_rf1_dfg_test.exs:39-43, test/beam4pm_rf2_conformance_test.exs,
# test/beam4pm_rf3_ocel_test.exs). CI builds those three crates and sources
# scripts/env/rust4pm_reactor_env.sh before `mix test`; step 6/10 and 7/10
# below now do the same so a genuinely fresh clone doesn't fail mid-suite.
set -euo pipefail
cd "$(dirname "$0")/.."

step() { printf '\n== [%s] %s\n' "$1" "$2"; }

step 1/10 "toolchain"
# cargo is required because compiling the :ggen_igniter dep builds its
# oxigraph query engine as a Rustler NIF (see scripts/igniter_sync.sh).
for t in ggen erlc rebar3 elixir mix gleam cargo; do
  if ! command -v "$t" >/dev/null 2>&1; then
    echo "BLOCKED: required tool '$t' not on PATH" >&2
    exit 2
  fi
  printf '  %s: %s\n' "$t" "$(command -v "$t")"
done

step 2/10 "submodules"
git submodule update --init --recursive

step 3/10 "dependencies (hex: ash + ggen_igniter)"
mix deps.get

step 4/10 "manufacture (ggen sync run — the only source authority)"
rm -f ggen.lock
ggen sync run

step 5/10 "Erlang suite (rebar3 eunit)"
rebar3 eunit

step 6/10 "Build rust4pm-Reactor-validation oracle crates (RF1/RF2/RF3)"
# Real Rust subprocess oracles the RF1/RF2/RF3 Chicago tests spawn (thin
# adapters over the real process_mining =0.6.2 function surface, no
# algorithm re-implemented) -- same three crates .github/workflows/
# beam4pm-ci.yml builds before `mix test`.
(cd native/rf1-dfg-oracle && cargo build --release)
(cd native/rf2-conformance-oracle && cargo build --release)
(cd native/rf3-ocel-oracle && cargo build --release)

step 7/10 "Elixir suite (mix test)"
source scripts/env/rust4pm_reactor_env.sh
mix test

step 8/10 "Gleam projection (build + test + demo)"
(cd gleam && gleam build && gleam test && gleam run)

step 9/10 "process-mining demos (Erlang + Elixir)"
DEMO_EBIN="$(mktemp -d)"
trap 'rm -rf "$DEMO_EBIN"' EXIT
erlc -o "$DEMO_EBIN" src/*.erl
escript examples/erlang/dfg_discovery_demo.erl "$DEMO_EBIN"
mix run examples/elixir/dfg_discovery_demo.exs

step 10/10 "GATE M5 cross-language roundtrip"
bash scripts/roundtrip_check.sh

printf '\nPLAYGROUND: end-to-end PASS\n'
