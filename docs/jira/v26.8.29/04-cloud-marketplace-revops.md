# Cloud Marketplace Revenue Operations — v26.8.29

## Objective

Make beam4pm_pro purchasable, deployable, entitleable, supportable, renewable and expandable through the major cloud marketplaces without coupling the product runtime to any single cloud or requiring customer telemetry to leave the customer boundary.

The RevOps system covers the complete commercial process:

`lead -> qualify -> technical discovery -> value hypothesis -> proof -> marketplace route -> quote/private offer -> procurement -> entitlement -> deployment -> adoption -> value evidence -> expansion -> renewal`

Every stage has an owner, required evidence, exit criteria and replayable receipt.

## Commercial principles

1. Marketplace is a procurement/billing channel, not the product architecture.
2. Public listing unlocks discoverability and, where required, private-offer motions; enterprise revenue is expected to be primarily negotiated.
3. Private offers/plans are first-class, not exceptions.
4. Contract identity and runtime identity remain separate but correlated.
5. Customer data stays inside the customer boundary by default.
6. Metering never double bills across marketplace/provider mechanisms.
7. Renewal evidence accumulates from day one.
8. Air-gap and regulated deployment are premium operating modes, not bespoke forks.
9. Channel/reseller routes are planned from the beginning.
10. Every commercial state transition is receiptable.

## Canonical commercial objects

Create provider-neutral concepts that preserve provider identities:

- `MarketplaceProvider`
- `SellerAccount`
- `ProductListing`
- `Plan/SKU`
- `PricingDimension`
- `BuyerOrganization`
- `BuyerBillingIdentity`
- `Offer`
- `Agreement/Contract`
- `Entitlement`
- `Order`
- `UsageRecord`
- `Deployment`
- `Environment`
- `SupportEntitlement`
- `RenewalOpportunity`
- `ExpansionOpportunity`
- `CommercialReceipt`

Provider-specific IDs are never normalized away.

## AWS Marketplace lane

### Target product forms

Evaluate and qualify at least:

- SaaS contract;
- SaaS contract with consumption/overage where appropriate;
- deployment package or customer-managed runtime pattern that remains compatible with air-gap/private operation;
- channel partner private offer route after direct-sale closure is stable.

### Required integration capabilities

AWS contract-based SaaS integrations require customer resolution and entitlement validation. The current seller documentation also requires new SaaS products to handle concurrent agreements introduced for new products effective June 1, 2026. The canonical adapter therefore must key commercial state by agreement/license identity rather than assuming one product purchase per account.

Required test scenarios:

- first purchase/registration;
- entitlement activation;
- multiple concurrent agreements where supported;
- quantity/tier changes;
- contract upgrade;
- renewal;
- expiration/cancellation;
- private offer;
- flexible payment schedule;
- overage/metering when enabled;
- seller-side entitlement outage and replay;
- duplicate/reordered marketplace events;
- buyer organization/account topology changes.

### Private offers

Operationalize custom pricing, EULA/terms, payment schedule and buyer-account targeting as a standard enterprise quote-to-cash lane. Maintain CRM linkage from opportunity -> buyer AWS account(s) -> offer ID -> agreement/license -> entitlement -> deployment.

### Channel

Prepare CPPO/resale authorization capabilities only after direct private-offer operations are deterministic. Track partner margin, reseller identity, end-customer identity and renewal ownership separately.

## Microsoft Marketplace lane

### Target product form

Transactable SaaS offer with public and/or private plans as appropriate. Plan visibility must match intended acquisition route: public marketplace discovery plus private enterprise negotiation where useful.

### Required integration capabilities

- marketplace purchase/activation;
- SaaS fulfillment/subscription identity;
- plan identity and quantity;
- metered billing where selected;
- private-plan/private-offer customer scoping;
- upgrade/downgrade/renewal/cancellation lifecycle;
- duplicate/out-of-order event safety;
- correlation to Azure tenant/subscription/billing identities without conflating them.

### Commercial advantage

For eligible customers/offers, Microsoft Marketplace purchases can participate in committed-cloud-spend procurement motions. Sales qualification must therefore ask whether the buyer has Azure/Microsoft cloud commitments and whether marketplace procurement improves budget conversion.

## Google Cloud Marketplace lane

### Target product forms

Evaluate both:

- integrated SaaS product for transactable commercial relationship;
- Kubernetes application/private deployment form where customer-operated runtime is advantageous.

Google supports private offers for SaaS, VM and Kubernetes products, with flat-fee, usage-based and hybrid pricing options depending on product type. Private offers can be managed programmatically through Cloud Commerce/Producer APIs.

### Entitlement lifecycle

Use Partner Procurement API semantics while preserving `ENTITLEMENT_ID` as the commercial identity. Current Google guidance explicitly supports multiple orders of the same product, meaning implementation must not assume account ID or product ID uniquely identifies an active purchase.

Test:

- account approval if used;
- entitlement creation/approval;
- multiple orders;
- private-offer activation;
- scheduled start;
- amendment/replacement;
- monthly/upfront payment schedules;
- auto-renew where configured;
- usage reporting;
- reseller/private-offer-plan path;
- cancellation/expiration;
- Pub/Sub duplication/reordering/replay.

## Product packaging across marketplaces

Maintain one commercial vocabulary even when provider implementations differ.

Recommended dimensions to test:

### Base entitlement

Annual or multi-year right to operate beam4pm_pro for a bounded estate.

### Estate dimension

