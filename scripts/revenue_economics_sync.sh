#!/usr/bin/env bash
# BeamPM.Revenue.Economics manufacturing script -- Phase-7 economics layer
# (rework cost, cycle-to-cash, conformance leakage) plus the BeamPM.Revenue.Xes
# :xmerl XES reader, computed over the committed BPI-2020 stratified fixtures
# (qualification/fixtures/bpi2020/*.xes). Both templates are fully static
# (no graph bindings -- the algorithms and pinned fixture constants are baked
# in, not queried from RDF) -- mix ggen_igniter.sync still requires >=1
# --query flag, so this passes admitted_actions.rq, whose result these
# templates never reference (same pattern as beam4pm_rf1_dfg.ex.eex /
# scripts/rf1_dfg_sync.sh and beam4pm_receipt_chain.ex.eex /
# scripts/receipt_chain_sync.sh). No cargo step: this family has no native
# oracle -- every collaborator (BeamPM.Discovery, BeamPM.Precision,
# BeamPM.Types constructors, :xmerl) is already in-tree or OTP built-in.
set -euo pipefail

PACK="${PACK:-vendor/ggen-marketplace/packs/beam4pm-process-model-pack}"
IGN="$PACK/igniter"

mix deps.get

mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query admitted="$IGN/queries/admitted_actions.rq" \
  --template "$IGN/templates/beam4pm_revenue_economics.ex.eex" \
  --out lib/beam4pm_revenue_economics.ex

mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query admitted="$IGN/queries/admitted_actions.rq" \
  --template "$IGN/templates/beam4pm_revenue_economics_test.exs.eex" \
  --out test/beam4pm_revenue_economics_test.exs
