# beam4pm_pro Release and Commercial Acceptance — v26.8.30

## Objective

Define the evidence ladder that separates:

- useful process-mining code;
- Pro capability seeds;
- an installable Pro package;
- a supportable product;
- a paid-ready release;
- a marketplace/enterprise commercial product.

A named feature, package, workflow, receipt, or CI job does not establish standing by itself. `ALIVE` requires observed execution against the exact admitted subject.

## Evidence dimensions

For every crown, track these independently:

- **observed** — what source/artifact/runtime state was actually inspected;
- **admitted** — exact subject/version/config/policy accepted for the test;
- **executed** — command/workflow/customer path actually ran;
- **changed** — persisted or external consequences, if any;
- **verified** — independent acceptance checks and verifier output;
- **inferred** — conclusions that are not direct observations;
- **refused** — typed policy/authority rejection;
- **blocked** — missing external capability/authority;
- **unsupported** — intentionally absent behavior.

Inspection is not execution. CI metadata is not CI logs. A license is not authority. A package existing is not a successful install. A receipt-shaped object is not necessarily an actuation receipt.

## Crown ladder

### C0 — `BEAM4PM_OSS_FOUNDATION_ALIVE`

Required:

- exact source identity;
- deterministic manufacture/source-lock;
- Erlang/Elixir/Gleam/Ash projections as claimed;
- rust4pm engine execution as claimed;
- real examples/playground;
- cross-language/wire identity for every claimed leg;
- exact process-mining algorithm disclosure.

Pro release work must not weaken this crown.

### C1 — `BEAM4PM_PRO_PACKAGE_ALIVE`

Required:

1. immutable/versioned Pro artifact exists;
2. dependency on compatible OSS package is explicit;
3. Pro artifact contains no duplicate canonical domain fork;
4. licensed consumer can resolve/install the exact artifact;
5. unlicensed fetch/use behavior matches the commercial contract;
6. package provenance and digest verify.

### C2 — `BEAM4PM_PRO_ADOPTION_ALIVE`

Execute both paths:

#### Fresh install

```text
fresh supported app
-> install OSS + Pro
-> compatibility check
-> configure/migrate
-> doctor
-> bundled real fixture
-> process finding
-> receipt
```

#### OSS -> Pro

```text
working OSS consumer
-> capture OSS receipt
-> add Pro
-> migrate/configure
-> re-run OSS acceptance
-> run Pro acceptance
-> prove intended semantic continuity
```

A hand-edited fixture application that bypasses the advertised installer does not crown adoption.

### C3 — `BEAM4PM_PRO_UPGRADE_ALIVE`

Required:

- supported N-1 Pro release with realistic persisted state;
- documented compatibility preflight;
- versioned migration execution;
- source/manufacturing regeneration as required;
- upgrade verifier;
- exact post-upgrade product path;
- rollback proof or typed declaration of irreversible edges;
- old client/API behavior tested for the documented compatibility window.

Oban Pro's upgrade discipline is the benchmark pattern: release evolution is part of the product contract, not an implicit "update dependencies and hope" operation.

### C4 — `BEAM4PM_PRO_CONTROL_PLANE_ALIVE`

Required web/operator execution:

- authenticate as an admitted principal;
- view estate/evidence scope;
- execute or inspect real analysis;
- inspect process variants/conformance/economics;
- follow a finding to source evidence and receipt;
- distinguish `UNKNOWN`, `UNSUPPORTED`, `BLOCKED`, `REFUSED`, `PARTIAL_ALIVE`, `ALIVE`;
- inspect connector/product/license health;
- produce a support bundle.

A screenshot or rendered static page is not enough.

### C5 — `BEAM4PM_PRO_AGENT_READY_ALIVE`

Required:

- root/nested authority doctrine is machine-consumable and human-readable;
- at least two distinct coding-agent implementations are tested;
- each completes the same admitted change by editing lawful manufacturing inputs;
- each regenerates and validates through the exact repo commands;
- direct modification of manufactured output is rejected/detected;
- common recipes carry preconditions, intended changes, verifier and rollback/replay information;
- MCP/agent tools produce read results or candidates/intents, never ambient `DO`.

Petal Pro's agent-ready consistency is the benchmark pattern; Beam4PM adds stronger source-authority and receipt requirements.

### C6 — `BEAM4PM_PRO_SUPPORTABLE_ALIVE`

Run a support drill against seeded failures:

- incompatible versions;
- stale migration;
- malformed/tampered license;
- missing/failed connector;
- broken engine artifact;
- provenance/source-lock mismatch;
- inaccessible evidence source;
- denied operational authority.

The customer-generated doctor bundle must contain enough redacted evidence to locate the failed transition without undocumented vendor access.

### C7 — `BEAM4PM_PRO_PAID_READY_ALIVE`

Requires C0-C6 plus:

