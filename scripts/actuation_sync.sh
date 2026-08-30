#!/usr/bin/env bash
# GATE PI7/PI8 (BRCE actuation leg) - ggen_igniter-manufactured Reactor
# actuation pipeline for beam4pm.
#
# Run from the beam4pm repo root. Depends on the pack's igniter assets at
# vendor/ggen-marketplace/packs/beam4pm-process-model-pack/igniter/, the
# bpma:AdmittedActuation admission facts appended directly to this repo's
# own ontology.ttl (same single-file-ontology convention as every other
# instance-data fragment here -- see scripts/igniter_sync.sh), and the
# fixture gym bridge at qualification/fixtures/toy_gym_bridge.py.
#
# Requirements: same as scripts/igniter_sync.sh ({:ggen_igniter, "~> 26.8"},
# {:ash, "~> 3.0"} - Ash 3.32.1 pulls :reactor 1.0.6 transitively, verified
# in mix.lock; ggen_igniter itself also requires {:reactor, "~> 1.0"}), plus
# python3 on PATH for the gym bridge subprocess.
set -euo pipefail

PACK="${PACK:-vendor/ggen-marketplace/packs/beam4pm-process-model-pack}"
IGN="$PACK/igniter"

mix deps.get

# 1. BeamPM.Actuation + BeamPM.Actuation.GymBridge: the plain `use Reactor`
#    BRCE pipeline (validate -> admit -> execute -> observe+receipt), with
#    the admission allowlist rendered from the bpma:AdmittedActuation graph.
mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query admitted="$IGN/queries/admitted_actions.rq" \
  --query admitted_requires="$IGN/queries/admitted_requires.rq" \
  --template "$IGN/templates/beam4pm_actuation.ex.eex" \
  --out lib/beam4pm_actuation.ex

# 2. Chicago ExUnit qualification suite: real Reactor runs against the real
#    python3 fixture gym bridge (admitted / refused / missing-fact /
#    invalid / bridge-crash paths), receipts mined by BeamPM.Discovery.
mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query admitted="$IGN/queries/admitted_actions.rq" \
  --query admitted_requires="$IGN/queries/admitted_requires.rq" \
  --template "$IGN/templates/beam4pm_actuation_test.exs.eex" \
  --out test/beam4pm_actuation_test.exs

# Verify.
mix compile --warnings-as-errors
mix test
