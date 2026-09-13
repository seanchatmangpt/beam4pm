# Close the plan-execute-conform loop: real POWL conformance checking vs accumulated OCEL v2 traces (Step 5)

## Summary

`BeamPM.PowlConformance.check_conformance/3` closes the plan-execute-conform
loop by combining Step 4's object-centric POWL discovery
(`ocel_discover_powl`, via flattening) with the existing alignment
operations (`discover_alphappp/align_trace/compute_fitness`). It discovers a
reference POWL model plus an independently alignable Petri net from a
reference OCEL log's real flattened variant traces
(`ocel_variants_of_object_type`), then checks a candidate trace against that
net, returning real fitness plus a real list of deviating alignment moves
(never a boolean).

A disclosed, real limitation is stated in the module's own moduledoc: the
rust4pm engine has no POWL -> Petri-net conversion op, so alignment cannot
run directly against a `discover_powl`/`ocel_discover_powl` result; the net
is discovered from the identical flattened traces the POWL model itself was
discovered from. Also disclosed: Alpha+++'s default
`absolute_df_clean_thresh` (10) silently produces a degenerate 0-place net
over a handful-of-traces reference log (observed directly while developing
this), so a small-log config (`thresh: 1`, every other field restated
verbatim from the crate's own `Default`) is used instead.

## Status

Done - already merged/committed.

## Commits

- `de1c33f` feat(powl): close the plan-execute-conform loop -- real POWL conformance checking against real accumulated OCEL v2 traces (Step 5)

## Changes

- Added `BeamPM.PowlConformance.check_conformance/3`, combining Step 4's
  `ocel_discover_powl` with the existing `discover_alphappp` /
  `align_trace` / `compute_fitness` alignment ops to check a candidate
  trace against a reference OCEL log and return real fitness plus a real
  list of deviating alignment moves.
- Documented, in the module's own moduledoc, the rust4pm engine's lack of a
  POWL -> Petri-net conversion op and the workaround (discovering the
  alignable net from the identical flattened traces the POWL model was
  discovered from).
- Configured a small-log Alpha+++ threshold (`absolute_df_clean_thresh: 1`,
  other fields left at crate defaults) to avoid the degenerate 0-place net
  produced by the crate's default threshold (10) on small reference logs.
- Added `test/beam4pm_powl_conformance_test.exs`: a real in-test
  3-meeting/6-phase OCEL log; asserts a conforming trace aligns at real
  cost 0, and a deliberately injected phase-skip or phase-reorder
  deviation is really detected (nonzero cost, a real model-only move
  naming the skipped activity, fitness < 1.0).
- Added `test/beam4pm_powl_conformance_e2e_test.exs`: reads
  `qualification/gym_bridge/{reference,deviant}_ocel_events.json` (real,
  ingest-confirmed OCEL events captured by ash_a2a's own e2e test: real
  HDDL plan -> real A2A dispatch -> real HTTP POST to this repo's
  `BeamPM.OcelIngest.Router`, real 201 responses), rebuilds a real
  in-process OCEL log, and asserts the real captured `clean_house`-skip
  deviation is really detected by `PowlConformance`.
- Admitted both new test files and the conformance module as
  `bpm:HandAuthoredSource` individuals (`ontology.ttl`); raised the
  `hand_authored_qualification` ceiling 30 -> 32 in the vendored pack
  (submodule bump) to admit the 2 new tests and the module itself under
  `native_engine_facade` (same precedent as `lib/beam4pm_ocel.ex`).
- Performed a full clean ggen sync run to resolve pre-existing merge drift
  on the branch, regenerating `test/beam4pm_authorship_gate_test.exs`,
  `docs/reference/beam4pm_hand_authored_source.md`, and
  `schema/beam4pm_hand_authored_source.tsv`.

## Verification

Per the commit message:

- `mix test test/beam4pm_powl_conformance_test.exs test/beam4pm_powl_conformance_e2e_test.exs`: 4 tests, 0 failures
- `scripts/gate_authorship_check.sh`: PASS (40 admitted, 33 debt)
- `scripts/gate_engine_dispatch_check.sh`: PASS (77 wire ops, 0 unexposed)
- `scripts/gate_lint_truth.sh`: PASS (55 files, 0 findings)
- `rebar3 eunit`: All 3100 tests passed
- `mix compile --warnings-as-errors`: clean
- `mix test` (full suite): 1070 tests, 13 failures, 1 invalid, 20 skipped --
  identical failure set/count to the pre-change baseline (RF2/RF4
  oracle-binary-absent / `RF2_ORACLE_BIN`-unset, all pre-existing and
  environmental), 0 regressions (net +4 tests vs baseline)

## Related

No PR numbers or branch names stated in the commit subject or message.
