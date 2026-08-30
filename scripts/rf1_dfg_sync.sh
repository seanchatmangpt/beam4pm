#!/usr/bin/env bash
# BeamPM.RF1.DfgDiscovery manufacturing script -- Reactor-orchestrated,
# subprocess-oracle-backed validation of rust4pm's real discover_dfg
# function surface against canonical wasm4pm datasets. Adapted from the
# rust4pm-Reactor-validation swarm (wf_7cdca56f-f92), independently
# re-verified end-to-end (clean cargo rebuild + fresh mix test) before
# integration. Both templates are fully static (no graph bindings -- the
# oracle-observed constants are baked in from real runs, not queried from
# RDF) -- mix ggen_igniter.sync still requires >=1 --query flag, so this
# passes admitted_actions.rq, whose result these templates never reference
# (same pattern as beam4pm_receipt_chain.ex.eex / scripts/receipt_chain_sync.sh).
set -euo pipefail

PACK="${PACK:-vendor/ggen-marketplace/packs/beam4pm-process-model-pack}"
IGN="$PACK/igniter"

# The test file's oracle_bin path is hardcoded relative to repo root
# (native/rf1-dfg-oracle/target/release/rf1-dfg-oracle) -- build it before
# mix ggen_igniter.sync's own internal `mix test` verification needs it.
(cd native/rf1-dfg-oracle && cargo build --release)

mix deps.get

mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query admitted="$IGN/queries/admitted_actions.rq" \
  --template "$IGN/templates/beam4pm_rf1_dfg.ex.eex" \
  --out lib/beam4pm_rf1_dfg.ex

mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query admitted="$IGN/queries/admitted_actions.rq" \
  --template "$IGN/templates/beam4pm_rf1_dfg_test.exs.eex" \
  --out test/beam4pm_rf1_dfg_test.exs
