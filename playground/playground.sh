#!/usr/bin/env bash
# GATE M6 — fresh-user end-to-end playground.
#
# From a fresh `git clone --recurse-submodules` of beam4pm, this single
# command exercises the entire fresh-user workflow: toolchain check ->
# submodules -> manufacture (ggen sync run) -> both BEAM test suites ->
# Gleam build/test/demo -> real process-mining demos in Erlang and Elixir ->
# GATE M5 cross-language roundtrip. It is ops tooling only: every module it
# executes is ggen-manufactured under generated/.
#
# Fail-closed discipline (same pattern as ggen-ecosystem's
# tests/test_container_smoke.sh): a missing required tool exits 2 (BLOCKED)
# with the real reason, never a fake pass.
set -euo pipefail
cd "$(dirname "$0")/.."

step() { printf '\n== [%s] %s\n' "$1" "$2"; }

step 1/8 "toolchain"
for t in ggen erlc rebar3 elixir mix gleam; do
  if ! command -v "$t" >/dev/null 2>&1; then
    echo "BLOCKED: required tool '$t' not on PATH" >&2
    exit 2
  fi
  printf '  %s: %s\n' "$t" "$(command -v "$t")"
done

step 2/8 "submodules"
git submodule update --init --recursive

step 3/8 "manufacture (ggen sync run — the only source authority)"
rm -f ggen.lock
ggen sync run

step 4/8 "Erlang suite (rebar3 eunit)"
rebar3 eunit

step 5/8 "Elixir suite (mix test)"
mix test

step 6/8 "Gleam projection (build + test + demo)"
(cd generated/gleam && gleam build && gleam test && gleam run)

step 7/8 "process-mining demos (Erlang + Elixir)"
DEMO_EBIN="$(mktemp -d)"
trap 'rm -rf "$DEMO_EBIN"' EXIT
erlc -o "$DEMO_EBIN" generated/erlang/src/*.erl
escript examples/erlang/dfg_discovery_demo.erl "$DEMO_EBIN"
mix run examples/elixir/dfg_discovery_demo.exs

step 8/8 "GATE M5 cross-language roundtrip"
bash scripts/roundtrip_check.sh

printf '\nPLAYGROUND: end-to-end PASS\n'
