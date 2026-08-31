# beam4pm_pro Gap-Closure Backlog — v26.8.30

## Ordering principle

Close the shortest path to a defensible paid customer experience before broadening the feature graph.

Foundational order:

```text
Preserve OSS/source authority
-> define Pro boundary
-> make install/adoption/upgrade reproducible
-> make first customer value visible
-> productize license/support/release
-> expand connectors/fleet/marketplace
-> deepen autonomous/agent surfaces
```

A failed optional connector or UI edge is topology, not permission to bypass the canonical model or BRCE.

## P0 — product identity and first paid customer path

### PRO-001 — current-status truth source

**Problem:** root documentation has already drifted behind exact-head implementation.

**Implement:** machine-readable capability manifest generated or verified from exact source/build/qualification state; README/product status consumes that manifest rather than manually asserting stale capability state.

**Acceptance:** on exact head, one command produces the current capability/status manifest and a verifier fails if customer-facing current-status docs contradict it.

### PRO-002 — explicit package boundary

**Implement:** create a separately versioned `beam4pm_pro` package/artifact that depends on a compatible `beam4pm` version and contains only paid extension surfaces.

**Acceptance:** a fresh application can depend on OSS only or OSS+Pro; adding Pro does not duplicate canonical type/process definitions; removing Pro leaves OSS tests green.

### PRO-003 — compatibility manifest

**Implement:** version matrix binding OSS, Pro, ontology schema, ggen packs, rust4pm engine, runtime storage migrations, connectors, wire/API versions, and license schema.

**Acceptance:** an incompatible pair is refused before application mutation with a typed diagnostic naming the incompatible dimension.

### PRO-004 — fresh licensed install

**Implement:** installer/adoption task and documented setup flow.

**Target interface:** `mix beam4pm.pro.install` or equivalent.

**Acceptance:** clean supported Phoenix/Elixir application -> install -> migrate/configure -> run bundled Chicago fixture -> process finding -> receipt, without copying source files manually.

### PRO-005 — OSS -> Pro adoption

**Implement:** bounded adoption path over an already working `beam4pm` application.

**Acceptance:** execute OSS qualification before adoption; install Pro; apply only admitted changes/migrations; execute OSS qualification again byte/semantic-compatible where contracts require; execute Pro qualification.

### PRO-006 — Pro migration framework

**Implement:** centrally versioned, explicit migrations for Pro-owned persistent state and schema evolution.

**Acceptance:** supported N-1 -> N upgrade executes on a real populated fixture/database; rollback or explicit irreversibility classification is tested; stale migration state is surfaced by doctor/runtime warning.

### PRO-007 — commercial license evidence

**Implement:** commercial license object distinct from marketplace entitlement and runtime authority.

**Acceptance:** valid, expired, wrong-scope, tampered, and offline license evidence all produce typed outcomes; license state never directly grants BRCE authority.

### PRO-008 — product doctor/support bundle

**Implement:** `beam4pm_pro` doctor plus portable redacted support bundle.

**Acceptance:** from a deliberately broken customer fixture, doctor identifies at least version mismatch, migration lag, connector failure, entitlement failure, and source/provenance mismatch without requiring vendor shell access.

## P0 — visible product value

### PRO-009 — optional Pro control plane

**Implement:** `beam4pm_pro_web` Phoenix/LiveView product shell.

**Minimum views:** Overview, Evidence, Processes, Conformance, Economics, Governance, Receipts, Connectors, Administration, Product.

**Acceptance:** fresh Pro demo starts the UI and renders a real bundled fixture through discovery/conformance/economics with exact evidence/receipt links; `UNKNOWN`, `BLOCKED`, `UNSUPPORTED`, and typed `REFUSED` are visibly distinct.

### PRO-010 — principal/tenant/RBAC model

**Implement:** canonical principal, organization/tenant, role/capability and data-boundary policy for web/API/agent surfaces.

