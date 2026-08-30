#!/usr/bin/env bash
# BeamPM.ReceiptChain manufacturing script -- hash-chained beam4pm-brce/v1
# receipts, adapted from ex4pm's real Ex4pm.Evidence.Replay.Chain. Purely
# additive/opt-in (see the module's own moduledoc). This template is fully
# static (no graph bindings), so no --ontology/--query flags are needed.
set -euo pipefail

PACK="${PACK:-vendor/ggen-marketplace/packs/beam4pm-process-model-pack}"
IGN="$PACK/igniter"

mix deps.get

# Real compile-order dependency chain, each step verified by
# ggen_igniter's own reactor reconciliation (mix compile + mix test) before
# the next step runs:
#   1. lib/beam4pm_receipt_chain.ex (static, no deps) must exist before...
#   2. beam4pm_actuation.ex, which now calls BeamPM.ReceiptChain.link_fields/2
#   3. beam4pm_process_governor.ex, which delegates to BeamPM.Actuation.run/2
#   4. test/beam4pm_receipt_chain_test.exs LAST -- it exercises BOTH
#      BeamPM.ReceiptChain directly AND BeamPM.ProcessGovernor.run/2 (the
#      composition test), so it must not render until every module it calls
#      is real. Rendering it earlier is exactly the ordering bug GATE M2
#      caught for real: "BeamPM.ProcessGovernor.run/2 is undefined".
#
# beam4pm_receipt_chain.ex.eex is fully static (no graph bindings) --
# mix ggen_igniter.sync still requires at least one --query flag, so this
# passes a real, harmless one (admitted_actions.rq) whose result the
# template never references.
mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query admitted="$IGN/queries/admitted_actions.rq" \
  --template "$IGN/templates/beam4pm_receipt_chain.ex.eex" \
  --out lib/beam4pm_receipt_chain.ex

# The extended templates render through their EXISTING sync scripts --
# re-run those so the additive chain_id/link_fields support lands before
# the composition test needs them.
bash scripts/actuation_sync.sh
bash scripts/process_governor_sync.sh

mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query admitted="$IGN/queries/admitted_actions.rq" \
  --query admitted_requires="$IGN/queries/admitted_requires.rq" \
  --query transitions="$IGN/queries/process_transitions.rq" \
  --template "$IGN/templates/beam4pm_receipt_chain_test.exs.eex" \
  --out test/beam4pm_receipt_chain_test.exs
