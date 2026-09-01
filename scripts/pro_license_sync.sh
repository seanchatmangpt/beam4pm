#!/usr/bin/env bash
# BeamPM.Pro.License manufacturing script -- beam4pm_pro gap-closure item
# PRO-007 ("commercial license evidence"). Fully static (no graph bindings).
set -euo pipefail

PACK="${PACK:-vendor/ggen-marketplace/packs/beam4pm-process-model-pack}"
IGN="$PACK/igniter"

mix deps.get

mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query admitted="$IGN/queries/admitted_actions.rq" \
  --template "$IGN/templates/beam4pm_pro_license.ex.eex" \
  --out lib/beam4pm_pro_license.ex

mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query admitted="$IGN/queries/admitted_actions.rq" \
  --template "$IGN/templates/beam4pm_pro_license_test.exs.eex" \
  --out test/beam4pm_pro_license_test.exs
