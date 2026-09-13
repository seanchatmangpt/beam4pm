# Wire ash_a2a onto beam4pm as additive agent-facing layer

## Summary

Adds `ash_a2a` + `a2a` (+ `req`) as real dependencies and mounts a genuinely
separate, additive A2A (agent-to-agent) HTTP surface alongside beam4pm's
existing OCEL ingest listener. This is explicitly not a replacement for
ex4pm's `Ex4pm.Engine.Beam4pm` HTTP route-table client, and it does not route
beam4pm's own internals (the 79 EngineOp dispatch/telemetry pipeline, the
OCEL/OTel evidence chain, `BeamPM.ReceiptChain`) through A2A/JSON-RPC.

## Status

Done - already merged/committed.

## Commits

- `4ca2ed9` feat(a2a): wire ash_a2a onto beam4pm as the additive agent-facing layer
- `0b1e073` feat(a2a): wire ash_a2a onto beam4pm as the additive agent-facing layer
- `ab88ca1` chore(ferroplan): bump submodule for hddl_error_json wasm fix

## Changes

- Added `ash_a2a`, `a2a`, and `req` as real dependencies.
- vendor/ggen-marketplace pointer bump: the igniter EEx template for
  `BeamPM.Ash.Domain` now renders `extensions: [AshAi, AshA2A]` plus an
  `a2a do skill(...) end` block for the same 2 curated resources already
  exposed as AshAi tools (`OcelEvent` read, `ConformanceResult` read) --
  regenerated via `scripts/igniter_sync.sh` into `lib/beam4pm_ash_domain.ex`.
- `lib/beam4pm_a2a_agent.ex` (new, hand-authored, admitted in `ontology.ttl`):
  `BeamPM.A2AAgent`, an `AshA2A.Agent` over `BeamPM.Ash.Domain`'s curated
  skills.
- `lib/beam4pm_a2a_router.ex` (new, hand-authored, admitted in `ontology.ttl`):
  `BeamPM.A2ARouter`, a thin `Plug.Router` forwarding `/a2a` to `A2A.Plug`.
- `lib/beam4pm_application.ex`: mounts a second Bandit listener
  (`BeamPM.A2ARouter`, port `:a2a_port`, default 4211) in the existing
  `one_for_one` supervisor, additively alongside the existing port-4210 OCEL
  ingest Bandit listener. `BeamPM.A2AAgent` itself boots via `ash_a2a`'s own
  Application callback (`config :ash_a2a, :agents, [BeamPM.A2AAgent]` in
  `config/config.exs`), not a second `A2A.AgentSupervisor` in this tree.
- `ontology.ttl`: re-admits `lib/beam4pm_application.ex`'s new sha256 and
  adds admissions for the two new hand-authored files (GATE AUTHORSHIP
  source facts). `schema/beam4pm_hand_authored_source.tsv` and
  `docs/reference/beam4pm_hand_authored_source.md` still need `just sync`'s
  ggen render to pick these up; `just sync` was BLOCKED in the commit's
  sandbox (docker daemon unavailable: "failed to create temp dir ...
  input/output error"), leaving 2 real regressions in
  `BeamPM.AuthorshipGateTest` pending a host with working docker re-running
  `just sync`.
- No change to `lib/beam4pm_ocel_ingest.ex`, the EngineOp dispatch facades,
  `BeamPM.ReceiptChain`, or the existing AshAi `tools do ... end` block.
- `native/ferroplan` submodule bumped to commit `d493c19`, which fixes the
  `wasm32-wasip1` build blocker in `op_hddl_solve`'s error mapping
  (non-exhaustive match on `HddlError::Timeout`/`WorkerPanicked`).

## Verification

Per the `4ca2ed9`/`0b1e073` commit messages:

- `mix compile --warnings-as-errors`: exit 0, zero warnings -- `AshA2A.Verify`'s
  fail-closed compile-time check passed for both declared skills.
- Real smoke test (`qualification/a2a_smoke_test.exs`, `mix run`): the real
  app boots both Bandit listeners; `A2A.Client.discover("http://localhost:4211/a2a")`
  returns a real `AgentCard` naming both skills
  (`["read_ocel_events", "read_conformance_results"]`); `A2A.Client.send_message`
  dispatches a real JSON-RPC request that reaches
  `BeamPM.Ash.Resources.OcelEvent`'s real `:read` action end-to-end (task
  state `:completed`, real Ash-returned data `%{"results" => []}` -- empty
  because no OCEL fixtures were loaded in this run, not a mock).
- `mix test`: 1065 tests, 13 failures, 81 skipped. 11 of the 13 failures are
  pre-existing (`BeamPM.Rf2ConformanceTest` / `BeamPM.RF3OcelTest`, missing
  `RF2_ORACLE_BIN`/`RF3_ORACLE_BIN`/`RF2_CLEAN_XES` env vars -- unrelated to
  this change, fail identically on main). The remaining 2
  (`BeamPM.AuthorshipGateTest`) are real regressions caused by this change,
  root-caused to the docker-blocked `just sync` regen step (see Changes).

For `ab88ca1`: none stated beyond the submodule bump description (fixes a
wasm32-wasip1 build blocker); no test/lint/CI output given in the commit
message.

## Related

None stated -- no PR numbers or branch names appear in the commit subjects
or messages.
