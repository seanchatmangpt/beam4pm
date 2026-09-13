# Expose hddl_solve/htn_plan/fond_policy at the Elixir/BEAM layer (ferroplan)

## Summary

The ferroplan-wasm dispatch layer (`native/ferroplan/crates/ferroplan-wasm/src/wasi_abi.rs`)
already implemented three wire ops -- `htn_plan`, `fond_policy`, `hddl_solve` -- but they had
no Elixir/Erlang/Gleam facade. This ticket documents admitting `bpm:EngineOp`/`bpm:EngineArg`
ontology facts for these three ops (opOrder 31/32/33 on `bap:engine_ferroplan`), regenerating
the BEAM-layer projection via ggen, and confirming the new facade functions reach the real wasm
engine.

## Status

Done - already merged/committed.

## Commits

- `2b098ad` feat(ferroplan): expose hddl_solve/htn_plan/fond_policy at the Elixir/BEAM layer

## Changes

- Admitted `bpm:EngineOp`/`bpm:EngineArg` ontology facts for `htn_plan`, `fond_policy`,
  `hddl_solve` at opOrder 31/32/33 on `bap:engine_ferroplan`, following the existing
  `plan`/`plan_production` domain/problem/limits pattern (`limits` as
  `EngineArgType_optional_map` / `ArgMode_optional` / `omit_when_nil`), matching the real
  `req.get("limits")` handling already present in `wasi_abi.rs` for these ops.
- Ran a full clean ggen regeneration (colima/docker was initially down with an I/O error on
  temp-dir creation; fixed via `colima restart`). The regen surfaced pre-existing drift on the
  branch unrelated to the new ops (an authorship-gate test and `engine_ops.tsv` stale from the
  `origin/main` merge at `b2c4768`), so the regen deleted every GENERATED-marker file under
  `src`/`lib`/`test`/`gleam`/`schema`/`docs-reference`/`.github-workflows` plus the
  `ggen_igniter` Ash projection and per-record-type docs, then re-ran `ggen sync run` +
  `scripts/igniter_sync.sh`.
- `lib/beam4pm_ferroplan.ex` now has real generated functions:
  - `def htn_plan(domain, problem, limits \\ nil, opts \\ [])`
  - `def fond_policy(domain, problem, limits \\ nil, opts \\ [])`
  - `def hddl_solve(domain, problem, limits \\ nil, opts \\ [])`
  each firing `[:beam4pm, :engine, :ferroplan, op]` telemetry on both branches.
- As a side effect of the template regeneration, `beam4pm_petgraph.ex`, `beam4pm_rust4pm.ex`,
  and `beam4pm_tract.ex` now all carry the same per-op `:telemetry.execute/3` evidence-contract
  instrumentation that ferroplan already had, confirming the template extension applies
  uniformly across engines, not only to ferroplan.

## Verification

Per the commit message:

- `scripts/gate_engine_dispatch_check.sh`: PASS -- ferroplan 33 wire ops checked against 33
  dispatch arms in `wasi_abi.rs`, 76 total ops across 4 engines, 0 unexposed.
- `scripts/gate_authorship_check.sh`: PASS -- 37 admitted, 0 findings.
- `mix compile --warnings-as-errors`: clean (622 files).
- `rebar3 eunit`: All 3100 tests passed.
- `mix test test/beam4pm_ferroplan_test.exs test/beam4pm_ferroplan_facades_test.exs test/beam4pm_engine_dispatch_gate_test.exs`:
  39 tests, 0 failures.
- `mix test` (full suite): 1065 tests, 11 failures, 46 skipped -- all 11 failures stated as
  pre-existing/environmental (`BeamPM.Rf2ConformanceTest` needs `RF2_ORACLE_BIN`;
  `BeamPM.RF3OcelTest` references an external fixture repo, `/Users/sac/wasm4pm/fixtures`, not
  present in this repo), confirmed unrelated to this change by re-running one directly and
  reading its stacktrace.
- Real smoke test: `BeamPM.Ferroplan.hddl_solve/2` against the real `ferroplan-hddl`
  `fixtures/a/{domain,problem}.hddl` content reaches the real wasm module (dispatch is real, no
  adapter-level error), but the native `ferroplan::hddl::solve_hddl` call panics inside the wasm
  sandbox (`unwrap_failed` at `ferroplan_wasm.wasm!ferroplan::hddl::solve_hddl`, surfaced to
  Elixir as `{:error, {:wasmex, "...wasm trap: unreachable..."}}`). Commit message states this is
  a genuine bug in the native `ferroplan-hddl` solve path on this fixture, not a wrapper/dispatch
  defect, and that fixing the native panic was out of scope for this change.
- Commit message additionally notes `scripts/gate_evidence_coverage_check.sh` does not exist in
  this repo (checked), so the telemetry coverage claim was verified directly by grep + gate
  output instead.

## Related

No PR numbers or branch names are mentioned in the commit subject or message.
