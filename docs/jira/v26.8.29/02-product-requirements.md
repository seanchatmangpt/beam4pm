# Product Requirements — beam4pm / beam4pm_pro v26.8.29

## Product objective

Create a BEAM-first process-mining and process-intelligence platform that can progress from zero prior modeling to a continuously maintained, evidence-bounded process twin of living services and then expose lawful optimization/planning paths without granting ambient production authority.

## Product identities

### beam4pm

Open process substrate and first ggen-only product proof.

### beam4pm_pro

Commercial enterprise product that turns the substrate into a deployable, governable, supportable, marketplace-transactable process-intelligence system.

## Foundational requirements

### PR-001 — ggen-only normal source authority

- Human and LLM direct application-source commits are forbidden by default.
- Normal source is manufactured by ggen from admitted declarative inputs.
- Generated files are projections, not editing surfaces.
- A generated defect is repaired in ontology/specification/template/query/generator and regenerated.
- Manual source edits require explicit privileged authorization, a single-purpose pure commit, exact changed-subject Chicago execution, a receipt, replay evidence and privilege revocation.

Acceptance: repository policy and automated checks can distinguish admitted manufacturing-input changes, generated projections and privileged source exceptions.

### PR-002 — no wasm4pm inheritance

- wasm4pm is sunk cost.
- No source port, wrapper, compatibility shim or historical implementation dependency is required to establish beam4pm standing.
- External process-mining libraries/documentation may be used as semantic evidence, test oracles or reference inputs without becoming architectural authority.

### PR-003 — modern Erlang/OTP first-class

- Generated Erlang library compiles on the currently admitted modern OTP baseline.
- Public Erlang APIs have generated specs/types and documentation.
- Erlang examples execute real process operations.
- Erlang does not depend on Elixir/Ash to use core beam4pm functions.

### PR-004 — Gleam first-class

- Generated Gleam types/APIs are idiomatic and compile on the admitted current Gleam release.
- Erlang-target FFI boundaries are generated and contract-tested.
- Gleam examples execute real process operations.
- Cross-language round-trips preserve semantic identity.

### PR-005 — Elixir and Ash projections

- Generate Elixir structs/typespecs and Ash-compatible types/resources where semantically appropriate.
- Do not promote every value object into an Ash.Resource; choose value/newtype/typed-struct/embedded/resource by ontology semantics.

### PR-006 — executable examples

`examples/` is an executable specification. Every documented example must compile, run and verify its expected result in CI/local qualification.

Minimum verticals:

- OCEL ingest/read;
- directly-follows discovery;
- Petri/process representation;
- conformance/alignment;
- process discovery;
- cross-language serialization/execution.

### PR-007 — playground

`playground/` must provide an end-to-end environment that proves the intended customer workflow, not merely syntax.

Initial path:

`sample events -> OCEL -> discovery -> DFG/Petri/process representation -> conformance -> visible result`

Pro evolution:

`living services -> OTel/Kubernetes -> inferred process graph -> formal projection -> analysis`

## Process-intelligence requirements

### PI-001 — progressive discovery

beam4pm_pro must provide useful bounded output from whatever lawful evidence exists. Missing evidence lowers standing; it does not force total refusal unless a specific operation requires that evidence.

Evidence ladder:

1. network/eBPF;
2. OTLP traces/metrics/logs;
3. Kubernetes objects/events;
4. OTel semantic conventions/registry;
5. databases/queues/message metadata;
6. BEAM Telemetry/runtime semantics;
7. domain events;
8. explicit admitted ontology.

### PI-002 — living service graph

Continuously maintain a time-indexed graph of observed entities and relations, including identity, version, deployment, topology and causal execution where evidence supports it.

### PI-003 — process inference

Infer candidate process instances, activities, transitions and variants from observed execution while preserving confidence/provenance and UNKNOWN where semantics are unresolved.

### PI-004 — process twin

