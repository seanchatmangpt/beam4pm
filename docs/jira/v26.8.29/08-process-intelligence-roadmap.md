# Process Intelligence Roadmap — v26.8.29

## North-star product loop

`living services -> observation -> semantic normalization -> service graph -> process inference -> process twin -> conformance -> optimization/planning -> governed actuation -> receipt -> new observation`

The roadmap is ordered to maximize reversible learning and customer-visible value before granting production authority.

## Phase 0 — manufacturing substrate

### Goals

- establish ggen-only source policy;
- define canonical process/event/type ontology;
- generate Erlang, Gleam, Elixir and Ash projections;
- generated build/test/docs/package surfaces;
- generated `examples/` and `playground/`;
- reproducible delete/regenerate/build/test flow.

### Crowns

- `SOURCE_LOCKED_ALIVE`
- `ERLANG_TYPES_ALIVE`
- `GLEAM_TYPES_ALIVE`
- `CROSS_LANGUAGE_ROUNDTRIP_ALIVE`
- `PLAYGROUND_ALIVE`
- `BEAM4PM_GGEN_ONLY_ALIVE`

## Phase 1 — process-mining core

### Capabilities

- event/object model;
- OCEL ingest/export;
- XES compatibility where valuable;
- DFG discovery;
- process-tree/Petri representation;
- alignments/conformance;
- variants;
- path/process schema analysis;
- deterministic fixtures and property tests.

### Rule

Algorithms may be independently implemented/generated or invoke admitted computational engines, but handwritten source cannot silently enter beam4pm.

## Phase 2 — BEAM-native process integration

Generate integrations that preserve runtime semantics for:

- Erlang/OTP applications/supervisors;
- process lifecycle;
- `gen_statem` transitions;
- Telemetry;
- Broadway;
- Oban;
- Reactor;
- Ash;
- Phoenix/Ecto where process evidence is useful.

Goal: reconstruct one cross-runtime BEAM business process without requiring every library to become beam4pm-aware.

## Phase 3 — OpenTelemetry ingestion hub

### OpenTelemetry

Ingest OTLP traces, metrics, logs, resources, events and span links.

### Weaver

Use semantic-convention registries and inference/validation as the telemetry-schema layer. Weaver's semantic inference is not business-process inference; beam4pm begins where telemetry semantics end.

### Service graph

Derive/ingest service relationships and preserve causal provenance.

### Zero-code/eBPF

Use available zero-code/eBPF evidence to produce useful topology/process candidates before custom instrumentation.

Crowns:

- `OTLP_INGEST_ALIVE`
- `SEMANTIC_REGISTRY_ALIVE`
- `SERVICE_GRAPH_ALIVE`

## Phase 4 — Kubernetes living topology

Continuously reconcile:

- clusters;
- namespaces;
- workloads/controllers;
- pods/containers;
- services/endpoints;
- jobs/cronjobs;
- stateful sets;
- owner references;
- watch events/resource versions;
- OTel Kubernetes resource identity.

The output is a time-indexed living service/deployment graph rather than a static CMDB snapshot.

Crown: `K8S_LIVING_TOPOLOGY_ALIVE`.

## Phase 5 — process inference

Infer candidate processes from causal/temporal/object evidence.

Requirements:

- preserve multiple plausible candidates when evidence is insufficient;
- confidence/provenance per inferred relation;
- UNKNOWN is explicit;
- no adjacency-only causal claims;
- process instances correlate across sync/async boundaries;
- process variants and repeated loops are discoverable;
- business labels are not fabricated when only technical evidence exists.

Crown: `PROCESS_INFERENCE_ALIVE` requires known seeded processes plus real-system observations with falsifiable expected structure.

## Phase 6 — living process twin

Maintain distinct but queryable projections:

- designed;
- executable;
- observed;
- inferred;
- admitted;
- verified.

Support time travel/replay and explain why a process edge exists, including source observations.

Crown: `PROCESS_TWIN_ALIVE`.

## Phase 7 — process intelligence

Capabilities:

- cycle/wait time;
- WIP/throughput;
- bottlenecks;
- variants;
- conformance deviations;
- retry/rework/recovery loops;
- process obligation tracking;
- anomaly detection;
- economic/value annotations;
- before/after comparison.

Product rule: metrics must be tied to exact process scope and evidence, not dashboard decoration.

## Phase 8 — DDL/formal projection league

Project the canonical graph into the formalism best suited to the question:

- PDDL — deterministic planning;
- PPDDL — probabilistic/stochastic planning;
- PDDL+ — continuous/event dynamics where admitted;
- HDDL — hierarchy;
- POWL — partial-order process semantics;
- Petri nets — concurrency/reachability/deadlock;
- BPMN/DMN — organizational communication/decision projection;
- TLA+/Alloy/SMT/other verifiers where useful.

No single DDL becomes the canonical process ontology.

## Phase 9 — empirical transition models

Use observed receipts/executions to estimate bounded transition probabilities/costs:

`P_(t+1)(s'|s,a) = update(P_t, observed receipts)`

Maintain sample size, confidence, environment/version identity and drift detection. Do not generalize across incompatible subjects without evidence.

## Phase 10 — planning and optimization

Given current state, goals and constraints, enumerate candidate process policies/plans.

Objectives may include:

- minimize cycle time;
- minimize WIP/rework;
- maximize throughput/reliability;
- minimize cost;
- preserve SLO/policy/security;
- maximize reversible lawful options before irreversible selection.

Planner output remains `CONSTRUCT`, never `DO`.

## Phase 11 — BRCE governed actuation

Only after observation/inference/planning are separately ALIVE:

`candidate -> admission/refusal -> authority -> actuation -> receipt -> replay -> updated twin`

Initial actuation surfaces should be narrow and reversible. One failed action edge is topology evidence, not permission to weaken the boundary.

## Phase 12 — beam4pm_pro zero-config product closure

Customer experience target:

1. purchase/entitle;
2. deploy;
3. automatically discover available lawful evidence;
4. show service/process graph;
5. show confidence/coverage/UNKNOWN;
6. identify first meaningful process finding;
7. produce customer-controlled report/receipt;
8. expand integrations only where they increase value.

Crown: `BEAM4PM_PRO_ZERO_CONFIG_ALIVE`.

## Phase 13 — marketplace closure

Per AWS/Microsoft/Google:

- listing accepted;
- purchase path executed;
- entitlement activated;
- deployment bound to entitlement;
- usage/contract accounting correct;
- private offer/plan path executed;
- renewal/upgrade path tested;
- provider outage/replay tested.

Final commercial crown: `BEAM4PM_PRO_MARKETPLACE_REVOPS_ALIVE`.

## Falsifiers

The thesis is weakened or falsified if:

- meaningful process inference routinely requires bespoke consulting/manual modeling;
- zero-config observation produces mostly unusable topology with no economic path to richer semantics;
- ggen-only manufacture requires so many privileged source exceptions that source lock is nominal;
- cross-language projection loses semantic identity;
- air-gap materially cripples core process intelligence;
- marketplace distribution creates unacceptable runtime coupling;
- inferred process findings cannot produce repeatable customer value;
- planning cannot maintain authority separation;
- operating/support costs destroy enterprise software margins.

These outcomes must be measured, not argued away.