#!/usr/bin/env bash
# BeamPM.Rf2Conformance manufacturing script -- Reactor-orchestrated,
# subprocess-oracle-backed validation of rust4pm's real Alpha+++ discovery +
# alignment + fitness function surface against a real 4.3MB canonical
# wasm4pm dataset (receipt.xes, 1434 traces). Adapted from the
# rust4pm-Reactor-validation swarm (wf_7cdca56f-f92), independently
# re-verified (clean cargo rebuild, real dup2 stdout-silencing check, fresh
# mix test) before integration.
#
# Unlike RF1/receipt_chain, this template genuinely queries real RDF:
# rf2:ConformanceStream (ontology.ttl) names the oracle/wire-op/dataset/
# module identity, bound via ontology.ttl's real oxigraph engine.
#
# RF2_ORACLE_BIN/RF2_CLEAN_XES/RF2_MUTATED_XES must be set (see
# scripts/env/rust4pm_reactor_env.sh) BEFORE this script runs -- mix
# ggen_igniter.sync's own reactor reconciliation runs mix test as part of
# its verification, and the real subprocess-driven tests need them too.
set -euo pipefail

: "${RF2_ORACLE_BIN:?source scripts/env/rust4pm_reactor_env.sh first}"

PACK="${PACK:-vendor/ggen-marketplace/packs/beam4pm-process-model-pack}"
IGN="$PACK/igniter"

(cd native/rf2-conformance-oracle && cargo build --release)

mix deps.get

mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query spec="$IGN/queries/rf2_spec.rq" \
  --template "$IGN/templates/beam4pm_rf2_conformance.ex.eex" \
  --out lib/beam4pm_rf2_conformance.ex

mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query spec="$IGN/queries/rf2_spec.rq" \
  --template "$IGN/templates/beam4pm_rf2_conformance_test.exs.eex" \
  --out test/beam4pm_rf2_conformance_test.exs
