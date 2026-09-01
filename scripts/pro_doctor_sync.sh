#!/usr/bin/env bash
# BeamPM.Pro.Doctor manufacturing script -- beam4pm_pro gap-closure item
# PRO-008 ("product doctor / support bundle"). Fully static (no graph bindings).
set -euo pipefail

PACK="${PACK:-vendor/ggen-marketplace/packs/beam4pm-process-model-pack}"
IGN="$PACK/igniter"

mix deps.get

mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query admitted="$IGN/queries/admitted_actions.rq" \
  --template "$IGN/templates/beam4pm_pro_doctor.ex.eex" \
  --out lib/beam4pm_pro_doctor.ex

mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query admitted="$IGN/queries/admitted_actions.rq" \
  --template "$IGN/templates/beam4pm_pro_doctor_test.exs.eex" \
  --out test/beam4pm_pro_doctor_test.exs