**Acceptance:** cross-tenant read and write attempts fail closed; proposal/admission/actuation capabilities are independently testable; support access is absent unless explicitly admitted.

### PRO-011 — versioned HTTP/OpenAPI surface

**Implement:** stable automation API for evidence, analysis tasks, findings, receipts, connectors, product/license status and candidate intents.

**Acceptance:** generated OpenAPI contract, contract tests, backwards-compatibility policy, and one real external client fixture all pass against exact head.

### PRO-012 — durable analysis task lifecycle

**Implement:** durable long-running analysis/research jobs using admitted BEAM orchestration primitives rather than inventing a new scheduler.

**Acceptance:** submit/status/stream/cancel/retry/replay on a real process analysis; node/process interruption is injected and the task either resumes or terminates with a typed receipted state.

## P0 — release and distribution

### PRO-013 — authenticated package/release channel

**Implement:** private package and/or release distribution with versioned immutable artifacts.

**Acceptance:** licensed clean consumer resolves an exact Pro version; unlicensed consumer cannot fetch it; already installed software does not require continuous vendor connectivity merely to run unless the commercial contract explicitly says otherwise.

### PRO-014 — signed release provenance

**Implement:** signed release manifest binding source SHA, pack/ontology/engine digests, generated artifacts, SBOM and qualification receipts.

**Acceptance:** tampering with any bound artifact causes verifier failure; the release can be reconstructed or at minimum provenance-verified from the declared inputs.

### PRO-015 — required repository/release gates

**Implement:** protect release-producing branches/tags with required deterministic/source-lock, runtime, fresh-consumer, Pro adoption, migration, security and receipt gates.

**Acceptance:** exact release head cannot be promoted when any required crown is non-ALIVE.

### PRO-016 — changelog + upgrade guide manufacture

**Implement:** human and machine-readable release delta from exact capability/migration/compatibility changes.

**Acceptance:** every release contains current install, upgrade and deprecation guidance; a verifier detects undocumented breaking contract/migration changes.

## P1 — agent-ready product operations

### PRO-017 — portable `AGENTS.md` doctrine

**Implement:** root and nested `AGENTS.md` files that restate source authority, allowed editing surfaces, exact regeneration commands, tests, privileged exception rules and subtree-specific constraints.

**Acceptance:** at least two different coding-agent workflows independently complete the same admitted manufacturing change without hand-editing manufactured output.

### PRO-018 — recipe catalog

**Implement:** deterministic recipes for the ten highest-frequency Pro changes, including adding a process metric, connector mapping, API operation, web view, migration, entitlement dimension, provider transport and release receipt.

**Acceptance:** recipes manufacture or edit only admitted inputs; each recipe declares preconditions, changed surfaces, verifier, reversibility and receipt.

### PRO-019 — MCP read/propose surface

**Implement:** MCP capabilities for docs/status/process/evidence/findings plus proposal/intention creation.

**Acceptance:** an external client can inspect a real process and propose a bounded change or `ToolIntent`; no MCP request can directly actuate external state without separate admission/BRCE.

### PRO-020 — A2A research/task edge

**Implement only if justified by a concrete multi-agent use case.**

**Acceptance:** external agent task artifacts enter as evidence/candidates; principal and authority are locally re-derived; task cancellation and failure are bounded and receipted.

## P1 — enterprise process-intelligence packs

### PRO-021 — BEAM semantic connector pack

**Implement:** adapters preserving OTP, Oban, Reactor, Broadway, Ash and Phoenix/Ecto semantics where observable.

**Acceptance:** one real cross-runtime BEAM workflow is reconstructed from native evidence and compared against a known expected process; retry/compensation/ack/supervision semantics are not flattened into anonymous adjacency.

### PRO-022 — OTLP evidence hub

**Implement:** traces/metrics/logs/resources/events/links ingestion and semantic registry handling.

