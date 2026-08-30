#!/usr/bin/env bash
# BeamPM.Revenue.Metering manufacturing script -- governed-process-estate
# usage metering (deterministic sha256 event_ids, quantity 1.0/case) plus
# the bill-only-if-entitled admission join (admit_entitled_usage/2) that
# beam4pm_billing's own fieldDoc declares and no generated module implements.
# Both templates are fully static (no graph bindings -- the algorithm binds
# to the EXISTING generated surfaces BeamPM.Billing.UsageEvent.new/1,
# BeamPM.Billing.reconcile/4 and BeamPM.Entitlement.reconcile_entitlement/2,
# not to queried RDF facts) -- mix ggen_igniter.sync still requires >=1
# --query flag, so this passes admitted_actions.rq, whose result these
# templates never reference (same pattern as beam4pm_rf1_dfg.ex.eex /
# scripts/rf1_dfg_sync.sh and beam4pm_receipt_chain.ex.eex /
# scripts/receipt_chain_sync.sh). No cargo step: no native oracle involved.
set -euo pipefail

PACK="${PACK:-vendor/ggen-marketplace/packs/beam4pm-process-model-pack}"
IGN="$PACK/igniter"

mix deps.get

# lib module first: the test file exercises BeamPM.Revenue.Metering (and,
# end-to-end, BeamPM.Revenue.Xes from the economics family), so the module
# must be real before the test renders -- the same compile-order discipline
# scripts/receipt_chain_sync.sh documents.
mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query admitted="$IGN/queries/admitted_actions.rq" \
  --template "$IGN/templates/beam4pm_revenue_metering.ex.eex" \
  --out lib/beam4pm_revenue_metering.ex

mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query admitted="$IGN/queries/admitted_actions.rq" \
  --template "$IGN/templates/beam4pm_revenue_metering_test.exs.eex" \
  --out test/beam4pm_revenue_metering_test.exs
