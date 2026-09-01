#!/usr/bin/env bash
# Per-record-type reference doc fan-out -- transplanted from xaas's real,
# proven --for-each pattern (docs/claude/diataxis/how-to/fix-ash-admin-and-
# use-ggen-for-codegen.md, "Real N-way fan-out from one invocation": 44
# real files from one invocation, idempotent re-run reports "unchanged").
# One docs/reference/types/<record_name>.md per admitted bpm:RecordType
# individual, instead of everything crammed into the single monolithic
# docs/reference/beam4pm_types_reference.md.
set -euo pipefail

PACK="${PACK:-vendor/ggen-marketplace/packs/beam4pm-process-model-pack}"
IGN="$PACK/igniter"

mix deps.get

mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query records="$IGN/queries/records.rq" \
  --query fields="$IGN/queries/fields.rq" \
  --for-each records \
  --template "$IGN/templates/beam4pm_type_page.md.eex" \
  --out "docs/reference/types/<%= record_name %>.md"
