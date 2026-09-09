#!/usr/bin/env bash
# beam4pm's own independent OCEL v2 network ingestion layer -- the
# manufactured equivalent of ex4pm's retired ex4pm_stream/ex4pm_web
# umbrella apps. NOT a dependency on ex4pm: this generates a real
# Plug.Router decoding straight into beam4pm's own already-admitted
# BeamPM.Types.OcelEvent/OcelObject structs.
#
# Run from the beam4pm repo root. Depends on the pack's igniter assets at
# vendor/ggen-marketplace/packs/beam4pm-process-model-pack/igniter/ and the
# bpmi:AdmittedIngestRoute admission facts appended to this repo's own
# ontology.ttl (same single-file-ontology convention as scripts/
# actuation_sync.sh / scripts/igniter_sync.sh).
#
# Requirements: same as scripts/actuation_sync.sh, plus {:plug, "~> 1.14"}
# for Plug.Router/Plug.Test.
set -euo pipefail

PACK="${PACK:-vendor/ggen-marketplace/packs/beam4pm-process-model-pack}"
IGN="$PACK/igniter"

mix deps.get

# 1. BeamPM.OcelIngest.Router: the Plug.Router admitting only the routes in
#    the bpmi:AdmittedIngestRoute graph, decoding real JSON payloads into
#    real, validating BeamPM.Types.OcelEvent/OcelObject constructors.
mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query routes="$IGN/queries/admitted_ingest_routes.rq" \
  --template "$IGN/templates/beam4pm_ocel_ingest.ex.eex" \
  --out lib/beam4pm_ocel_ingest.ex

# 2. Chicago ExUnit qualification suite: real Plug.Test conns driven
#    through the real generated Router.call/2 pipeline, plus a real
#    BeamPM.Discovery mining pass over real ingested events.
mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query routes="$IGN/queries/admitted_ingest_routes.rq" \
  --template "$IGN/templates/beam4pm_ocel_ingest_test.exs.eex" \
  --out test/beam4pm_ocel_ingest_test.exs

# Verify.
mix compile --warnings-as-errors
mix test test/beam4pm_ocel_ingest_test.exs
