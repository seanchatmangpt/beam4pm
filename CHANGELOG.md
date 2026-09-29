# Changelog

All notable changes to beam4pm are documented in this file.

## [26.9.10] - 2026-09-10

### Integrated

- Merged `feat/ocel-evidence-architecture` into `release/v26.9.10` off `main`
  (this merge transitively subsumed `integration/htn-fond-hddl`,
  `feat/ferroplan-hddl`, and `feat/htn-fond-dispatch`, all already ancestors
  of it — one clean, conflict-free merge).
- HTN/FOND dispatch (`htn_plan`/`fond_policy`) and ferroplan HDDL/FOND
  planning work.
- OCEL v2 evidence architecture: all 79 native-engine ops across the four
  engine facades (`petgraph`, `tract`, `rust4pm`, `ferroplan`) are
  telemetry-hooked (GATE EVIDENCE COVERAGE: 79/79, 0 findings). Of those 79
  hooked ops, 4 are exercised end-to-end by a real running test this pass
  (the `rust4pm.ocel_new` evidence-chain path plus its sibling checks) — full
  end-to-end exercise of the remaining ops is a disclosed follow-up, not
  claimed complete here.
- `vendor/ggen-marketplace` submodule advanced to the release marketplace
  commit plus one required follow-up: a reviewed ceiling raise
  (`AuthorshipKind_hand_authored_qualification`, 27 -> 30) needed because the
  merged work legitimately added 3 new admitted hand-authored qualification
  files.
- Fixed a real gap in `ggen-verify-pack`'s materialization: `ggen sync run`
  (no `--dry-run`) now completes cleanly, producing `VERIFICATION.md`,
  `scripts/verify-evidence.sh`, `scripts/produce-*.sh`, and
  `receipts/EVIDENCE_NOTE.md` for the first time in this consumer. Getting
  there required resolving real `FM-WRITE-005` silent-clobber refusals and
  `evidence_fresh`/`output_count_regression` gate trips by deleting stale
  generated files, re-emitting real `ver:Check` evidence bound to the new
  graph hash, and disclosing three `ver:AcceptedShrink` facts against the
  specific crashed/partial receipts — no ceiling or force-flag was used to
  route around a check.
- Fixed `scripts/gate_evidence_coverage_check.sh`'s static-grep pattern to
  recognize both the old per-op literal-atom `:telemetry.execute` call shape
  and the marketplace-merged template's new generic per-engine-op shape
  (semantically equivalent at runtime, different static text).

### Verified this pass

- GATE AUTHORSHIP, GATE ENGINE DISPATCH, GATE EVIDENCE COVERAGE, GATE
  LINT-TRUTH: all real-run PASS, 0 findings.
- `rebar3 eunit`: 3100/3100 passing (run twice against the fully materialized
  tree).
- `mix test`: 1073 tests, 11 failures, 57 skipped — matching the documented
  pre-existing RF2/RF3-oracle-environment baseline exactly; zero new
  regressions in the final state.

### Known open item

- GATE M2 (the destructive delete-regenerate-diff determinism check) was run
  once this pass and its own regenerate-step `mix test` run hit an async OTel
  span-export timing assertion
  (`BeamPM.EvidenceChainTest` `rust4pm.ocel_new ...`) before reaching any
  content-diff comparison. Its EXIT-trap safety net restored the pre-delete
  backup, so the working tree was unaffected, but GATE M2 has **not** yet
  confirmed byte-identical determinism for this state and should be re-run
  independently (it is destructive and outside `just verify`).