**Acceptance:** replay a real multi-service trace corpus through ingest -> service graph -> process candidate with provenance and explicit unresolved semantics.

### PRO-023 — Kubernetes living topology

**Implement:** watch/reconcile cluster/workload/pod/service/job topology with resource-version identity.

**Acceptance:** create/update/delete/restart events in a real disposable cluster alter the living graph exactly once with replayable observations.

### PRO-024 — process twin persistence/time travel

**Implement:** designed/executable/observed/inferred/admitted/verified projections with time/version identity.

**Acceptance:** query the same entity/process at two known times and explain each edge from source evidence; inferred state never overwrites observed state.

### PRO-025 — process intelligence/economics productization

**Implement:** promote current revenue-suite seeds into typed, versioned product contracts where justified.

**Acceptance:** real fixtures produce rework, cycle/wait/WIP/throughput/conformance/economic findings with provenance, units, confidence/standing and customer-visible receipts; no fixture currency is mislabeled.

## P1 — commercial lifecycle

### PRO-026 — direct self-serve commercial experiment

**Implement:** one reversible direct-purchase/evaluation motion independent of cloud marketplaces.

**Acceptance:** acquire -> obtain license -> install -> receive update entitlement -> access support path is executed end to end with test commercial identities.

### PRO-027 — update-rights lifecycle

**Implement:** distinguish right-to-run from right-to-receive-updates.

**Acceptance:** expired update rights refuse fetching a newer release but do not corrupt or disable an already entitled perpetual/offline release if that license model was purchased.

### PRO-028 — support tiers and escalation contract

**Implement:** community/direct/enterprise or equivalent support definitions, response channels, data-handling boundaries and evidence expectations.

**Acceptance:** a support simulation starts from a doctor bundle and reaches reproducible diagnosis without undocumented privileged access.

### PRO-029 — ROI/value receipt

**Implement:** customer-controlled value evidence suitable for renewal/QBR.

**Acceptance:** exact process scope + baseline + subsequent observed state produce a non-double-counted value receipt whose sources and assumptions are inspectable; causal claims remain bounded to evidence.

## P2 — marketplace and sovereign closure

### PRO-030 — AWS transaction transport

**Acceptance:** real seller test environment executes offer/purchase -> entitlement -> usage/contract accounting -> cancellation/renewal/replay without double billing.

### PRO-031 — Microsoft transaction transport

Same acceptance shape with Microsoft-native agreement/meter semantics preserved.

### PRO-032 — Google transaction transport

Same acceptance shape with Google-native order/account semantics preserved.

### PRO-033 — signed offline/air-gap bundle

**Acceptance:** disconnected clean environment imports exact artifacts/license evidence, executes core Pro value, exports a redacted support/receipt bundle, and later applies a signed update without vendor egress.

### PRO-034 — fleet control

**Acceptance:** multi-environment estate demonstrates tenant/account/project isolation, centralized visibility, bounded policy distribution and no ambient cross-environment actuation authority.

## First closure sequence

The first implementation tranche should be deliberately narrow:

```text
PRO-001 current truth
PRO-002 package boundary
PRO-003 compatibility manifest
PRO-004 fresh install
PRO-005 OSS->Pro adoption
PRO-006 migrations
PRO-007 license evidence
PRO-008 doctor
PRO-009 minimal control plane
PRO-013 distribution
PRO-014 provenance
PRO-015 release gates
PRO-016 upgrade/changelog
PRO-017 AGENTS
PRO-018 recipes
```

This sequence produces something neither current exact-head Beam4PM nor a strategy document alone can provide: **a customer can acquire, install, understand, upgrade, diagnose, and safely extend a coherent Pro product.**

## Standing rule

Documentation is `ADMITTED PLAN`, not execution evidence. Each item remains `UNKNOWN`, `UNSUPPORTED`, `BLOCKED`, or `PARTIAL_ALIVE` until the exact acceptance behavior has been observed against the exact implementation subject.