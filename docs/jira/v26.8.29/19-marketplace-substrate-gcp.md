# GCP Marketplace Substrate — v26.8.29

Updated 2026-08-29. Companion to docs 04 (cloud marketplace RevOps), 05
(pricing/packaging), and 11 (release gates); records what GCP Marketplace
substrate has been locally manufactured for beam4pm_pro ahead of any seller
account, and at exactly what standing.

## Objective

Manufacture everything a Google Cloud Marketplace submission needs that can
lawfully exist **before** MP0 (seller onboarding), so that when the external
authorities arrive, the remaining work is binding identities and filing — not
authoring. Honest boundary: this doc claims only local, verifiable substrate.
A marketplace listing is not a successful purchase; a generated file is not a
runtime proof (doc 11).

## What was manufactured

### 1. Listing collateral (this stream, I3)

`marketplace/gcp/listing/`:

- `application.yaml` — `marketplace.cloud.google.com/v1` Application
  definition: beam4pm_pro identity, input schema (deployment type, project,
  region, capability tier, estate band, image, scaling, observability),
  deployment manifests pointing at the stream I1/I2 terraform trees, output
  schema;
- `schema.yaml` — deployment-UI input schema with
  `x-google-marketplace`/`x-google-property` hints and conditional
  visibility rules per deployment type;
- `parameters.yaml` — schema-input → terraform-variable mappings for the
  I1/I2 modules, and commercial-input → entitlement-policy mappings that
  deliberately have **no** terraform binding (tier is entitlement policy,
  never a feature fork — doc 05 principle 6);
- `metadata.display.yaml` — display metadata with placeholder pricing
  dimensions and no dollar values;
- `README.md` — the per-gate MP0–MP9 standing map.

Verification executed: every YAML parses under PyYAML (`yaml.safe_load`);
grep confirms doc 05 dimension names are quoted, and no secret-shaped
strings or real project ids exist (outputs recorded in the stream receipt).

### 2. Deployment substrate (concurrent streams, referenced)

- Stream I1 — `marketplace/gcp/terraform/cloud-run`: Cloud Run deployment of
  the GHCR container; locally verifiable via `terraform validate`;
- Stream I2 — `marketplace/gcp/packer` + `marketplace/gcp/terraform/vm`:
  packer-built GCE image and VM terraform; locally verifiable via
  `packer validate` / `terraform validate`.

This doc does not restate those streams' verification results; their own
receipts are authoritative (doc 11: do not restate a status without
re-deriving it).

### 3. Deployable artifact (referenced)

`ghcr.io/seanchatmangpt/beam4pm` — the beam4pm container published by the
concurrently-manufactured container workflow. GHCR is the manufacturing
source of truth; Marketplace hosting requires an Artifact Registry mirror,
which is part of the MP1 filing work, not of this substrate.

## Pricing dimensions used

Taken verbatim from doc 05, preserved per DfCM (multiple lawful models until
evidence selects):

1. Capability ladder tiers: **Observe, Infer, Govern, Sovereign**.
2. Model A — **estate bands** (governed environment/cluster/service-estate
   band) — the default UI dimension (`estate_band`).
3. Model B — **process scope** (discovered/governed process-estate band).
4. Model C — **capacity units** (marketplace-compatible capacity basket).
5. Model D — **platform commitment + overage** (private-offer fit).

Dollar levels: `UNKNOWN`, exactly as doc 05 records them. No file in this
substrate encodes a price.

## MP gate standing summary

Full per-gate table with substrate status:
`marketplace/gcp/listing/README.md`. Summary:

- MP0–MP9: all `BLOCKED` on external authority (seller account, listing
  review, Procurement API, billing integration, approved buyer);
- MP1 substrate: **manufactured and locally verified** (this stream);
- MP4 substrate: **manufactured** as streams I1/I2 terraform;
- MP3/MP6/MP7 substrate: **partial** — entitlement/pricing dimension
  vocabulary declared, adapters and meters not manufacturable pre-MP0;
- MP2/MP8/MP9: no local substrate is possible; admitted test plan lives in
  doc 04's Google lane (entitlement lifecycle, Pub/Sub
  duplication/reordering/replay).

`GCP_MARKETPLACE_ALIVE`: `BLOCKED`. This substrate cannot and does not
change that; it shortens the path from MP0 to MP1 filing.

## Newly available manufacturing edges

1. When a seller account exists (MP0): bind real publisher identity into
   `application.yaml`/`metadata.display.yaml`, mirror the GHCR image to
   Artifact Registry, and file the producer-portal submission from this
   collateral.
2. Before MP0: the Partner Procurement entitlement adapter (MP3) can be
   manufactured against the documented API shapes and doc 04's test-scenario
   list, Chicago-style against a recorded/replayed event fixture — a separate
   stream, out of I3 scope.
3. Doc 05's pricing-model selection needs buyer evidence, not more substrate.

## See Also

- `docs/jira/v26.8.29/04-cloud-marketplace-revops.md` — Google lane and
  entitlement lifecycle test plan
- `docs/jira/v26.8.29/05-pricing-packaging-unit-economics.md` — pricing
  dimension source of truth
- `docs/jira/v26.8.29/11-release-gates-receipts.md` — MP gate definitions
  and standing vocabulary
- `marketplace/gcp/listing/README.md` — per-gate MP0–MP9 standing map
