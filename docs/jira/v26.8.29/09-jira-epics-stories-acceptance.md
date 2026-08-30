# Jira Epics, Stories and Acceptance — v26.8.29

This backlog is written as implementable outcome units. Every story must bind exact subject, acceptance behavior, authority and evidence. Compilation or file existence alone is not a crown.

## EPIC B4PM-100 — ggen-only repository constitution

### B4PM-101 Source authority classification

Define machine-readable classifications for authoritative manufacturing inputs, generated projections, documentation and privileged-source exceptions.

Acceptance:

- normal human/LLM commit touching generated/application source is refused;
- ggen projection commit is admitted with manufacturing provenance;
- docs/spec/ontology/template/query changes remain writable;
- refusal is typed and testable.

### B4PM-102 Privileged source exception protocol

Implement explicit temporary grant scoped to one change/pure commit.

Acceptance:

`grant -> isolated source commit -> exact Chicago execution -> receipt -> revoke`

A second source commit without a new grant must be refused.

### B4PM-103 Reprojection determinism

Delete generated outputs, regenerate, build/test and compare canonical artifact identities.

Acceptance: no unexplained generated drift.

## EPIC B4PM-200 — canonical process/type ontology

### B4PM-201 Semantic type graph

Model type identity, fields, cardinality, variants, constraints, wire representation and provenance.

### B4PM-202 Process/event/object graph

Model events, objects, relations, activities, transitions, process instances, observations and provenance.

### B4PM-203 Reference evidence importer

Ingest admitted Rust4PM type/reference metadata without source-code porting.

Acceptance: representative semantic distinctions survive round-trip into canonical representation.

## EPIC B4PM-300 — Erlang projection

### B4PM-301 Generate Erlang types/specs/modules
### B4PM-302 Generate codecs/validators
### B4PM-303 Generate OTP application packaging
### B4PM-304 Generate Erlang process-mining examples
### B4PM-305 Modern OTP qualification

Acceptance crown: `ERLANG_TYPES_ALIVE` and `ERLANG_EXAMPLES_ALIVE` from observed execution on admitted modern OTP.

## EPIC B4PM-400 — Gleam projection

### B4PM-401 Generate idiomatic Gleam public types
### B4PM-402 Generate Erlang-target FFI
### B4PM-403 Generate contract tests for externals
### B4PM-404 Generate Gleam examples
### B4PM-405 Cross-language semantic round-trip

Acceptance crown: `GLEAM_FFI_ALIVE`, `GLEAM_EXAMPLES_ALIVE`, `CROSS_LANGUAGE_ROUNDTRIP_ALIVE`.

## EPIC B4PM-500 — Elixir/Ash projection

### B4PM-501 Generate Elixir structs/typespecs/codecs
### B4PM-502 Generate Ash value/newtype projections
### B4PM-503 Generate typed-struct/embedded projections
### B4PM-504 Generate Ash.Resource only for actual lifecycle/domain entities

Acceptance: representative object/event/process graph can be consumed in Ash without semantic flattening.

## EPIC B4PM-600 — process mining core

### B4PM-601 OCEL ingest/export
### B4PM-602 directly-follows graph discovery
### B4PM-603 process/Petri representation
### B4PM-604 variants
### B4PM-605 alignment/conformance
### B4PM-606 path/process schema analysis
### B4PM-607 deterministic fixtures/property generation

Acceptance: generated `examples/` execute these capabilities with verifiable outputs.

## EPIC B4PM-700 — playground

### B4PM-701 Generate reproducible local playground
### B4PM-702 Seed event/object scenario
### B4PM-703 End-to-end discovery scenario
### B4PM-704 Cross-language scenario
### B4PM-705 Reset/replay

Acceptance crown `PLAYGROUND_ALIVE`:

`fresh checkout -> manufacture -> start playground -> ingest scenario -> discover process -> verify expected result -> reset -> replay`

## EPIC B4PM-800 — BEAM process integration