Potential defensible units:

- managed environment/cluster;
- service/process estate band;
- node/vCPU band where marketplace constraints favor infrastructure dimensions;
- governed process-instance/operation band;
- enterprise/fleet tier.

Do not price primarily on raw spans/log bytes unless the economics require it; telemetry volume can punish observability adoption and disconnect price from process value.

### Capability tier

- Observe — discovery, service/process graph, baseline metrics;
- Infer — continuous process inference and variants;
- Govern — conformance, policy, planning and enterprise controls;
- Sovereign — air-gap/offline/fleet/security/support package.

Names may change; the monotonic capability ladder should remain.

## Quote-to-cash operating procedure

### 1. Qualified opportunity

Required fields:

- legal/buyer organization;
- cloud provider(s);
- billing/account/tenant identifiers needed for private offer;
- target estate scope;
- data-boundary requirements;
- air-gap requirement;
- security/compliance constraints;
- decision owner;
- procurement owner;
- technical owner;
- quantified process problem;
- expected proof criterion;
- target start date;
- budget/commit route.

### 2. Technical discovery

Produce a bounded Environment Admission Record identifying observable surfaces and required privileges. No production write authority is requested for initial observation unless separately justified.

### 3. Proof

Deploy read-mostly/observe-only product scope, reconstruct process evidence, quantify at least one meaningful operational finding and record confidence/limits.

### 4. Commercial proposal

Map observed estate/value to package, term, usage band and support level. Select public purchase, private offer/plan, reseller/channel or non-marketplace contract only when marketplace path is unavailable or clearly inferior.

### 5. Marketplace transaction

Record offer/agreement/entitlement identity and acceptance evidence. Entitlement activation must be idempotent and auditable.

### 6. Deployment/activation

Deployment must bind to the commercial entitlement without making cloud-provider APIs a runtime single point of failure. Define grace/reconciliation behavior for marketplace API outages.

### 7. Adoption/value

Continuously collect product-local metrics sufficient to show process coverage, findings, usage and economic outcomes without exporting customer telemetry.

### 8. Expansion

Expansion triggers include:

- uncovered clusters/accounts/projects;
- adjacent business processes;
- repeated UNKNOWN semantics resolvable with richer integration;
- conformance/optimization demand;
- planning/governed-actuation demand;
- regulated/air-gapped estate.

### 9. Renewal

Begin evidence review at least 120 days before enterprise expiration. Renewal package includes realized metrics, adoption, support record, coverage gaps, expansion opportunities, roadmap fit, entitlement accuracy and marketplace private-offer timeline.

## CRM / RevOps state machine

Recommended opportunity states:

`DISCOVERED -> QUALIFIED -> TECH_ADMITTED -> PROOF_RUNNING -> VALUE_PROVEN -> COMMERCIAL_PROPOSED -> MARKETPLACE_OFFERED -> CONTRACTED -> DEPLOYED -> ADOPTING -> EXPANDING -> RENEWAL -> RENEWED`

Failure/side states:

- `DISQUALIFIED_NO_PROBLEM`
- `BLOCKED_PROCUREMENT`
- `BLOCKED_SECURITY`
- `BLOCKED_AUTHORITY`
- `BLOCKED_MARKETPLACE`
- `NO_DECISION`
- `CHURN_RISK`
- `CLOSED_LOST`

No stage is advanced based on optimism; require the defined receipt.

## Funnel metrics

Track separately by marketplace/provider/channel:

- qualified pipeline $;
- proof-start rate;
- proof-to-value-proven rate;
- value-proven-to-offer rate;
- private-offer acceptance rate;
- sales cycle by stage;
- marketplace processing latency;
- activation latency;
- time to first inferred process;
- time to first quantified finding;
- ACV/TCV;
- gross retention;
- net revenue retention;
- expansion source;
- support burden;
- cloud/provider fees;
- CAC payback when sales costs are observable;
- gross margin by deployment mode.

## RevOps automation requirements

Eventually manufacture/reconcile through ggen/integration packs:

- marketplace product/plan metadata;
- pricing dimension definitions;
- entitlement adapters;
- private-offer templates;
- security packet;
- order form/EULA metadata;
- deployment artifacts;
- customer activation checklist;
- renewal packet;
- sales evidence report;
- marketplace reconciliation report.

Automation is not allowed to silently create binding offers or terms without admitted commercial authority.

## Current marketplace source notes

Planning references captured 2026-08-29:

- AWS SaaS integration/pricing/private offers: `https://docs.aws.amazon.com/marketplace/latest/userguide/saas-integrate-contract.html`, `https://docs.aws.amazon.com/marketplace/latest/userguide/saas-pricing-models.html`, `https://docs.aws.amazon.com/marketplace/latest/userguide/private-offers-overview.html`
- Microsoft SaaS/transactable marketplace: `https://learn.microsoft.com/en-us/partner-center/marketplace-offers/plan-saas-offer`, `https://learn.microsoft.com/en-us/partner-center/marketplace-offers/transacting-commercial-marketplace`
- Google private offers/entitlements/Kubernetes: `https://docs.cloud.google.com/marketplace/docs/partners/offers`, `https://docs.cloud.google.com/marketplace/docs/partners/integrated-saas/manage-entitlements`, `https://docs.cloud.google.com/marketplace/docs/partners/kubernetes`

Provider documentation is mutable. Release gates must fetch/verify current requirements before submission rather than treating this document as permanent marketplace law.