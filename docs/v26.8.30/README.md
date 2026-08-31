# beam4pm / beam4pm_pro v26.8.30 — Product Gap Closure

## Purpose

This package converts the v26.8.29 commercial vision into a productization closure plan grounded against the exact current repository and two useful BEAM commercial-product archetypes:

- **Oban Pro** — an open-source foundation with a narrow paid extension layer, a low-friction OSS→Pro adoption path, explicit licenses, versioned migrations, upgrade guides, dedicated support, and enterprise procurement.
- **Petal Pro** — an opinionated paid product kit with private-source distribution, a complete production surface, clear update rights, strong onboarding, repeatable recipes, and agent-readable conventions.

The comparison is about **product mechanics**, not feature equivalence. Oban Pro is a durable job-orchestration product and Petal Pro is a Phoenix SaaS product kit; beam4pm is a process-mining/process-intelligence substrate. The goal is to import the strongest commercial and developer-experience patterns without weakening beam4pm's source-authority, evidence, receipt, or BRCE invariants.

## Exact baseline

Comparison baseline:

- repository: `seanchatmangpt/beam4pm`
- branch: `main`
- exact SHA: `4fbbcc9d183d213b54f553fd276ae2311e18c53e`
- observed date: 2026-08-30

At that exact head, the repository has moved materially beyond the original v26.8.29 prose:

- the rust4pm WASM engine exposes real OCEL 2.0 JSON/XML import/export and object-centric DFG/variant discovery;
- the Fortune-5 revenue suite has been merged, including process economics, metering, entitlement admission, and a Reactor workflow model;
- `BeamPM.Billing` and `BeamPM.Entitlement` are executable surfaces rather than merely future concepts;
- the hard regeneration/determinism gate is represented in the current development doctrine;
- the root README is stale relative to the code: it still says `beam4pm_pro` does not exist as code, while current generated/runtime surfaces already include Pro-oriented revenue capabilities.

The correct status is therefore not "no Pro work exists." It is:

- **PROCESS_ENGINE: PARTIAL_ALIVE** — substantial exact-head process-mining execution exists.
- **PRO_CAPABILITY_SEEDS: PARTIAL_ALIVE** — revenue, entitlement, metering, governance/receipt-related surfaces exist inside the current repository.
- **PRO_PRODUCT_BOUNDARY: UNSUPPORTED** — no separately installable/licensed `beam4pm_pro` product contract is established at the inspected head.
- **PRO_DISTRIBUTION_AND_UPGRADE: UNSUPPORTED** — no observed paid package channel, customer install path, versioned Pro migration contract, or update-rights mechanism.
- **PRO_CONTROL_PLANE: UNSUPPORTED** — no observed Phoenix/LiveView administration and process-intelligence product UI at the current runtime dependency surface.
- **ENTERPRISE_COMMERCIAL_CLOSURE: PARTIAL_ALIVE** — entitlement/revenue computation exists locally, but provider transaction transport, customer lifecycle, support, and marketplace closure remain open.

## Product thesis for v26.8.30

`beam4pm_pro` should become an **orthogonal paid extension and product shell over the same canonical manufacturing graph**, not a fork of `beam4pm` and not a collection of unrelated enterprise code.

The target relationship is:

```text
beam4pm OSS substrate
        |
        +--> beam4pm_pro          paid process-intelligence extensions
        +--> beam4pm_pro_web      operator/admin/process UI
        +--> beam4pm_pro_connectors enterprise evidence/connectivity packs
        +--> beam4pm_pro_enterprise licensing, fleet, air-gap, support evidence
```

All application-source families remain manufactured from admitted ontology/spec/template inputs. Pro packaging changes **capability availability and distribution**, not source authority.

## Decisions

1. **Adopt Oban Pro's extension discipline.** A customer already using `beam4pm` should be able to add Pro without replacing the OSS API or forking their process model.
2. **Adopt Petal Pro's complete-product discipline.** Pro must include the operational surfaces customers otherwise have to reinvent: onboarding, admin/process UI, auth/tenancy where relevant, diagnostics, deployment recipes, upgrade paths, documentation, examples, and agent-readable recipes.
3. **Do not copy irrelevant features.** A blog/CMS, generic SaaS CRUD, or a second job scheduler are not product requirements merely because Petal Pro or Oban Pro contain them.
4. **Do not make an external commercial BEAM product a hidden runtime requirement.** Integrations with Oban/Oban Pro/Petal/Phoenix are valuable; beam4pm_pro's own standing must remain independently testable.
5. **Make upgradeability a first-class product feature.** Versioned schema/ontology migrations, generated-source regeneration, compatibility matrices, upgrade guides, and rollback evidence are part of the product, not release notes afterthoughts.
6. **Make agent readiness deterministic.** `CLAUDE.md`, `AGENTS.md`, machine-readable recipes, MCP/A2A read/proposal surfaces, and verifier commands must point agents toward the lawful manufacturing path rather than direct source mutation.
7. **Keep pricing reversible.** v26.8.29 correctly leaves final dollar prices `UNKNOWN`. External price points are evidence for experiments, not doctrine.

## Package index

- [`01-current-repo-vs-commercial-beam-products.md`](01-current-repo-vs-commercial-beam-products.md) — exact-head comparison and gap matrix.
- [`02-beam4pm-pro-product-contract.md`](02-beam4pm-pro-product-contract.md) — target product topology, installation, licensing, upgrades, UX, support, and agent contract.
- [`03-gap-closure-backlog.md`](03-gap-closure-backlog.md) — prioritized implementation epics with executable acceptance criteria.
- [`04-release-and-commercial-acceptance.md`](04-release-and-commercial-acceptance.md) — release crowns and the definition of a paid-ready Pro product.

## External benchmark sources

Observed 2026-08-30:

- Oban Pro overview: https://oban.pro/docs/pro/overview.html
- Oban Pro pricing: https://oban.pro/pricing
- Oban Pro upgrade guidance: https://oban.pro/docs/pro/v1-7.html
- Petal Pro pricing/product surface: https://petal.build/pricing
- Petal Pro AI-ready product surface: https://petal.build/pro/ai
- Petal Pro installation: https://docs.petal.build/petal-pro-documentation/fundamentals/installation

## Scope rule

This package is a **closure specification**, not evidence that any newly described product surface is implemented. A capability moves to `ALIVE` only when the exact admitted subject executes against the acceptance condition and produces a replayable receipt.