### B4PM-801 OTP lifecycle/supervision events
### B4PM-802 gen_statem transitions
### B4PM-803 Telemetry/OpenTelemetry bridge
### B4PM-804 Broadway semantic adapter
### B4PM-805 Oban semantic adapter
### B4PM-806 Reactor dependency/compensation adapter
### B4PM-807 Ash domain-operation adapter

Acceptance: one seeded workflow crosses at least three execution abstractions and reconstructs as one process without losing native semantic evidence.

## EPIC B4PM-900 — OpenTelemetry / Weaver hub

### B4PM-901 OTLP traces/resources/events
### B4PM-902 OTLP metrics/log correlation where process-relevant
### B4PM-903 span links/async causality
### B4PM-904 Weaver registry ingestion/validation
### B4PM-905 service graph ingestion/derivation
### B4PM-906 zero-code/eBPF observation integration

Acceptance: known service topology reconstructed from live observations with provenance.

## EPIC B4PM-1000 — Kubernetes living topology

### B4PM-1001 watch/list reconciliation
### B4PM-1002 owner-reference graph
### B4PM-1003 workload/pod/service identity
### B4PM-1004 OTel K8s identity correlation
### B4PM-1005 topology time travel

Acceptance crown `K8S_LIVING_TOPOLOGY_ALIVE`: create/scale/rollout/delete a seeded workload and verify the graph records each transition in order.

## EPIC B4PM-1100 — process inference

### B4PM-1101 correlation engine
### B4PM-1102 candidate process-instance reconstruction
### B4PM-1103 process variants
### B4PM-1104 confidence/provenance
### B4PM-1105 explicit UNKNOWN semantics
### B4PM-1106 falsification fixtures

Acceptance crown `PROCESS_INFERENCE_ALIVE`: infer known seeded flows plus a live integration scenario; false adjacency must not be promoted to admitted causality.

## EPIC B4PM-1200 — living process twin

### B4PM-1201 designed/executable/observed/inferred/admitted/verified projections
### B4PM-1202 time-indexed process state
### B4PM-1203 evidence drill-down
### B4PM-1204 replay

Acceptance: query one process instance and trace every admitted edge back to its source evidence.

## EPIC B4PM-1300 — formal model projections

### B4PM-1301 POWL projection
### B4PM-1302 PDDL projection
### B4PM-1303 PPDDL projection
### B4PM-1304 Petri/reachability projection
### B4PM-1305 model equivalence/property tests where defined

Acceptance: canonical process fixture projects into at least three formalisms and preserves stated invariants.

## EPIC B4PM-1400 — process intelligence

### B4PM-1401 cycle/wait time
### B4PM-1402 WIP/throughput
### B4PM-1403 retry/rework loops
### B4PM-1404 conformance deviation
### B4PM-1405 bottleneck ranking
### B4PM-1406 before/after value receipts

Acceptance: seeded workload with known bottleneck produces correct bounded diagnosis and metric evidence.

## EPIC B4PM-1500 — planning / DfCM

### B4PM-1501 candidate-state graph
### B4PM-1502 deterministic planner integration
### B4PM-1503 probabilistic transition estimation
### B4PM-1504 PPDDL planner league
### B4PM-1505 multi-objective/cost constraints
### B4PM-1506 planner receipt

Acceptance: planner enumerates lawful alternatives from exact twin state but cannot actuate without separate authority.

## EPIC B4PM-1600 — BRCE integration

### B4PM-1601 intent object
### B4PM-1602 admission/refusal
### B4PM-1603 authority/capability binding
### B4PM-1604 narrow reversible actuator
### B4PM-1605 receipt/replay

Acceptance: unauthorized planner action is refused; explicitly admitted action executes exact target, records consequence and replays verification.

## EPIC B4PMP-2000 — beam4pm_pro packaging

### B4PMP-2001 local all-in-one deployment
### B4PMP-2002 customer-managed persistence
### B4PMP-2003 local UI/API
### B4PMP-2004 fleet identity
### B4PMP-2005 support diagnostics
### B4PMP-2006 entitlement abstraction

