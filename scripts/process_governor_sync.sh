#!/usr/bin/env bash
# GATE PI7/PI8 extension: BeamPM.ProcessGovernor - named, ordered, exact-
# state-hash-fenced multi-step process governance layered on top of the
# real BeamPM.Actuation Reactor pipeline (scripts/actuation_sync.sh). Every
# admit/execute/receipt decision is DELEGATED to BeamPM.Actuation.run/2 --
# this module never reimplements admission or execution. See
# docs/jira/v26.8.29/21-governor-first-principles-rewrite.md for the audit
# that led to this design replacing the original (removed) BeamPM.Governor.
#
# Depends on: the bpmg:ProcessContract/bpmg:ProcessTransition instance data
# appended to this repo's own ontology.ttl, BeamPM.Actuation already
# manufactured (run scripts/actuation_sync.sh first), and the fixture gym
# bridge at qualification/fixtures/toy_gym_bridge.py.
set -euo pipefail

PACK="${PACK:-vendor/ggen-marketplace/packs/beam4pm-process-model-pack}"
IGN="$PACK/igniter"

mix deps.get

mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query transitions="$IGN/queries/process_transitions.rq" \
  --template "$IGN/templates/beam4pm_process_governor.ex.eex" \
  --out lib/beam4pm_process_governor.ex

mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query transitions="$IGN/queries/process_transitions.rq" \
  --template "$IGN/templates/beam4pm_process_governor_test.exs.eex" \
  --out test/beam4pm_process_governor_test.exs

# Verify.
mix compile --warnings-as-errors
mix test