- commercial SKU/license terms exist;
- acquire -> license -> install path executed with a test buyer identity;
- update-rights lifecycle is enforced as documented;
- release artifact is signed/provenance-bound;
- customer-facing install/upgrade/changelog docs match the exact release;
- required repository/release gates are enforced;
- first-value path is bounded and repeatable;
- support channel/escalation process is operationally defined;
- no critical product claim relies solely on roadmap prose.

This is the first crown at which "beam4pm_pro is a product customers can buy" is defensible.

### C8 — `BEAM4PM_PRO_ENTERPRISE_ALIVE`

Requires C7 plus:

- tenant/principal/RBAC isolation;
- multi-environment/fleet evidence;
- SSO/identity integration where product scope requires it;
- retention/export/redaction controls;
- signed SBOM/release evidence;
- private procurement/invoice/contract path or equivalent;
- enterprise support drill;
- security and upgrade evidence suitable for buyer review.

### C9 — `BEAM4PM_PRO_SOVEREIGN_ALIVE`

Requires:

- disconnected installation from signed offline artifacts;
- no mandatory runtime egress for claimed core value;
- offline license/entitlement verification;
- customer-managed key integration points if claimed;
- local telemetry/storage/inference path for claimed capabilities;
- disconnected doctor/support bundle export;
- signed offline upgrade with replayable provenance.

### C10 — `BEAM4PM_PRO_MARKETPLACE_REVOPS_ALIVE`

Per claimed cloud marketplace, execute with real provider test/seller authority:

```text
listing/offer
-> buyer transaction
-> entitlement/order observation
-> local entitlement reconciliation
-> deployment/license binding
-> usage/contract accounting
-> provider report transport where required
-> invoice/reconciliation evidence
-> upgrade/renewal/cancellation
-> outage/retry/replay
```

Provider transport currently described as absent remains `BLOCKED`/`UNSUPPORTED` until that exact edge executes. Local metering calculations do not crown marketplace billing.

## Productization gates derived from the comparators

### Oban-Pro-derived gate: extension continuity

Pro must be an enhancement to the OSS product rather than a migration to a parallel architecture.

**Falsifier:** installing Pro requires replacing core canonical Beam4PM APIs or maintaining two incompatible process identities.

### Oban-Pro-derived gate: migration discipline

Every persistent Pro state evolution has a versioned migration and upgrade guide.

**Falsifier:** customers must infer schema changes from source diffs or manually patch state.

### Petal-Pro-derived gate: first-success completeness

A licensed customer can reach a running, useful product without designing auth/admin/deployment/diagnostic patterns from scratch.

**Falsifier:** every customer must assemble the same surrounding product shell before they can see Beam4PM value.

### Petal-Pro-derived gate: agent consistency

The repository/product gives coding agents enough authoritative context and deterministic recipes that common changes converge on the same architecture.

**Falsifier:** different agents routinely invent competing patterns or directly edit manufactured files because the lawful path is not discoverable.

### Beam4PM-specific gate: evidence/authority separation

No commercial/product convenience may collapse observed, inferred, admitted, authorized and executed states.

**Falsifier:** a paid entitlement, UI button, model tool call, or connector result can directly produce unreceipted external actuation.

## Release candidate receipt

Every Pro release candidate should emit a machine-readable receipt containing at least:

```text
repository
source_sha
source_tree
beam4pm_version
beam4pm_pro_version
ontology_schema_version
pro_schema_version
oss_pack_digest
pro_pack_digest
rust4pm_engine_digest
runtime_migration_version
api_schema_digest
connector_manifest_digest
license_schema_version
sbom_digest
artifact_digests[]
validation_commands[]
validation_exits[]
consumer_fixture_identity
upgrade_fixture_identity
crown_statuses{}
known_blockers[]
known_unsupported[]
release_falsifiers[]
```

The release is a graph of evidence, not a tag name.

## Pricing and licensing experiments

Competitor prices are external evidence, not target prices:

- Oban Pro demonstrates that a narrow, high-value BEAM extension can sustain recurring per-application licensing plus enterprise procurement/support.
- Petal Pro demonstrates that full-source product kits can sell as one-time/project/team purchases with a defined update window and retained access to acquired versions.

Beam4PM should test both commercial mechanics where reversible:

1. **direct developer/departmental license** — low procurement friction;
2. **annual/multi-year enterprise license** — estate/capability scope and priority support;
3. **sovereign lifecycle contract** — offline artifacts, regulated evidence, premium support;
4. **cloud marketplace private offer** — procurement route, not a separate product fork.

Final dollar levels remain `UNKNOWN` until buyer evidence exists.

## Definition of done for v26.8.30 closure work

The documentation gap is closed when this package exists and accurately bounds the target product. The **implementation** gap is not closed until `C7 BEAM4PM_PRO_PAID_READY_ALIVE` is observed against an exact release candidate.

The narrowest current falsifier remains simple:

> If a new paying customer cannot acquire an immutable Pro artifact, install/adopt it into a supported application, run a real first-value path, understand its standing, upgrade it predictably, and generate a supportable evidence bundle, then beam4pm_pro is not yet a commercial product regardless of how advanced the underlying process engine becomes.