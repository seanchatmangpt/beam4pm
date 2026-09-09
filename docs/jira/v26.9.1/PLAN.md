# beam4pm v26.9.1 Workstream Plan

## Executive Summary

This document is a DMEDI-shaped (Define/Measure/Explore/Develop/Implement) plan for
the v26.9.1 cycle of beam4pm, grounded in real branch and commit activity from
2026-08-29 through 2026-09-01 (`git log`/`git branch -a` against
`origin/main`, HEAD at `489fe2b`). It is for engineers merging the active
revenue-workstream (WS1-WS5) and productization branches back to `main`.

## Define

The branch names and commit messages show a coordinated "revenue workstream" (WS1
through WS5) push plus several parallel productization/hardening branches:

- **WS1 (admission / commercial closure)** — `[WS1-REV-0xx]` commits build an
  "admission" and buying-center decision pipeline (engagement scope, engagement
  readiness, enterprise engagement, decision criteria, buying center maps, RFI
  ingestion). Goal: manufacture the evidence/ontology needed to admit and qualify
  enterprise revenue opportunities.
- **WS2 (price-to-cash / commercial contracts)** — `[WS2-REV-0xx]` commits build
  pricing, unit-economics, and business-unit-allocation ontology plus commercial
  contract closure work. Goal: manufacture the price-to-cash chain from quote to
  receipted revenue projection.
- **WS3 (runtime value / Fortune-5)** — `ws3-rev` commits build service health,
  capacity/performance envelopes, incident/recovery evidence. Goal: manufacture
  runtime-value evidence credible to a Fortune-5 buyer.
- **WS4 (trust evidence / publication court)** — trust-evidence-canonical and
  publication-court branches. Goal: canonicalize the trust/evidence layer backing
  the other workstreams' claims.
- **WS5 (revenue expansion)** — expansion/renewal evidence on top of WS1-WS4.
- **Productization branches** (`feat/beam4pm-pro-p0-capabilities`,
  `feat/pro-ocpm-simulation-tenancy`, `feat/transplants-from-ex4pm-xaas`,
  `feat/ws2-close-productization-loops-20260831`) — land OCPM discovery/what-if
  simulation, multi-tenancy, capability transplants from ex4pm/xaas (AshAi tools,
  per-type docs, engine health, overclaiming lint), and close out remaining
  productization gate loops (Gate M2 / ontology composition).
- **Infrastructure/hardening fixes** (`fix/cloudrun-google-provider-drift`,
  `fix/ws2-remove-temporary-ash-capture`) — remove a temporary Ash capture
  authority and fix a Cloud Run Google-provider Terraform template drift picked up
  via a ggen-marketplace pin bump.

Charter for v26.9.1: land the WS1-WS5 revenue-evidence manufacturing chain and the
parallel productization work as a coherent, gate-verified release, while removing
temporary/scaffolding authorities (Ash capture, provider drift) before rollout.

## Measure

Real branch state as of `git branch -a` / `git log` against `origin/main`
(`489fe2b`, 2026-09-01T03:24:45-07:00, "WS3: merge Fortune-5 runtime value crown"):

### Already merged into main (0 commits ahead of origin/main)

- `automation/ws1-rev-20260830-1958-commercial-closure` -- 7367a5d,
  2026-08-31T01:29:37-07:00 -- fix(manufacture): refresh Ash revenue
  projections after WS1 crown
- `automation/ws2-rev-commercial-contracts-20260830-1609` -- a72b4b2,
  2026-08-31T13:46:24-07:00 -- fix: re-merge main (WS5-REV landed), rename
  colliding value_realization record
- `automation/ws3-rev-20260831-runtime-value-50` -- ad5cfad,
  2026-08-31T22:49:58-07:00 -- merge(main): requalify WS3 crown on current
  integration subject
- `automation/ws4-rev-20260831-trust-evidence-canonical` -- 4dc41be,
  2026-08-31T14:19:33-07:00 -- fix: re-merge main (WS2-REV landed), full
  regeneration, no new collisions
