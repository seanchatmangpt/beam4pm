#!/usr/bin/env bash
# BeamPM.Pro.OcpmDiscovery manufacturing script -- beam4pm_pro gap-closure
# item PRO-011 ("object-centric process mining discovery slice"). Fully
# static (no graph bindings) -- operates on runtime OCEL data, not on
# ontology-time bindings.
set -euo pipefail

PACK="${PACK:-vendor/ggen-marketplace/packs/beam4pm-process-model-pack}"
IGN="$PACK/igniter"

mix deps.get

mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query admitted="$IGN/queries/admitted_actions.rq" \
  --template "$IGN/templates/beam4pm_pro_ocpm_discovery.ex.eex" \
  --out lib/beam4pm_pro_ocpm_discovery.ex

mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query admitted="$IGN/queries/admitted_actions.rq" \
  --template "$IGN/templates/beam4pm_pro_ocpm_discovery_test.exs.eex" \
  --out test/beam4pm_pro_ocpm_discovery_test.exs
