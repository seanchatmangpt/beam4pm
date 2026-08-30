# Security, Air-Gap and Compliance — v26.8.29

## Security objective

beam4pm_pro must be deployable where process telemetry is operationally sensitive and cannot be exported to a vendor-controlled SaaS. Security therefore begins with architecture, authority and provenance rather than a late compliance checklist.

## Core security invariants

1. No mandatory customer telemetry export.
2. No ambient production write authority.
3. Observation authority and actuation authority are distinct.
4. Planner/LLM/model output never becomes DO authority by itself.
5. Every privileged actuation flows through BRCE and produces a receipt.
6. Every artifact is attributable to exact source/manufacturing inputs.
7. Customer identity, marketplace entitlement and runtime identity are correlated but not conflated.
8. Air-gapped mode is a real execution mode, not a slideware claim.

## Deployment trust zones

Define explicit zones for:

- marketplace control/entitlement integration;
- product runtime;
- telemetry collection;
- process model/storage;
- UI/API;
- update channel;
- optional planning/optimization;
- BRCE actuation broker;
- customer targets.

Document allowed edges and required identities for each deployment mode.

## Zero-egress / air-gap requirements

Target `AIRGAP_ALIVE` behavior:

- install from customer/private registry or signed offline bundle;
- no DNS/HTTP dependency on beam4pm vendor services after activation;
- local OTel collection and processing;
- local model/inference execution;
- local storage/indexing;
- local UI/API;
- local audit/receipt store;
- customer-controlled secrets/keys;
- offline license/entitlement evidence with a defined reconciliation process;
- signed update import/export workflow;
- SBOM and provenance included with every release;
- deterministic replay of update/install validation.

If a marketplace requires online entitlement validation, define explicit disconnected grace/escrow/reconciliation semantics rather than hiding the dependency.

## Data classification

beam4pm_pro may observe data that reveals:

- service topology;
- business process structure;
- customer/account identifiers;
- URLs/operation names;
- database/message metadata;
- failure patterns;
- timing/volume;
- logs with potentially sensitive payloads.

Default collection policy should minimize payload capture and prefer semantic identifiers/metadata sufficient for process inference. Raw payload collection must be separately admitted.

## Least privilege

Initial discovery should request read-only/watch/telemetry permissions sufficient for stated process-intelligence goals. Write/control permissions are not bundled into observability access.

Kubernetes/RBAC, cloud IAM, BEAM node connectivity, database/broker access and OTel receivers must each publish a machine-readable permission manifest.

## Source/manufacturing supply-chain security

Because beam4pm is a ggen-only proof:

- authoritative manufacturing inputs are enumerated;
- generated source carries provenance metadata;
- direct human/LLM source authorship is rejected by policy;
- privileged source exception commits are identifiable and independently receipted;
- build inputs/toolchains are pinned or otherwise identified;
- SBOM is generated;
- release artifacts are signed;
- image/package digests are recorded;
- rebuild/reprojection checks detect unexplained drift.

A generated artifact without reproducible lineage is `UNSUPPORTED_PROVENANCE`, not release-ready.

## Marketplace secret separation

Provider credentials used for seller/entitlement APIs must be separated from customer telemetry/process credentials. A compromise of marketplace integration should not imply process-data access, and vice versa.

## Multi-tenancy and fleet isolation

For connected fleet modes:

- explicit tenant/org/environment identity;
- no cross-customer process graph joins;
- bounded query authorization;
- per-tenant encryption/keys where applicable;
- rate/usage/accounting isolation;
- audit of administrative access;
- customer-controlled export/delete policies.

Air-gapped deployments remain independent by design.

## BRCE security boundary

Any future remediation/control feature must maintain:

`intent -> admission -> authority -> actuation -> receipt -> replay`

Required receipt fields include:

- exact subject;
- requested action;
- requesting principal/system;
- admitting policy/authority;
- credentials/capability class used (not secret material);
- target identity;
- pre-state evidence;
- consequence;
- post-state evidence;
- time/order;
- replay/verifier reference.

No hook, planner, generated recommendation or process inference may bypass this boundary.

## Compliance posture

Do not claim certifications before they exist. Build evidence architecture so future certification is inexpensive.

Prepare controls/evidence mapping for likely enterprise requirements:

- SOC 2-style security/availability/change-management evidence;
- ISO 27001-style ISMS control mapping;
- FedRAMP/NIST-oriented federal control/evidence needs where targeted;
- HIPAA/BAA operational separation where applicable;
- PCI-related segmentation when payment systems are observed;
- export-control/data-residency requirements;
- customer-specific secure software development/supply-chain requirements.

Each is `PLANNED` until independently validated/certified where certification is required.

## Secure update lifecycle

`admitted source/spec -> ggen manufacture -> test -> SBOM/provenance -> sign -> publish -> customer import -> signature verification -> compatibility/admission -> deploy -> post-deploy verification -> receipt`

Air-gapped updates must support rollback and retained prior artifacts.

## Security acceptance

Minimum pre-enterprise gates:

- threat model;
- permission manifest;
- no-egress test;
- secret scan;
- dependency/SBOM generation;
- signed artifact verification;
- privilege-boundary tests;
- tenant isolation tests where applicable;
- marketplace entitlement replay/idempotency tests;
- backup/restore/recovery test;
- support diagnostic workflow that does not require hidden vendor access.

`SECURITY_ALIVE` requires execution of these controls against the exact release artifact; documents alone remain `PARTIAL_ALIVE`.