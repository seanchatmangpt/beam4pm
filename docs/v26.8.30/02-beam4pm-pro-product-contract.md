# beam4pm_pro Product Contract — v26.8.30

## Contract objective

Turn the existing Beam4PM substrate and Pro-oriented capability seeds into a product that is installable, licensable, upgradeable, supportable, observable, agent-ready, and independently verifiable without creating a second canonical architecture.

The product contract is deliberately stronger than "add paid features." It defines the full customer lifecycle:

```text
select -> acquire -> install -> admit -> configure -> ingest -> analyze
-> explain -> govern -> support -> upgrade -> renew/expand -> replay
```

Every transition has an explicit subject, authority, consequence, and verification surface.

## 1. Product identities

### `beam4pm`

Open process-mining/process-intelligence substrate.

Responsibilities:

- canonical process/event/object contracts;
- core OCEL/XES and process discovery/conformance interfaces;
- rust4pm computational engine boundary;
- generated Erlang/Elixir/Gleam/Ash projections;
- deterministic manufacturing/source-lock machinery;
- public examples, fixtures, and a useful standalone playground;
- open extension contracts required for third-party integration.

The OSS product must remain genuinely useful. Pro must not be required to validate the open substrate.

### `beam4pm_pro`

Paid extension package over the OSS substrate.

Responsibilities:

- continuous/living process intelligence;
- durable analysis/research workflows;
- enterprise evidence connectors and semantic adapters;
- fleet/tenant policy and governance;
- advanced economics/value receipts;
- licensed commercial capabilities;
- support/diagnostic bundle production;
- Pro API and compatibility contracts.

`beam4pm_pro` must depend on a compatible `beam4pm` release rather than copy its domain implementation.

### `beam4pm_pro_web`

Optional Phoenix/LiveView control-plane projection.

Responsibilities:

- environment/estate inventory;
- process and object-centric graph exploration;
- process variants, conformance, bottlenecks, cycle/wait/WIP/throughput views;
- confidence, evidence coverage, contradiction, and `UNKNOWN` visualization;
- value/economics findings with source lineage;
- receipt/replay explorer;
- license/entitlement/update/support status;
- connector health and diagnostics;
- governed candidate-action review where enabled.

The web product is a projection. It may never become the canonical process ontology.

### `beam4pm_pro_connectors`

Versioned integration packs for evidence and control boundaries.

Initial candidate families:

- BEAM/OTP Telemetry/runtime semantics;
- Oban OSS/Pro lifecycle semantics where available;
- Reactor workflows/compensation;
- Broadway ingestion/ack/back-pressure;
- Ash domain/action semantics;
- OpenTelemetry OTLP/semantic conventions;
- Kubernetes topology/events;
- databases/queues/message metadata;
- cloud marketplace entitlement/usage transports.

A connector's failure is one topology edge, not permission to flatten native semantics or bypass admission.

### `beam4pm_pro_enterprise`

Commercial lifecycle and regulated-operation projection.

Responsibilities:

- license evidence;
- marketplace entitlement reconciliation;
- offline/air-gap entitlement bundles;
- signed update bundles;
- customer-managed keys integration points;
- fleet policy and data-boundary controls;
- support bundle/redaction policy;
- long-retention receipt manifests;
- release/SBOM/provenance verification.

## 2. Package and source-authority topology

Pro must follow the same manufacturing rule as OSS:

```text
public ontology + admitted Pro ontology/spec + ggen packs/templates
        -> ggen / ggen_igniter
        -> OSS and Pro projections
        -> package/release artifacts
```

There is no `generated/` ownership surface. Manufactured files continue to live in normal source paths with per-file provenance markers.

The open and paid products may use distinct admitted packs/templates and packaging manifests, but **must not fork canonical semantic identity**. A record that means the same thing in OSS and Pro has one canonical definition.

## 3. Installation and adoption contract

### Fresh Pro install

The minimum supported customer path should be expressible as:

```sh
# conceptual target commands; exact command names may evolve
mix beam4pm.pro.install
mix beam4pm.pro.doctor
mix beam4pm.pro.demo
```

Acceptance:

1. a fresh supported application can add `beam4pm` + `beam4pm_pro` without copying source;
2. dependency and schema compatibility is checked before mutation;
3. required migrations/configuration are generated or explicitly listed;
4. a real bundled fixture executes through ingestion -> discovery -> finding -> receipt;
5. every external prerequisite is named before the customer hits it;
6. uninstall/rollback consequences are documented.

