#!/usr/bin/env bash
# BeamPM.RF3Ocel manufacturing script -- Reactor-orchestrated,
# subprocess-oracle-backed validation of rust4pm's real OCEL 2.0
# slim-binding function surface (bindings::slim_link_ocel, SlimLinkedOCEL
# construction) against a real self-authored positive fixture and three
# real adversarial fixtures from wasm4pm/fixtures/negative/ (n05, n13,
# n14). Adapted from the rust4pm-Reactor-validation swarm
# (wf_7cdca56f-f92), independently re-verified before integration.
#
# Fully static template (zero EEx interpolation, like beam4pm_rf1_dfg.ex.eex)
# -- mix ggen_igniter.sync still requires >=1 --query flag, so this passes
# admitted_actions.rq, whose result this template never references.
#
# RF3_ORACLE_BIN/RF3_POSITIVE_FIXTURE/RF3_N13_FIXTURE/RF3_N14_FIXTURE/
# RF3_N05_FIXTURE must be set (see scripts/env/rust4pm_reactor_env.sh)
# BEFORE this script runs -- mix ggen_igniter.sync's own reactor
# reconciliation runs mix test as part of its verification.
set -euo pipefail

: "${RF3_ORACLE_BIN:?source scripts/env/rust4pm_reactor_env.sh first}"

PACK="${PACK:-vendor/ggen-marketplace/packs/beam4pm-process-model-pack}"
IGN="$PACK/igniter"

(cd native/rf3-ocel-oracle && cargo build --release)

mix deps.get

mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query admitted="$IGN/queries/admitted_actions.rq" \
  --template "$IGN/templates/beam4pm_rf3_ocel.ex.eex" \
  --out lib/beam4pm_rf3_ocel.ex

mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query admitted="$IGN/queries/admitted_actions.rq" \
  --template "$IGN/templates/beam4pm_rf3_ocel_test.exs.eex" \
  --out test/beam4pm_rf3_ocel_test.exs
