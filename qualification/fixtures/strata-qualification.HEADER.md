# strata-qualification.json — fixture header (freshness law)

Pinned real court-emitted qualification report consumed by
`test/beam4pm_strata_qualification_ocel_test.exs` (sha256
`4b12771ac8872070f90a9b49b5aa7eab265e218278a3295abd4ddc6a5732287c`).

## Generation record

- **Generated at HEAD**: `fb123a452b52b64976185d1ad53937b2c52e7281`
  (ggen-marketplace, branch main)
- **ggen version**: `ggen 26.10.11`
- **As-of date**: 2026-10-13
- **Generation command** (run from `/Users/sac/ggen-marketplace`):

  ```bash
  python3 scripts/qualify_packs.py --report /tmp/strata-qualification-current.json \
    --workers 7 \
    --pack strata-cas-pack --pack strata-pn64-pack --pack strata-protocol-pack \
    --pack strata-signer-pack --pack strata-stratus-pack \
    --pack strata-temprun-pack --pack strata-valve-pack
  # then copy over qualification/fixtures/strata-qualification.json
  # and re-pin the sha256 in test/beam4pm_strata_qualification_ocel_test.exs
  ```

## Freshness law

The fixture is a snapshot, not a live surface. Refresh is required when BOTH:

1. the ggen-marketplace HEAD has moved past the HEAD recorded above, AND
2. at least one of the 16 `packs/strata-*` packs changed since that HEAD
   (`git -C <marketplace> log <as-of-head>..HEAD -- packs/strata-*` non-empty).

The meta-test in `test/beam4pm_strata_qualification_ocel_test.exs`
("freshness court ...") enforces this and fails naming the refresh command.

## Standing-delta allowlist (regeneration 2026-10-13)

Regeneration at HEAD `fb123a452` with ambient `ggen 26.10.11` produced
`/tmp/strata-qualification-current.json` (sha256
`ec36645cb50d877714b1c71cb6e51752567e7a1cc362944bc435ce4d8e734640`):

| pack | fixture standing | regenerated standing |
|---|---|---|
| strata-protocol-pack | REFUSED (`REFUSED:GGEN_PACK_SYNC_FAILED`, FM-GRAPH-013 BIND re-bind) | ALIVE |

All other packs in the pinned shard (strata-cas, strata-pn64, strata-signer,
strata-stratus, strata-temprun, strata-valve) keep standing ALIVE in both.
Because standings DIFFER, the old fixture is retained (not refreshed) and this
allowlist entry records both standings. The observed cause: the FM-GRAPH-013
SPARQL BIND re-bind graph error emitted by ggen 26.10.11 at fixture
generation time no longer fires for `strata-protocol-pack`'s queries.
