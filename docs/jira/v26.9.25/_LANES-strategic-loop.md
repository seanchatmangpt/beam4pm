# _LANES — strategic-autonomic-loop wave 2 (2026-09-25)

Coordinator-owned file. Ten write lanes, disjoint file ownership, no lane runs git.
Dispatched 10 agents per message per fanout-first law. Wave-1 evidence in session
receipt (10 Explore lanes, same day).

## Lane map

| Lane | Repo | Owned files (create unless noted) |
|---|---|---|
| W1 | ~/ferroplan | crates/ferroplan-wasm/src/wasi_abi.rs (edit: +`fond_policy_validate`, +`session_install_plan` ops + tests) |
| W2 | ~/beam4pm | ontology fragment for 2 new engine ops; lib/beam4pm_ferroplan_bridge.ex; test/beam4pm_ferroplan_bridge_test.exs |
| W3 | ~/beam4pm | lib/beam4pm_replan_trigger.ex; lib/beam4pm_stale_plan_gate.ex; lib/beam4pm_plan_journal.ex; test/beam4pm_replan_chain_test.exs |
| W4 | ~/beam4pm | lib/beam4pm_powl_model.ex; lib/beam4pm_hddl_powl.ex; lib/beam4pm_fond_powl.ex; lib/beam4pm_ocel_accumulator.ex; test/beam4pm_powl_edges_test.exs |
| W5 | ~/beam4pm | lib/beam4pm_ocel_session_facts.ex; test/beam4pm_ocel_session_facts_test.exs; test/fixtures/ocel golden files |
| W6 | ~/ggen-marketplace | packs/strategic-doctrine-pack/** (pack.toml, ontology.ttl, gates/, qualification/) |
| W7 | ash_a2a + xaas + ggen_igniter | ash_a2a: lib/ash_a2a/planning/preflight.ex (edit) + new test file. xaas: lib/xaas/sa2a/route.ex (edit: +command_envelope/1) + new test file. ggen_igniter: priv/ggen/semantic-jira-pack/shapes/work-order.shacl.ttl (edit) + new test file |
| W8 | ~/autofde-lab | src/autofde_lab/simulation/fortune5_safe/{worldgen.py (new), model.py, dfcm.py, engine.py (edits)} + tests/simulation/test_worldgen_doctrine.py |
| W9 | marketplace + beam4pm + xaas + wasm4pm + ash_a2a | locks (ssn/schema-org/aps), profile.ttl prefixes, ggen.toml imports keys (beam4pm, xaas), wasm4pm mex-core.ttl prov fix, ash_a2a base_bnode_relabelled.ttl xsd fix |
| W10 | ~/autofde-lab (gymact read-only) | src/autofde_lab/simulation/bridge_gymact.py; tests/simulation/test_bridge_gymact.py |

## RESOLUTIONS (shared seams, pinned before dispatch)

1. **Generated files** (`beam4pm_types.ex`, `beam4pm_codec.ex`, `beam4pm_ash/*`, all
   `# GENERATED` headers): NO lane edits them. W2 writes ontology facts only;
   coordinator runs the ggen re-render alone at integration.
2. **Telemetry seam** (W2↔W3): event `[:beam4pm, :ferroplan, :replan_triggered]`,
   metadata `%{trigger_hash: hex, reason: :deviation | :stale_plan | :world_invalid}`.
3. **trigger_hash formula** (W3, consumed at integration): `sha256(deviation_individual_name <> observed_at_iso8601)` hex.
4. **OCEL→sight fact-name policy** (W5): deviation move → fact `"dev_" <> activity` = true;
   umbrella `"conforms"`; discretized attribute → `attr <> "_" <> value` = true.
5. **Refusal shapes** (W3, W7): `{:error, {:stale_plan_refusal, %{admitted_preimage_hash:, observed_preimage_hash:}}}`,
   `{:error, {:preflight_work_order_mismatch, %{plan_digest:, work_order_digest:}}}`,
   `{:error, {:command_envelope_refusal, reason}}`.
6. **Module names** (W2/W3/W4/W5): `BeamPM.Ferroplan.Bridge`, `BeamPM.ReplanTrigger`,
   `BeamPM.StalePlanGate`, `BeamPM.PlanJournal`, `BeamPM.Powl.Model|HddlPowl|FondPowl`,
   `BeamPM.OcelAccumulator`, `BeamPM.OcelSessionFacts`.
7. **Outcome-row schema** (W8 owns, W10 conforms): `%{backend: binary, doctrine_id: binary, world_id: binary, seed: int, metrics: map, feasible: boolean, receipt_digests: [binary]}`.
8. **Ash domain module**: DEFERRED — `use Ash.Domain` is generator-owned (REFUSED_GENERATOR_OWNED);
   no admitted domain generator exists. UNSUPPORTED ledger row at integration; W3 uses the
   generated ETS resources directly.
9. **Parallel pytest** (W8‖W10 in autofde-lab): `PYTHONDONTWRITEBYTECODE=1 pytest -p no:cacheprovider`.
10. **W2 new-op call sites**: generated facade lacks `fond_policy_validate`/`session_install_plan`
    until re-render; W2 guards call sites (function_exported?/3) and tests the
    independent paths; unguard + verify at integration.