### OSS -> Pro adoption

Adoption must be a bounded extension, analogous to the strongest Oban Pro pattern:

```text
working beam4pm OSS application
-> add compatible Pro artifact
-> run compatibility/adoption check
-> apply versioned Pro migrations/config
-> enable selected capability pack
-> execute existing OSS regression suite
-> execute Pro qualification
```

No customer's OSS process identity may silently change merely because a license is installed.

## 4. License, entitlement, and authority separation

Three objects must remain distinct:

### Commercial license

Answers: "May this customer use this paid software under the commercial agreement?"

Examples of dimensions:

- customer/account;
- application/project/estate scope;
- seats/support tier where applicable;
- update-rights window;
- effective/expiry dates;
- offline evidence lifetime;
- product/capability edition.

### Marketplace entitlement

Answers: "What has AWS/Microsoft/Google recorded as the buyer's commercial entitlement/order/agreement?"

This is already partially modeled by current entitlement work and remains provider-specific at the transport edge.

### Runtime actuation authority

Answers: "May this principal perform this exact `DO` against this exact target now?"

A paid license or marketplace entitlement **never grants BRCE authority**. Commercial rights and operational authority are orthogonal.

## 5. Distribution contract

Support multiple reversible channels:

### Direct package channel

Preferred developer experience:

- authenticated private Hex-compatible repository or equivalent package channel;
- semver releases;
- signed package metadata;
- compatibility manifest;
- reproducible build provenance;
- deterministic dependency resolution.

### Source/release channel

For customers requiring source-visible delivery:

- private release repository or access-controlled release bundles;
- tagged release snapshots rather than "clone moving main" as the primary install path;
- update-rights policy explicit in metadata;
- checksums/signatures and SBOM.

### OCI/offline channel

For enterprise/air-gap:

- signed OCI artifacts and/or offline bundle;
- all runtime dependencies available inside the bundle contract;
- license/entitlement evidence that can be validated without mandatory egress;
- replayable update/import procedure.

No distribution channel may create a distinct functional fork.

## 6. Versioning and migration contract

A Pro release is not identified by one package version alone. Release receipts must bind at least:

```text
beam4pm version
beam4pm_pro version
canonical ontology schema version
Pro ontology/schema version
process-model pack digest
Pro pack digest
rust4pm engine digest/version
runtime storage migration version
wire/API version
connector versions
license schema version
```

Required release artifacts:

- compatibility matrix;
- upgrade guide;
- downgrade/rollback limits;
- migration plan;
- generated-diff summary;
- deprecation ledger;
- exact-head qualification receipt.

A migration may be irreversible, but the decision to execute it must never be implicit.

## 7. Pro control-plane UX contract

The initial web product should be process-intelligence specific rather than generic SaaS scaffolding.

### Required pages/views

1. **Overview** — estate scope, evidence coverage, process coverage, current standing, first actionable findings.
2. **Evidence** — sources, freshness, identity, access scope, ingestion failures, provenance.
3. **Processes** — discovered processes, variants, object-centric views, DFG/Petri/formal projections where admitted.
4. **Conformance** — deviations, precision/fitness semantics, unsupported algorithm disclosure.
5. **Economics** — rework, cycle-to-cash, waiting/WIP/throughput, value receipts, confidence and source units.
6. **Governance** — candidate plans/intents, admission/refusal states, policy versions, authority boundary.
7. **Receipts** — execution/research/actuation receipt DAG and replay handles.
8. **Connectors** — health, versions, semantic coverage, missing evidence, typed failures.
9. **Administration** — principals, organizations/tenants, roles, data boundaries, retention.
10. **Product** — license, entitlement, update channel, version compatibility, support bundle.

### UX rule

The UI must show `UNKNOWN`, `UNSUPPORTED`, `BLOCKED`, and typed `REFUSED` states explicitly. Empty charts are not evidence.

## 8. Tenant, principal, and RBAC contract

Pro needs a canonical security boundary even when embedded in a customer application.

Minimum principals:

- human operator;
- service principal;
- connector principal;
- external research/agent principal;
- support principal if customer explicitly admits support access.

Minimum roles/capabilities:

