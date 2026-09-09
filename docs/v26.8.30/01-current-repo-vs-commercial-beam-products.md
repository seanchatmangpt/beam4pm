# Exact-Head Gap Analysis — beam4pm vs Commercial BEAM Product Archetypes

## Baseline and evidence boundary

This analysis is anchored to `seanchatmangpt/beam4pm@4fbbcc9d183d213b54f553fd276ae2311e18c53e` on 2026-08-30.

Observed repository facts at that head:

- `mix.exs` is still a small library project (`beam4pm 0.1.0`) with runtime dependencies on `ash` and `wasmex`; there is no observed Phoenix/Ecto/admin/control-plane dependency set.
- current doctrine identifies ggen/ggen_igniter manufacture, generated Erlang/Elixir/Gleam/Ash projections, deterministic regeneration, and rust4pm WASM as the process engine path;
- merged work on 2026-08-30 adds real object-centric discovery and a Pro-oriented revenue suite;
- `docs/reference/beam4pm-pro-revenue-suite.md` specifies executable economics, process-estate metering, entitlement admission, and Reactor workflow modeling;
- the repository's root README has drifted behind implementation by still describing `beam4pm_pro` as code that does not yet exist;
- `main` was observed without branch protection / required status checks enabled at the exact baseline.

This means the technical substrate is advancing faster than the customer-facing product contract.

## What the comparators actually prove

### Oban Pro pattern

Oban Pro's commercial strength is not merely its feature count. Its product mechanics are unusually clear:

1. **OSS foundation stays useful.** The paid product extends rather than replaces the open product.
2. **Drop-in adoption.** Customers can move from OSS to Pro with a small dependency/configuration/migration delta.
3. **Pro capabilities are named and coherent.** Engine, Worker, Rate Limit, Relay, Batches, Chains, Workflows, Decorators, plugins, testing, and related functionality are packaged as a comprehensible extension set.
4. **Operational concerns are productized.** Global concurrency, rate limiting, queue partitioning, lifecycle tracking, uniqueness, bulk operations, encryption, structured arguments, outputs, deadlines, signals, and migrations are not left to every customer to reinvent.
5. **Upgrade safety is documented.** Versioned migrations, prerequisites, deprecations, and release-specific upgrade instructions are first-class product material.
6. **Licensing/support are explicit.** A buyer can understand application scope, support level, enterprise procurement, and the difference between free and paid.

The transferable lesson for beam4pm is: **paid value must be an obvious extension of an already useful open substrate, with a predictable adoption and upgrade path.**

### Petal Pro pattern

Petal Pro uses a different but complementary commercial pattern:

1. **Complete production starting point.** Authentication, organizations, billing, notifications, admin, deployment, REST/OpenAPI, GDPR workflows, and UI conventions come together as one coherent product.
2. **Private-source/update-rights distribution.** Purchase grants access to a maintained source product and a defined update window; customers retain what they received.
3. **Opinionated consistency is the value.** The product explicitly sells stable decisions and patterns rather than raw lines of code.
4. **Agent-ready conventions are product surface.** `CLAUDE.md`, `AGENTS.md`, recipes, MCP tooling, and shared action/tool registries constrain AI-generated changes toward known patterns.
5. **Fast first success.** Installation is documented as an immediately runnable product rather than a library-construction exercise.
6. **Roadmap/support are visible.** Buyers can see the product evolving and know how to get help.

The transferable lesson for beam4pm is: **a Pro product must package all recurring surrounding decisions needed to operate the core capability, and agents must be able to extend it without architectural drift.**

## Gap matrix