Acceptance crown `BEAM4PM_PRO_ZERO_CONFIG_ALIVE`: deploy into seeded living environment with no app rewrite and produce first meaningful process graph/finding.

## EPIC B4PMP-2100 — air-gap / sovereign

### B4PMP-2101 zero-egress runtime
### B4PMP-2102 private registry install
### B4PMP-2103 signed offline bundle
### B4PMP-2104 offline entitlement/grace/reconciliation
### B4PMP-2105 offline update/rollback
### B4PMP-2106 local receipt export

Acceptance crown `AIRGAP_ALIVE`: disconnected environment installs, discovers, infers, reports, upgrades and replays without vendor network access.

## EPIC B4PMP-2200 — AWS Marketplace

### B4PMP-2201 seller/listing readiness
### B4PMP-2202 contract/subscription integration
### B4PMP-2203 concurrent-agreement identity support
### B4PMP-2204 private offer path
### B4PMP-2205 metering/overage if admitted
### B4PMP-2206 renewal/upgrade/cancel replay
### B4PMP-2207 channel/CPPO readiness

Acceptance crown `AWS_MARKETPLACE_ALIVE`: real or marketplace-approved test purchase -> entitlement -> deployment -> renewal/upgrade scenario with exact evidence.

## EPIC B4PMP-2300 — Microsoft Marketplace

### B4PMP-2301 partner/listing readiness
### B4PMP-2302 transactable SaaS fulfillment
### B4PMP-2303 metered billing if admitted
### B4PMP-2304 private plan/offer path
### B4PMP-2305 lifecycle webhooks/reconciliation
### B4PMP-2306 renewal/upgrade/cancel

Acceptance crown `MICROSOFT_MARKETPLACE_ALIVE` from executed test transaction/lifecycle.

## EPIC B4PMP-2400 — Google Cloud Marketplace

### B4PMP-2401 vendor/listing readiness
### B4PMP-2402 integrated SaaS entitlement
### B4PMP-2403 Kubernetes product qualification
### B4PMP-2404 Partner Procurement API lifecycle
### B4PMP-2405 multiple-order identity
### B4PMP-2406 private offer API/manual path
### B4PMP-2407 reseller private-offer-plan path

Acceptance crown `GCP_MARKETPLACE_ALIVE` from executed entitlement/deployment/offer lifecycle.

## EPIC B4PMP-2500 — RevOps control plane

### B4PMP-2501 canonical opportunity/customer/commercial graph
### B4PMP-2502 marketplace identity reconciliation
### B4PMP-2503 proof/value receipt
### B4PMP-2504 quote/private-offer package generation
### B4PMP-2505 activation/adoption telemetry
### B4PMP-2506 expansion detection
### B4PMP-2507 120-day renewal workflow
### B4PMP-2508 contract/usage/revenue reconciliation

Acceptance: one synthetic customer travels from qualified opportunity through renewal with no orphan commercial/runtime identities.

## EPIC B4PMP-2600 — TAI quality / mission support

### B4PMP-2601 configuration/document control
### B4PMP-2602 V&V plan
### B4PMP-2603 supportability/recovery plan
### B4PMP-2604 release evidence package
### B4PMP-2605 24/7 mission-severity runbook
### B4PMP-2606 customer acceptance packet
### B4PMP-2607 continuous-improvement RCA loop

Acceptance: release/support simulation demonstrates traceable configuration, recovery, evidence and customer communication.

## Definition of Chicago

For every story labeled Chicago:

1. resolve exact repo/ref/SHA and admitted subject;
2. manufacture the change through the lawful path;
3. execute the actual user/customer path, not merely unit internals;
4. permit failure to become observed evidence;
5. perform RCA at the failed transition;
6. repair the narrow cause upstream;
7. reexecute exact subject;
8. produce receipt/replay evidence;
9. expand validation only after the narrow path succeeds;
10. do not crown ALIVE from CI/status metadata alone.