- read evidence;
- read process intelligence;
- administer connectors;
- administer product/license;
- propose candidate action;
- admit/refuse candidate action;
- actuate approved action;
- inspect receipts;
- export support bundle.

No role may combine commercial entitlement with ambient operational authority.

## 9. API and interoperability contract

### Stable API

Provide a versioned HTTP/OpenAPI surface for product operations that customers need to automate:

- evidence/source registration and health;
- analysis task submission/status/cancel;
- process/findings queries;
- receipts/replay queries;
- connector/product health;
- license/entitlement status;
- candidate intent submission and admission status.

### MCP

Expose read and proposal operations for coding/research assistants:

- read capabilities/docs/status;
- query process/evidence/findings;
- request deterministic analysis;
- propose a `ToolIntent`/change intent;
- fetch verifier/receipt results.

MCP tool execution that can change external state must route through admission/BRCE. The MCP request itself is not authority.

### A2A

Use only where independent agent/task interoperability creates actual value. Returned artifacts are evidence/candidates, never ambient authority.

## 10. Agent-ready repository contract

Borrow Petal Pro's strongest idea while preserving beam4pm doctrine: agents should not have to rediscover architecture on every turn.

Required surfaces:

- root `AGENTS.md` with source-authority and verifier commands;
- nested `AGENTS.md` where subtree doctrine differs;
- current `CLAUDE.md` retained as provider-specific optimization, not the sole authority document;
- machine-readable recipe catalog for common changes;
- generated capability manifest;
- explicit editing-surface metadata;
- exact commands for narrow validation, full validation, regeneration, and release qualification;
- negative examples for forbidden direct edits;
- recipe outputs that are manufacturing inputs/intents, not unreceipted application-source mutation.

Candidate recipes:

- add process record/type;
- add process metric;
- add connector semantic mapping;
- add Pro capability family;
- add web view over canonical query;
- add API operation;
- add license/entitlement dimension;
- add migration;
- add provider transport;
- add Chicago fixture/qualification;
- prepare release receipt.

## 11. Diagnostics and support contract

A paid product must manufacture support evidence without hidden access.

Target command:

```sh
mix beam4pm.pro.doctor --bundle support.tar.zst
```

Bundle contents, subject to redaction policy:

- exact product/package versions;
- ontology/pack/engine digests;
- migration state;
- connector status and typed failures;
- recent product telemetry summaries;
- receipt verifier status;
- license/entitlement health without leaking secrets;
- environment compatibility facts;
- redaction manifest;
- replay commands where safe.

Support tiers may change response channels and assistance depth. They may not weaken evidence requirements.

## 12. Pricing/packaging contract

Final price remains `UNKNOWN` until observed willingness-to-pay and channel evidence exists.

The product should preserve at least three commercial motions:

### Developer / departmental direct

A low-friction direct purchase or evaluation path proving that Pro can be adopted without enterprise procurement.

### Business / enterprise

Annual or multi-year license, broader estate/capability scope, priority support, private offers, and procurement support.

### Sovereign / regulated

Air-gap/offline distribution, signed bundles, premium lifecycle/support evidence, customer-managed keys, and regulated deployment artifacts.

Competitor pricing is an **anchor for experiments only**. Beam4PM's value metric is process-intelligence scope/outcome, not feature parity or developer-seat count alone.

## 13. Changelog and update-rights contract

Every Pro release publishes:

- human-readable changelog;
- machine-readable capability delta;
- migration requirements;
- compatibility changes;
- deprecated/removed interfaces;
- security fixes;
- exact qualification receipt;
- update-rights eligibility metadata.

A customer's right to run an already acquired release must be distinguishable from their right to receive future updates.

## 14. Acceptance: minimum paid-ready Pro

`BEAM4PM_PRO_PAID_READY_ALIVE` requires observed execution of all of the following against one exact release candidate:

1. fresh licensed install;
2. OSS -> Pro adoption;
3. upgrade from the prior supported Pro version;
4. real fixture -> process finding -> provenance -> receipt;
5. Pro web/operator path;
6. API automation path;
7. license and entitlement reconciliation, including offline mode if claimed;
8. denied-license path that fails closed without corrupting customer state;
9. support doctor bundle;
10. agent recipe that changes an admitted manufacturing input, regenerates, validates, and never hand-edits manufactured output;
11. exact-head source-lock and runtime tests;
12. signed release/provenance verification.

Anything less may still be useful, but it is not the paid-ready crown.