| Product dimension | beam4pm exact-head state | Oban Pro pattern | Petal Pro pattern | Gap standing | v26.8.30 direction |
| --- | --- | --- | --- | --- | --- |
| OSS foundation | Real and increasingly capable | Strong OSS base | Open Petal components around paid Pro | `ALIVE/PARTIAL_ALIVE` | Preserve and strengthen |
| Paid product identity | Pro-oriented modules exist, but no independently installable Pro product boundary | Clear `oban` + `oban_pro` | Clear paid product/release identity | `UNSUPPORTED` | Define explicit package/product topology |
| OSS→Pro adoption | No observed one-command dependency/install/migration path | Drop-in enhancement | Start from release/project | `UNSUPPORTED` | `mix beam4pm.pro.install`/documented equivalent + compatibility checks |
| Upgrade/migrations | ggen regeneration exists; no observed versioned customer Pro migration contract | Strong versioned migrations and upgrade guides | Release/download/update guides | `PARTIAL_ALIVE` | Version canonical schema, pack, runtime migrations and rollback evidence |
| Licensing | Entitlement domain logic exists | Per-application licensing and enterprise terms | Project/team/update-right licensing | `PARTIAL_ALIVE` | Separate commercial license from marketplace entitlement; support offline evidence |
| Distribution | Public GitHub substrate; no observed paid package channel | Licensed package repository | Private GitHub/releases | `UNSUPPORTED` | Private Hex/OCI/release bundle + signed offline channel |
| Runtime product shell | Library/runtime modules | Library extension | Complete Phoenix product shell | `UNSUPPORTED` | Add optional `beam4pm_pro_web` control plane |
| Admin/operator UX | No observed Pro web console | Oban Web is a companion operational UI | Rich admin/dashboard UX | `UNSUPPORTED` | Process graph, findings, coverage, receipts, entitlement, diagnostics UI |
| Auth/tenant boundaries | Enterprise requirements documented; no observed product shell enforcing them | App-level concern, Pro has partitioning primitives | Built-in users/orgs/roles | `PARTIAL/UNSUPPORTED` | Canonical principal/org/tenant + RBAC for Pro web/API |
| Process engine | Real DFG/conformance/OCEL/rust4pm path | N/A | N/A | `PARTIAL_ALIVE` | Continue engine depth; do not confuse with product closure |
| Durable orchestration | Reactor model exists; no observed customer-facing durable task subsystem | Core paid value | Uses ecosystem jobs | `PARTIAL_ALIVE` | Use BEAM ecosystem rather than inventing scheduler; expose durable research/analysis jobs |
| Integrations | Roadmap documents BEAM/OTel/K8s; exact runtime surface is still narrow | Strong extension/plugin surface | Recipes/integrations | `PARTIAL/UNSUPPORTED` | Pro connector packs with compatibility matrices |
| API/interop | Generated library APIs; AI contracts exist | Library API | REST/OpenAPI + MCP | `PARTIAL_ALIVE` | Stable HTTP/OpenAPI + MCP read/propose + A2A task surface where justified |
| Agent readiness | Root `CLAUDE.md` is strong; no observed root `AGENTS.md` and no customer recipe catalog | Upgrade docs now include AI usage guidance | First-class CLAUDE/AGENTS/recipes/sub-agents | `PARTIAL_ALIVE` | Add generated/manufacturing-aware AGENTS + recipes + verifier hooks |
| Testing/qualification | Strong local deterministic tests and Chicago-style evidence in recent work | Dedicated Pro test helpers | End-to-end app conventions | `PARTIAL_ALIVE` | Add fresh-consumer Pro installation/upgrade/control-plane qualification |
| Product docs | Large v26.8.29 strategy corpus; README already stale | Product/feature/adoption/upgrade docs are concise and current | Installation/changelog/feature docs are customer-oriented | `PARTIAL_ALIVE` | Diátaxis split + generated capability inventory + release docs from exact head |
| Pricing | Strategy exists; final dollars intentionally UNKNOWN | Transparent self-serve + enterprise | Transparent one-time tiers + update rights | `PARTIAL_ALIVE` | Run pricing experiments without turning competitor prices into doctrine |
| Support | Strategy mentions support | Dedicated/enterprise support explicit | Customer/priority/dedicated support explicit | `UNSUPPORTED` operationally | Define support tiers, doctor bundle, escalation evidence, lifecycle policy |
| Marketplace | Entitlement/metering computation seeds exist; provider transport blocked | Conventional direct licensing | Direct paid source product | `PARTIAL_ALIVE` | Keep marketplace as enterprise procurement lane, not only route to revenue |
| Branch/release governance | Exact baseline main observed unprotected | Mature product release discipline implied by commercial delivery | Release-oriented distribution | `BLOCKED/UNSUPPORTED` | Required gates, signed releases, provenance, exact-head release receipt |

