#!/usr/bin/env bash
# BeamPM.ClaudeWorkflowReactor manufacturing script -- renders the plain-Reactor
# DAG that models Claude Code's own orchestration shape (Measure fan-out ->
# Design synthesis -> Develop fan-out -> sequential Actuate -> Qualify) over a
# real 19-agent workflow journal committed at
# qualification/fixtures/claude-workflows/journal.jsonl. Both templates are
# fully static (no graph bindings -- the journal-schema facts are baked in from
# a real inspection of the journal, not queried from RDF) -- mix
# ggen_igniter.sync still requires >=1 --query flag, so this passes
# admitted_actions.rq, whose result these templates never reference (same
# pattern as beam4pm_receipt_chain.ex.eex / scripts/receipt_chain_sync.sh and
# scripts/rf1_dfg_sync.sh). No cargo step: this family has no native oracle.
set -euo pipefail

PACK="${PACK:-vendor/ggen-marketplace/packs/beam4pm-process-model-pack}"
IGN="$PACK/igniter"

# The generated test runs the Reactor end-to-end against the committed journal
# fixture -- refuse early (typed, loud) if it has not landed yet, rather than
# letting mix ggen_igniter.sync's internal verification fail obscurely.
FIXTURE="qualification/fixtures/claude-workflows/journal.jsonl"
if [ ! -f "$FIXTURE" ]; then
  echo "REFUSED: missing fixture $FIXTURE (commit it before running this sync)" >&2
  exit 1
fi

mix deps.get

mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query admitted="$IGN/queries/admitted_actions.rq" \
  --template "$IGN/templates/beam4pm_claude_workflow_reactor.ex.eex" \
  --out lib/beam4pm_claude_workflow_reactor.ex

mix ggen_igniter.sync \
  --ontology ontology.ttl \
  --query admitted="$IGN/queries/admitted_actions.rq" \
  --template "$IGN/templates/beam4pm_claude_workflow_reactor_test.exs.eex" \
  --out test/beam4pm_claude_workflow_reactor_test.exs
