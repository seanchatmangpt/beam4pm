# Release Gates, Receipts and Standing — v26.8.29

## Purpose

Prevent beam4pm/beam4pm_pro from confusing design, generated artifacts, CI metadata, marketplace listing state or partial execution with a proven customer capability.

## Standing vocabulary

- `UNKNOWN` — evidence is insufficient.
- `PARTIAL_ALIVE` — some required execution is observed but closure is incomplete.
- `ALIVE` — exact admitted subject executed successfully against the stated acceptance boundary.
- `BLOCKED` — required external authority/capability is unavailable.
- `BUILD_BROKEN` — the admitted build/execution path fails.
- `UNSUPPORTED` — the capability is intentionally not provided.
- `REFUSED_*` — admission/authority explicitly rejects an operation.

`UNKNOWN != ADMITTED`.

`UNSUPPORTED != REFUSED`.

A checkpoint is not a crown.

## Evidence dimensions

Receipts must preserve these dimensions independently where relevant:

- observed;
- admitted;
- executed;
- changed;
- verified;
- inferred;
- refused;
- blocked;
- unsupported.

Inspection is not execution. A workflow definition is not a successful run. A generated file is not a runtime proof. A marketplace listing is not a successful purchase. An entitlement object is not a deployed customer system. A named “receipt” without bound identity/authority/consequence is not a receipt.

## Receipt minimum fields

For technical execution:

- repository/product identity;
- exact ref/SHA/version/digest;
- canonical source/spec/ontology identity;
- generator/ggen/packs identity;
- toolchain/runtime identity;
- environment identity;
- command/action;
- authority/capability;
- start/end/order;
- exit/result;
- relevant outputs/measurements;
- changed targets;
- verifier identity;
- replay procedure;
- known limits.

For commercial/marketplace execution add:

- provider;
- seller/product/plan/SKU;
- buyer billing/account/tenant identity;
- offer/private-plan identity;
- agreement/order/license identity;
- entitlement identity;
- effective term;
- pricing/meter dimension identity;
- deployment bound to entitlement;
- renewal/upgrade/cancel event identity.

Never store secret values in receipts.

## Manufacturing gates

### GATE M0 — canonical input admitted

Ontology/specification/query/template/generator changes validate and have explicit authority classification.

### GATE M1 — manufacture succeeds

ggen produces the intended source/config/docs/tests/examples/playground artifacts.

### GATE M2 — deterministic reprojection

Deleting generated artifacts and regenerating yields semantically identical outputs under an identical admitted toolchain/configuration.

### GATE M3 — compile/type verification

Modern Erlang, Gleam and Elixir/Ash projections pass their admitted compiler/type gates.

### GATE M4 — executable examples

Erlang and Gleam examples execute actual process-mining/process-intelligence behavior.

### GATE M5 — cross-language identity

Representative semantic objects round-trip across generated language/wire boundaries.

### GATE M6 — playground

Fresh-user workflow executes end to end.

Crown after M0-M6: `BEAM4PM_GGEN_ONLY_ALIVE` only for the exact qualified release subject.

## Source-lock gates

### Normal source change

Must be attributable to ggen/manufacturing.

### Privileged source exception

Requires:

1. explicit grant;
2. exact scope;
3. reason;
4. pure commit;
5. exact-subject Chicago execution;
6. receipt;
7. privilege revocation.

Missing any item -> `REFUSED_UNAUTHORIZED_SOURCE_COMMIT` or `PARTIAL_ALIVE` depending on stage. Privileged exceptions must be counted and reviewed as manufacturing debt.

## Process-intelligence gates

### PI0 Observation ingestion

Real observation source connected and evidence identity preserved.

### PI1 Topology

Expected service/runtime topology reconstructed from actual observation.

### PI2 Correlation

Sync and async causal/correlation edges survive representative cases.

### PI3 Process inference

Known seeded process is inferred with bounded confidence; false adjacency fixtures are not promoted to causality.

### PI4 Process twin

Observed/inferred/admitted/verified projections are separately queryable and traceable to evidence.

### PI5 Intelligence

At least one metric/finding is proven correct against a known workload.

### PI6 Formal projection

Canonical process projects into admitted formal model(s) preserving stated invariants.

### PI7 Planning

Planner constructs lawful candidates from exact state but lacks ambient DO authority.