## Highest-value gaps

### G1 — The Pro boundary is semantic but not yet a product boundary

The repository has Pro-oriented capability code, but customers cannot currently point to one installable/licensed unit called `beam4pm_pro` with a compatibility contract. This creates ambiguity around what is open, what is paid, what is versioned, and what support covers.

**Closure:** make the open/pro split explicit in package metadata, build artifacts, licenses, docs, and upgrade tests without forking the canonical ontology.

### G2 — The current code proves capability faster than the documentation updates

The stale root README is concrete evidence of release-documentation drift. That is a product risk because a buyer or agent encounters the wrong state at the front door.

**Closure:** generate a machine-readable capability manifest and derive current-status docs from exact build/qualification receipts. Human prose may explain meaning; it must not be the sole source of current feature state.

### G3 — There is no observed paid-customer first-run path

A sophisticated process engine is not a product until a licensed customer can install it, connect evidence, see a useful finding, understand standing, and recover from failure.

**Closure target:**

```text
obtain entitlement/license
-> add/install beam4pm_pro
-> run doctor
-> deploy or start locally
-> ingest bundled real fixture
-> discover graph/process
-> display finding + provenance + receipt
-> verify entitlement/support/update status
```

### G4 — Upgradeability is under-specified for a manufactured product

Generated code does not remove migration risk. The canonical ontology, ggen pack, wire schemas, runtime storage, connector contracts, licenses, and customer state all evolve.

**Closure:** every release needs a compatibility matrix and versioned migration graph across:

`beam4pm version × beam4pm_pro version × ontology schema × pack version × rust4pm engine × runtime storage schema × connector/API versions`.

### G5 — Product UX is absent from the exact runtime surface

Petal Pro and Oban Web demonstrate that operational products need a visible shell. For beam4pm, the shell is not generic CRUD; it is the place where evidence, process scope, UNKNOWN, conformance, value findings, receipts, entitlement, and diagnostics become operable.

**Closure:** create `beam4pm_pro_web` as an optional product projection, not the canonical domain model.

### G6 — Agent readiness needs repository-wide authority awareness

The existing `CLAUDE.md` is strong, but paid customers will use multiple coding agents. Agent guidance must be portable and enforceable rather than model-brand specific.

**Closure:** root and nested `AGENTS.md`, generated recipe catalog, explicit edit-authority metadata, MCP/A2A surfaces that return intents rather than performing ambient actuation, and verifier commands that every agent can run.

## What not to build

The comparison also removes false work:

- Do **not** build a second general-purpose background job system to mimic Oban Pro. Integrate with the BEAM job/orchestration ecosystem where needed.
- Do **not** add generic blog/CMS/product CRUD because Petal Pro includes it.
- Do **not** force Phoenix into the OSS core. The web control plane belongs in an optional Pro projection.
- Do **not** duplicate canonical process semantics in a separate commercial data model.
- Do **not** treat a license check as runtime authorization for BRCE actuation.
- Do **not** make an LLM/MCP client an authority principal simply because the customer paid for Pro.

## Resulting target archetype

beam4pm_pro should be:

> **Oban-Pro-like in extension discipline, Petal-Pro-like in completeness and agent readiness, and uniquely beam4pm in evidence-bounded process intelligence, deterministic manufacture, formal projection, and receipted authority.**

That is the gap to close.