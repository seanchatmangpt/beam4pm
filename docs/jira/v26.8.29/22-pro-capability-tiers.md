# beam4pm_pro capability tiers — sourced findings (2026-08-31)

Synthesis of a deep-research pass (`Workflow({name: "deep-research", ...})`, 103 agents, 17 claims surviving 3-vote adversarial verification out of 21 raised) against process-mining commercial feature sets (Celonis, PM4Py, Apromore, ProM), pricing/packaging models, and BEAM/Elixir commercial-addon patterns.

## Findings (verified, high/medium confidence)

1. **Analytical parity is table stakes.** Discovery, conformance (token-replay + alignments), fitness/precision/generalization/simplicity, filtering, case stats — the PM4Py-standard baseline. beam4pm already has most of this (`BeamPM.Discovery`, `BeamPM.Precision`).
2. **Object-centric process mining (OCPM) is the commercially validated flagship differentiator.** Celonis (Process Sphere / Object-Centric Data Model), Apromore, and academic OCPM literature all treat multi-object/multi-instance analysis as a premium capability addressing convergence/divergence problems that single-case-notion event logs cannot express. beam4pm is already OCEL-native — landed `BeamPM.Pro.OcpmDiscovery` (object-type co-occurrence, per-object-type activity frequency) as the first slice.
3. **Predictive monitoring over object interactions is a research-stage gap, not a shipped competitor feature.** Predicting remaining event sequences/timestamps using inter-object interactions (vs. single-case suffix prediction) is unfilled even in the academic literature (Galanti et al.) — real whitespace, not yet implemented anywhere including here.
4. **Prescriptive/actuation is a separately-monetized commercial tier.** Celonis's Action Engine (automated recommendations) and ML Workbench validate this as distinct from the analytical tier. `BeamPM.Actuation` and `BeamPM.ProcessGovernor` map directly onto it. Landed `BeamPM.Pro.Simulation` (what-if DFG analysis — edge add/remove, real reachability, real cycle detection) as the "evaluate before acting" half of this tier.
5. **Simulation/what-if analysis was a real, unfilled gap.** Celonis Process Simulation and Apromore's simulation capability are standard commercial-tier features; nothing in beam4pm's module list did this before `BeamPM.Pro.Simulation` landed.
6. **Dual-tier open-core packaging matches the existing beam4pm/beam4pm_pro split.** Apromore Community/Enterprise is the closest industry analogue; caveat that some vendors' free/academic tiers have since closed to new signups (time-sensitive, not load-bearing).
7. **Multi-tenancy: Triplex (Elixir/Ecto, PostgreSQL schema-based tenancy) is a real, ready-made library** — but beam4pm's data layer is Ets-based, not Postgres-backed, so adopting Triplex today would be an architecture mismatch, not a drop-in swap. `BeamPM.Pro.Tenancy`'s existing fail-closed tenant-then-role check is retained as-is; Triplex adoption is named explicit future work in that module's moduledoc, conditional on a Postgres-backed data layer existing, rather than forced now.

Pricing anchors (not yet actioned): platform licenses commonly $5K–$150K/yr, enterprise CoE spend $1M+; four common pricing models (SaaS subscription, usage-based, tiered, perpetual license).

## Refuted / excluded claims

Failed adversarial verification (0-3 or 1-2 votes) — not treated as evidence: ProcessMind per-user pricing tiers, premium-only feature-gating claims, a real-world OCPM adoption-gap claim, a Celonis volume-based-pricing claim, a PM4Py-as-BEAM-competitor positioning claim, an ARIS conformance-monetization claim, a generic usage-based-pricing-metering claim.

## What actually landed from this pass

- `lib/beam4pm_pro_ocpm_discovery.ex` + test (via `scripts/pro_ocpm_discovery_sync.sh`)
- `lib/beam4pm_pro_simulation.ex` + test (via `scripts/pro_simulation_sync.sh`)
- Both registered in `scripts/gate_m2_check.sh`'s determinism gate.
- `vendor/ggen-marketplace` PR #405 (pack v0.1.3 → v0.1.4).

## See Also

- `docs/jira/v26.8.29/README.md` — product split this doc's tier list extends
- `docs/jira/v26.8.29/16-gate-closure-m0-m6.md` — release gates