- `automation/ws5-revenue-expansion-20260831` -- 262c68d,
  2026-08-31T13:11:19-07:00 -- Merge remote-tracking branch 'origin/main'
  into fix/pr36-ash-determinism
- `feat/beam4pm-pro-p0-capabilities` -- 0dc0aff, 2026-08-31T15:51:18-07:00 --
  fix(docker): exclude native/*/target/ from image build
- `feat/transplants-from-ex4pm-xaas` -- bb09b9d, 2026-08-31T17:15:02-07:00 --
  feat: four capabilities transplanted from ex4pm/xaas
- `fix/cloudrun-google-provider-drift` -- 3b1f5bc, 2026-08-31T12:53:33-07:00
  -- fix: bump ggen-marketplace pin for cloudrun_main_tf.tmpl fix
- `fix/ws2-remove-temporary-ash-capture` -- 35aca07, 2026-08-31T17:14:27-07:00
  -- chore(ws2): remove completed Ash capture court

These branches' tip commits are already contained in `main`'s history (their
merge/re-merge commits landed the content); they still exist as remote refs and
should be deleted post-verification (see Implement) rather than re-merged.

### Still ahead of main (real unmerged commits)

- `automation/ws1-rev-20260830-1100-fortune5-admission` -- 50 ahead, 052e889,
  2026-08-30T11:34:45-07:00 -- feat(pro): admit revenue admission decision
  [WS1-REV-050]
- `automation/ws1-rev-20260831-1205-revenue-admission-2` -- 30 ahead,
  f00194c, 2026-08-31T12:22:42-07:00 -- feat(pro): WS1-REV-080 rfi
  requirement ingestion
- `automation/ws2-rev-20260831-2212-price-to-cash-50` -- 53 ahead, 491f5d2,
  2026-08-31T22:29:13-07:00 -- build(ws2): publish receipted price-to-cash
  projections
- `automation/ws3-rev-20260830-1623-fortune5-runtime-value` -- 38 ahead,
  8f011d3, 2026-08-30T16:41:35-07:00 -- feat(ws3-rev): manufacture recovery
  evidence
- `feat/pro-ocpm-simulation-tenancy` -- 3 ahead, 626f85e,
  2026-08-31T21:59:30-07:00 -- docs: add docs/README.md index linking all
  four Diataxis quadrants
- `feat/ws2-close-productization-loops-20260831` -- 11 ahead, 15b5077,
  2026-08-31T20:53:53-07:00 -- fix(ws2): align Gate M2 with composed
  ontology O*

### Other branches present but out of scope for this plan

- `automation/beam4pm-pro-50-now-20260830` (2a10474, 2026-08-30)
- `automation/post-llm-governed-runtime` (97866a0, 2026-08-29)
- `automation/ws4-20260830-beam4pm-publication-court` (de6e121, 2026-08-30)
- `beam4pm-pro/commercial-control-plane-v1` (5454a69, 2026-08-30)
- `dependabot/github_actions/github-actions-edc9a20dd8` (577b00f, 2026-08-31)
- `docs/v26.8.30-pro-product-gap-closure` (31f6e03, 2026-08-30)

These were captured for completeness in the branch inventory but are not part of the
named WS1-WS5/productization charter; the dependabot branch should go through normal
CI-approved dependency merge, not this plan's gates.

## Explore

Branch names imply the following options/alternatives not yet reconciled:

1. **WS1 has two parallel admission lineages** —
   `automation/ws1-rev-20260830-1100-fortune5-admission` (50 commits, admission
   decisions WS1-REV-001..050) and
   `automation/ws1-rev-20260831-1205-revenue-admission-2` (30 commits, WS1-REV-051..080
   continuing into buying-center/decision-process/RFI ingestion). These read as
   sequential continuations of the same numbered ontology series rather than
   competing approaches — option: merge `-1100-fortune5-admission` first, then
   rebase/fast-forward `-1205-revenue-admission-2` on top, since REV-051 onward
   likely depends on REV-001..050 already existing.
2. **WS2 price-to-cash vs. commercial-contracts** — `commercial-contracts` is
   already merged (0 ahead); `price-to-cash-50` (53 commits, WS2-REV-060..109) is
   the active continuation. No competing alternative here, just sequencing.
3. **WS3 runtime-value-50 vs. fortune5-runtime-value** — `runtime-value-50` is
   already merged (0 ahead, tip is itself a "requalify WS3 crown" merge commit);
   `fortune5-runtime-value` (38 commits) is the earlier, still-unmerged lineage this
   crown was built from. Option: verify whether `fortune5-runtime-value`'s 38
   commits are already subsumed by the merged `runtime-value-50` tip (likely, given
   the "requalify... crown" language) before attempting a separate merge — a
   redundant merge risks re-introducing already-superseded evidence records.
4. **Productization gate closure vs. new capability** —
   `feat/ws2-close-productization-loops-20260831` (Gate M2 ontology alignment,
   Ash-capture-authority revocation) is closure work; `feat/pro-ocpm-simulation-tenancy`
   and `feat/transplants-from-ex4pm-xaas` are net-new capability. These are
   independent and can land in parallel, not as alternatives to each other.
5. **Provider-drift fix delivery mechanism** — `fix/cloudrun-google-provider-drift`
   fixes a Terraform template bug via a ggen-marketplace pin bump rather than a
   local template patch, consistent with the "search reusable capital first, don't
   hand-write" manufacturing principle; no local alternative needed if the pin bump
   is verified to actually change generated output.

## Develop

Concrete next engineering steps per branch/workstream to reach mergeable state:

### automation/ws1-rev-20260830-1100-fortune5-admission (50 ahead)
1. Diff against current `main` to confirm no conflicting admission-ontology IDs
   were introduced by branches merged after it forked.
2. Re-run the WS1 admission manufacture/regeneration pipeline against current
   `main` HEAD to confirm deterministic output (per repo's "receipted" pattern seen
   in other WS commit messages).
3. Resolve any collisions the same way `automation/ws2-rev-commercial-contracts`
   did ("rename colliding value_realization record, full regen").

### automation/ws1-rev-20260831-1205-revenue-admission-2 (30 ahead)
1. Rebase onto the post-merge tip of `-1100-fortune5-admission` (do not merge both
   independently against `main` if REV-051..080 depends on REV-001..050).
2. Re-run ingestion/regeneration for WS1-REV-051..080 records after rebase.

### automation/ws2-rev-20260831-2212-price-to-cash-50 (53 ahead)
1. Confirm this branch already contains the merged `commercial-contracts` tip
   (`a72b4b2`) in its history; if not, rebase onto current `main` first.
2. Re-run the "crown price-to-cash ontology expansion" manufacture step
   (WS2-REV-060..109) and the "publish receipted price-to-cash projections" step
   against current `main`, per the branch's own commit sequence.

### automation/ws3-rev-20260830-1623-fortune5-runtime-value (38 ahead)
1. Diff this branch's tip against the already-merged
   `automation/ws3-rev-20260831-runtime-value-50` tip to determine whether its
   evidence records are already subsumed.
2. If subsumed: close/delete this branch without merging (superseded).
3. If not fully subsumed: cherry-pick only the non-duplicate manufacture commits.

### feat/pro-ocpm-simulation-tenancy (3 ahead)
1. Small diff (3 commits: OCPM discovery/what-if simulation land, full Diataxis
   docs, docs index). Rebase onto current `main` and re-run doc-link verification
   (`docs/README.md` index).
2. Run PRO-011/012 OCPM discovery and what-if simulation feature tests.

### feat/ws2-close-productization-loops-20260831 (11 ahead)
1. Verify Gate M2 ontology composition (`O*`) alignment still holds against
   current `main`'s composed ontology.
2. Confirm the "authorize one receipted ggen publication" / "publish receipted
   ggen projections" / "revoke temporary generated-publication authority" sequence
   completed cleanly (temporary authority should be revoked, not left open, before
   merge).
3. Re-run the deterministic content-manifest verification step
   ("verify generated tree by deterministic content manifest").

### Already-merged branches (commercial-closure, commercial-contracts,
runtime-value-50, trust-evidence-canonical, revenue-expansion,
beam4pm-pro-p0-capabilities, transplants-from-ex4pm-xaas,
cloudrun-google-provider-drift, ws2-remove-temporary-ash-capture)
1. No merge action needed — confirm tip SHAs are reachable from `main` via
   `git merge-base --is-ancestor <sha> origin/main`.
2. Delete the stale remote branch refs after confirmation to reduce branch-list
   noise for the next cycle.

## Implement

### Merge order

Sequential merges only at the integration boundary (per the local
research/manufacturing-engine's "fan out maximally, integrate conservatively"
principle) — each step gated on the previous one's verification passing:

1. `fix/cloudrun-google-provider-drift` verification only (already merged;
   confirm ancestor).
2. `automation/ws1-rev-20260830-1100-fortune5-admission` -> merge to `main`.
3. `automation/ws1-rev-20260831-1205-revenue-admission-2` (rebased on step 2) ->
   merge to `main`.
4. `automation/ws2-rev-20260831-2212-price-to-cash-50` (rebased on current `main`)
   -> merge to `main`.
5. `automation/ws3-rev-20260830-1623-fortune5-runtime-value` -> resolve per Explore
   item 3 (supersession check) before any merge attempt.
6. `feat/ws2-close-productization-loops-20260831` -> merge to `main`.
7. `feat/pro-ocpm-simulation-tenancy` -> merge to `main`.
8. Delete stale already-merged remote branch refs (commercial-closure,
   commercial-contracts, runtime-value-50, trust-evidence-canonical,
   revenue-expansion, beam4pm-pro-p0-capabilities, transplants-from-ex4pm-xaas,
   ws2-remove-temporary-ash-capture).

### Verification/test gates (per merge step above)

- Deterministic-regeneration check: re-run the repo's ggen manufacture pipeline and
  diff generated output against the receipted manifest (per the
  "verify generated tree by deterministic content manifest" pattern already used on
  `feat/ws2-close-productization-loops-20260831`).
- Ontology collision check: confirm no duplicate/colliding record IDs across
  merged WS1/WS2/WS3 ontology expansions (the repo has already hit and fixed one
  such collision — `value_realization` record rename on
  `ws2-rev-commercial-contracts`).
- Gate M2 composed-ontology alignment check for any branch touching `O*`.
- Docker build check for `feat/beam4pm-pro-p0-capabilities`'s
  `native/*/target/` exclusion fix (confirm no locally pre-built wasm engine leaks
  into a fresh image build).
- Cloud Run Terraform provider check: apply-plan (not apply) the updated
  `cloudrun_main_tf.tmpl` output against a scratch/staging project to confirm the
  Google provider drift is actually resolved by the ggen-marketplace pin bump.

### Rollout and monitoring plan

1. After all merges land on `main`, tag the release candidate as `v26.9.1-rc1`.
2. Re-run the full receipted-manufacture pipeline once against the merged `main`
   tip to produce a single consolidated release receipt (per the "manufacturing
   receipt, not narrated summary" discipline) covering: which WS ontology records
   landed, which were superseded/dropped, and final SHA.
3. Stand up a standing verification check (cron or CI gate) that re-runs the
   deterministic-manifest diff against `main` on a schedule, to catch any future
   regeneration drift the same way the provider-drift and Ash-capture-authority
   issues were caught this cycle.
4. Monitor the revenue-evidence pipeline's receipted-projection outputs
   (price-to-cash, runtime-value, trust-evidence) post-merge for at least one full
   regeneration cycle before treating v26.9.1 as stable.

## References

- Repository: <https://github.com/seanchatmangpt/beam4pm>
- Branch/commit data captured via `git branch -a`, `git log --oneline`, and
  `git rev-list --count origin/main..<branch>` against a fresh clone,
  2026-09-01.

---

Last Updated: 2026-09-01
