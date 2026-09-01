#!/usr/bin/env bash
# BeamPM.Pro.CapabilityManifest manufacturing script -- beam4pm_pro
# gap-closure item PRO-001 ("current-status truth source"). Fully static
# (no graph bindings -- introspects live repo state at runtime, not RDF
# facts), same dummy-query pattern as claude_workflow_reactor_sync.sh.
set -euo pipefail

PACK="${PACK:-vendor/ggen-marketplace/packs/beam4pm-process-model-pack}"
IGN="$PACK/igniter"

mix deps.get

mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query admitted="$IGN/queries/admitted_actions.rq" \
  --template "$IGN/templates/beam4pm_pro_capability_manifest.ex.eex" \
  --out lib/beam4pm_pro_capability_manifest.ex

mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query admitted="$IGN/queries/admitted_actions.rq" \
  --template "$IGN/templates/beam4pm_pro_capability_manifest_test.exs.eex" \
  --out test/beam4pm_pro_capability_manifest_test.exs