### PI8 BRCE

Authorized narrow action executes through admission/authority boundary and produces a replayable consequence receipt.

## Air-gap gates

`AIRGAP_ALIVE` requires an actually disconnected execution environment:

1. install from offline/private artifact source;
2. verify signatures/SBOM/provenance;
3. start without vendor DNS/network;
4. collect local observations;
5. infer/display process intelligence;
6. persist locally;
7. produce diagnostic/value receipt;
8. perform offline update;
9. rollback;
10. reconcile entitlement according to admitted policy without hidden online dependency.

A configuration flag named air-gap is insufficient.

## Marketplace gates — common

For each provider:

### MP0 Seller/provider onboarding

Required seller account/agreements/permissions exist.

### MP1 Listing accepted

Product/plan is accepted in required marketplace state.

### MP2 Purchase path

Approved test or production buyer executes subscription/purchase.

### MP3 Entitlement

beam4pm_pro receives/reconciles the provider's entitlement/order/agreement state idempotently.

### MP4 Deployment

Purchased entitlement activates an exact deployment/customer path.

### MP5 Value path

The entitled deployment performs real process discovery/inference.

### MP6 Billing/metering

Contract quantities/usage reconcile exactly; duplicate/reordered events do not double bill.

### MP7 Private offer/plan

Negotiated enterprise route executes where supported.

### MP8 Lifecycle

Upgrade/amendment, renewal and cancel/expiration are executed or provider-approved test equivalents are proven.

### MP9 Failure/replay

Provider API/event failure, retry and reconciliation path is executed.

Only then may provider crown become `ALIVE`.

## Provider crowns

- `AWS_MARKETPLACE_ALIVE`
- `MICROSOFT_MARKETPLACE_ALIVE`
- `GCP_MARKETPLACE_ALIVE`

All three plus product/RevOps closure are required for:

`BEAM4PM_PRO_MARKETPLACE_REVOPS_ALIVE`

The crown is scoped by version, marketplace product identities and executed date; marketplace rules can change, so standing can become stale.

## RevOps gates

### R0 Qualified

Real mission problem, owner, environment and proof criterion.

### R1 Technical admission

Environment/data/authority boundaries admitted.

### R2 Proof running

Exact product deployed.

### R3 Value proven

Customer-specific finding/metric evidenced.

### R4 Commercial proposed

Package/term/marketplace route is purchasable.

### R5 Contracted

Executed marketplace agreement/order/entitlement.

### R6 Adopted

Sustained use/coverage above admitted threshold.

### R7 Expansion

Additional paid estate/capability activated.

### R8 Renewal

New/extended executed agreement/entitlement.

No CRM stage may impersonate these states without the corresponding evidence object.

## Release evidence packet

Every commercial release should manufacture an evidence packet containing:

- release manifest;
- exact source/manufacturing identities;
- generated-artifact manifest;
- compiler/test/property results;
- examples/playground results;
- cross-language results;
- process-inference qualification;
- security/no-egress results;
- SBOM/provenance/signatures;
- install/upgrade/rollback results;
- provider-specific marketplace compatibility results;
- known limitations;
- replay instructions.

## Chicago execution protocol

For release-critical capabilities:

`inspect -> admit -> manufacture -> execute -> observe failure if any -> RCA -> repair upstream -> reexecute -> verify -> receipt -> expand validation`

Rules:

- execute the actual customer-facing path;
- preserve failures as evidence;
- do not rerun an unchanged failure without a new hypothesis;
- repair the narrowest failed transition;
- encode a permanent guard when feasible;
- exact-head CI supplements local/target execution; it does not replace it;
- one failed edge is topology, not graph failure.

## Falsifier policy

Every major product claim must name a falsifier.

Examples:

- “zero config” falsified when standard supported environments consistently require bespoke manual modeling before meaningful value;
- “air-gapped” falsified by required hidden vendor egress;
- “ggen-only” weakened when privileged manual source commits become routine;
- “process inference” falsified when causal structure cannot be distinguished from adjacency on admitted fixtures;
- “marketplace RevOps” falsified when offer/entitlement/reconciliation regularly requires manual identity repair;
- “world-class process intelligence” remains unsupported until measured against explicit capabilities/benchmarks/customer outcomes.

The operating rule is simple: preserve the claim only at the standing earned by observed evidence.