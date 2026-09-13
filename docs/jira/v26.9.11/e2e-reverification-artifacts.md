# Capture real e2e re-verification artifacts for qualification

## Summary

Re-verification of the finished HDDL->FOND->A2A->OCEL->POWL pipeline regenerated the
`qualification/gym_bridge` fixtures and the full BRCE engine-op receipt chain under
`receipts/engine_ops/`.

## Status

Done - already merged/committed.

## Commits

- c639d69 chore(qualification): capture real e2e re-verification artifacts

## Changes

- `qualification/gym_bridge/reference_ocel_events.json`: refreshed event_ids/timestamps
  from a fresh Step-5 e2e deviation-detection run (same 3-meeting/6-phase shape, new
  UUIDv7 event_ids and capture times).
- `qualification/gym_bridge/deviant_ocel_events.json`: same refresh as above for the
  deviant fixture.
- `receipts/engine_ops/`: 4331 real BRCE receipt-chain JSON files
  (`receipt_schema=beam4pm-brce/v1`) produced by the native engine facades
  (petgraph/tract/rust4pm/ferroplan) during this session's fresh re-verification run,
  each hash-chained via `prev_receipt_hash`/`chain_seq`.

## Verification

None stated beyond the fact that the artifacts are the product of "a fresh Step-5
e2e deviation-detection run" and "this session's fresh re-verification run" per the
commit message. No test/lint/CI command output is included in the commit message.

## Related

None stated (no PR number or branch name in the commit subject).
