# beam4pm_pro — GCP Marketplace Listing Substrate

Updated 2026-08-29. Manufactured by stream I3 of the beam4pm_pro cloud-deployment
substrate effort. This directory is producer-portal submission collateral for a
future Google Cloud Marketplace listing of beam4pm_pro. It is hand-authored
ops collateral (the schema shapes are provider-defined), modeled on a real
BEAM-product Marketplace kit and adapted to beam4pm_pro.

## What exists (locally verified)

| File | Purpose | Verification |
| --- | --- | --- |
| `application.yaml` | Marketplace Application definition (`marketplace.cloud.google.com/v1`): identity, input schema, deployment manifests | parses with PyYAML |
| `schema.yaml` | Deployment-UI input schema (JSON Schema draft-07 with `x-google-marketplace` / `x-google-property` hints) | parses with PyYAML |
| `parameters.yaml` | Schema-input → Terraform-variable mappings (streams I1/I2) and commercial-input → entitlement-policy mappings | parses with PyYAML |
| `metadata.display.yaml` | Listing display metadata: descriptions, capability tiers, placeholder pricing dimensions, regions, features | parses with PyYAML |

Deployment manifests reference the concurrently-manufactured terraform trees:

1. `marketplace/gcp/terraform/cloud-run` — stream I1, Cloud Run deployment of
   `ghcr.io/seanchatmangpt/beam4pm:latest`;
2. `marketplace/gcp/terraform/vm` + `marketplace/gcp/packer` — stream I2,
   packer-built Compute Engine VM image.

Pricing content is **placeholder dimensions only**, taken verbatim from
`docs/jira/v26.8.29/05-pricing-packaging-unit-economics.md`: the
Observe/Infer/Govern/Sovereign capability ladder and the four preserved
commercial models (Model A — estate bands, Model B — process scope, Model C —
capacity units, Model D — platform commitment + overage). No dollar values
appear anywhere — doc 05 records dollar levels as `UNKNOWN` pending buyer
discovery, and this substrate does not turn a price guess into doctrine.

No secrets, no real GCP project ids, and no real seller identities appear in
any file; defaults use placeholders such as `beam4pm-pro-demo`.

## What is BLOCKED on external authority

A marketplace listing is not a successful purchase; an entitlement object is
not a deployed customer system (doc 11, "Evidence dimensions"). Everything
below requires authorities that do not exist yet:

- a Google Cloud Marketplace **seller/producer account** and executed seller
  agreements;
- **listing review/acceptance** by Google;
- **Cloud Commerce / Partner Procurement API** integration (entitlements,
  orders, `ENTITLEMENT_ID` lifecycle, Pub/Sub events);
- **billing/metering** registration of any usage dimension;
- an approved **test or production buyer**.

## Gate map — MP0–MP9 standing

Gate definitions: `docs/jira/v26.8.29/11-release-gates-receipts.md`
("Marketplace gates — common"). Standing vocabulary is used exactly as
defined there. "Substrate manufactured" below means: the local, submittable
collateral this stream could lawfully produce exists and parses; it never
implies provider-side state.

| Gate | Definition | Standing | Substrate status |
| --- | --- | --- | --- |
| MP0 | Seller/provider onboarding: seller account/agreements/permissions exist | `BLOCKED` (external authority: Google seller onboarding) | Substrate manufactured: publisher identity fields present as explicit placeholders in `application.yaml`/`metadata.display.yaml`, ready to be bound to a real seller identity |
| MP1 | Listing accepted in required marketplace state | `BLOCKED` (requires MP0 + Google listing review) | Substrate manufactured: `application.yaml`, `schema.yaml`, `parameters.yaml`, `metadata.display.yaml` — the local half of a producer-portal submission |
| MP2 | Purchase path: approved buyer executes subscription/purchase | `BLOCKED` (requires MP1 + approved buyer) | No substrate is manufacturable locally; purchase is wholly provider-side |
| MP3 | Entitlement: beam4pm_pro receives/reconciles entitlement/order state idempotently | `BLOCKED` (requires Partner Procurement API access) | Partial substrate: entitlement-dimension vocabulary (`capability_tier`, `estate_band`) is declared in `parameters.yaml` as entitlement-policy bindings; the reconciliation adapter itself is not part of this stream |
| MP4 | Deployment: purchased entitlement activates an exact deployment path | `BLOCKED` (requires MP3) | Substrate manufactured: the deployment paths themselves exist locally as streams I1/I2 terraform (locally `terraform validate`-verifiable), referenced from `application.yaml` manifests |
| MP5 | Value path: entitled deployment performs real process discovery/inference | `BLOCKED` as a marketplace gate (requires MP4); the underlying value path exists in beam4pm (generated discovery/conformance, playground) independent of any entitlement | Substrate exists upstream in beam4pm (M0–M6 closure per `docs/jira/v26.8.29/16-gate-closure-m0-m6.md`) |
| MP6 | Billing/metering reconcile exactly; no double billing | `BLOCKED` (requires seller account + billing integration) | Partial substrate: usage-dimension candidates named in `metadata.display.yaml` with identities from doc 05; no meter is registered anywhere |
| MP7 | Private offer/plan executes | `BLOCKED` (requires MP1; Google private offers support flat-fee, usage-based, hybrid) | Substrate manufactured: Model D (platform commitment + overage) preserved in `parameters.yaml` as the private-offer-fit candidate |
| MP8 | Lifecycle: upgrade/amendment, renewal, cancel/expiration proven | `BLOCKED` (requires MP2/MP3) | No local substrate beyond dimension vocabulary; lifecycle events are provider-side |
| MP9 | Failure/replay: provider API/event failure, retry, reconciliation executed | `BLOCKED` (requires Pub/Sub + Procurement API access) | No local substrate; test scenarios enumerated in `docs/jira/v26.8.29/04-cloud-marketplace-revops.md` (Google lane) are the admitted test plan |

Crown standing: `GCP_MARKETPLACE_ALIVE` requires MP0–MP9 closure and is
therefore `BLOCKED`. Nothing in this directory advances any gate past
`BLOCKED`; what it advances is the amount of work remaining between "seller
account exists" and "submission filed", which is the entire lawful scope of a
pre-seller-account stream.

## Replay / verification procedure

From the collateral root:

```bash
for f in marketplace/gcp/listing/*.yaml; do
  python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1])); print('OK', sys.argv[1])" "$f"
done
grep -rn "estate band\|process scope\|capacity unit\|commitment" marketplace/gcp/listing/
grep -rniE "(api[_-]?key|secret|password|token|AKIA|-----BEGIN)" marketplace/gcp/listing/ || echo "no secret patterns"
```

## See Also

- `docs/jira/v26.8.29/19-marketplace-substrate-gcp.md` — the numbered doc
  tying this listing substrate to streams I1/I2 and the MP gate map
- `docs/jira/v26.8.29/05-pricing-packaging-unit-economics.md` — pricing
  dimension source of truth
- `docs/jira/v26.8.29/11-release-gates-receipts.md` — gate definitions and
  standing vocabulary
- `docs/jira/v26.8.29/04-cloud-marketplace-revops.md` — Google Cloud
  Marketplace lane, entitlement lifecycle test plan
