#!/usr/bin/env bash
# BeamPM.Pro.Simulation manufacturing script -- beam4pm_pro gap-closure
# item PRO-012 ("what-if simulation over a discovered DFG"). Fully static
# (no graph bindings) -- operates on runtime DFG data, not on ontology-time
# bindings.
set -euo pipefail

PACK="${PACK:-vendor/ggen-marketplace/packs/beam4pm-process-model-pack}"
IGN="$PACK/igniter"

mix deps.get

mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query admitted="$IGN/queries/admitted_actions.rq" \
  --template "$IGN/templates/beam4pm_pro_simulation.ex.eex" \
  --out lib/beam4pm_pro_simulation.ex

mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query admitted="$IGN/queries/admitted_actions.rq" \
  --template "$IGN/templates/beam4pm_pro_simulation_test.exs.eex" \
  --out test/beam4pm_pro_simulation_test.exs