Maintain distinguishable designed, executable, observed, inferred, admitted and verified process projections.

### PI-005 — native semantic preservation

Adapters must preserve important native semantics rather than flattening them into generic events. Examples:

- OTP start/stop/restart/supervision/state transitions;
- Oban enqueue/retry/cancel/discard/rescue;
- Broadway ingestion, back-pressure and acknowledgement;
- Reactor dependency/compensation/undo;
- Ash domain actions/resources;
- OTel span/link/resource/event identities;
- Kubernetes creation/change/deletion and owner/reference topology.

### PI-006 — formal projections

Canonical process knowledge may project to multiple analysis formalisms including OCEL, DFG, Petri nets, POWL, PDDL, PPDDL and other admitted DDL/formal models. No projection is the canonical ontology itself.

### PI-007 — stochastic planning

Observed execution may estimate transition likelihoods/costs for probabilistic planning, with provenance and confidence. Planner output remains advisory/constructive until separately admitted for DO.

## Enterprise requirements

### ENT-001 — zero mandatory external SaaS dependency

Core product value must be realizable inside the customer boundary.

### ENT-002 — air-gapped mode

Target capabilities:

- zero required egress;
- private OCI registry support;
- local telemetry collection;
- local inference/storage;
- customer-managed keys;
- signed offline update bundles;
- offline entitlement/license evidence where marketplace terms permit;
- deterministic provenance and SBOM;
- no mandatory vendor telemetry export.

### ENT-003 — marketplace distribution

Support commercial packaging for AWS Marketplace, Microsoft Marketplace and Google Cloud Marketplace while keeping provider-specific procurement/metering adapters outside the canonical process model.

### ENT-004 — entitlement abstraction

Provide a canonical entitlement object capable of representing marketplace-specific customer/account/product/offer/agreement/order identifiers, quantities, effective dates, renewal/upgrade and usage dimensions without losing provider identity.

### ENT-005 — observability of beam4pm itself

beam4pm_pro must emit its own operational telemetry and process receipts so support, billing, entitlement and inference failures are diagnosable without hidden vendor access.

### ENT-006 — fleet scale

Support deployment from one environment to multi-account/multi-subscription/multi-project estates with bounded tenant isolation and explicit data/authority boundaries.

## RevOps requirements

### REV-001 — public-to-private offer motion

Maintain a public transactable/listable SKU where required to unlock private offers, then support negotiated enterprise terms without separate product forks.

### REV-002 — contract/usage duality

Packaging must support annual/multi-year committed contracts and usage expansion. Usage dimensions must correspond to customer value or defensible resource/process scope, not arbitrary telemetry volume alone.

### REV-003 — measurable ROI

The product must be able to baseline and report process metrics such as cycle time, waiting time, WIP, throughput, rework, variants, failure/retry loops and conformance so that expansion/renewal can be tied to observed customer outcomes.

### REV-004 — sales evidence package

Each qualified opportunity should produce a replayable evidence pack: environment scope, admitted access, discovered topology, process findings, quantified opportunity, product standing, security posture, proposed package, marketplace route and next proof step.

### REV-005 — renewal as operating process

Renewal is not an end-of-term event. The product and RevOps system must continuously accumulate evidence for adoption, value, support quality, expansion candidates and entitlement health.

## Standing and acceptance

No marketing claim becomes ALIVE merely because documentation or code exists.

Required vocabulary:

- `UNKNOWN` — insufficient evidence;
- `PARTIAL_ALIVE` — some required path executed, closure incomplete;
- `ALIVE` — exact admitted subject executed against acceptance;
- `BLOCKED` — required external authority/capability unavailable;
- `BUILD_BROKEN` — admitted build/execution path fails;
- `UNSUPPORTED` — capability intentionally absent;
- typed `REFUSED_*` — admission/authority rejects operation.

Product launch standing requires exact-subject observed evidence across generation, build, examples/playground, process inference, marketplace entitlement, deployment and customer-value paths.