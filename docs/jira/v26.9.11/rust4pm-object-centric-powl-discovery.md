# Object-centric POWL discovery via real flattening bridge (rust4pm)

## Summary

Adds a new wire op `ocel_discover_powl` to the rust4pm-wasm engine. It builds a
real flat `EventLog` from an OCEL log restricted to one `object_type` (one
trace per object, containing every event e2o-related to that object, ordered
by the event's real OCEL timestamp, not insertion order), then runs the
existing real `discover_powl` recursive choice-graph inductive miner already
used by the flat-log `discover_powl` op. This is a flattening bridge between
existing real primitives, not a new multi-object POWL algorithm — no
object-centric POWL algorithm exists anywhere in this crate or repo.

Disclosed limitation (from commit message): one flattening choice per object
type. An event shared by several objects of the same type is duplicated
across their traces (divergence); an event's relations to OTHER object types
are dropped entirely, so true multi-object convergence (e.g. several item
objects re-converging at one shared shipment event) is not modeled.

## Status

Done — already merged/committed.

## Commits

- `8e31631` feat(rust4pm): object-centric POWL discovery via a real flattening bridge

## Changes

- New wire op `ocel_discover_powl` in `native/rust4pm-wasm/src/lib.rs`
- Ontology: added `bap:engine_rust4pm_op_ocel_discover_powl` (+2 `bpm:EngineArg`
  individuals) to `ontology.ttl`, opOrder 32, following the existing admission
  pattern of other real rust4pm EngineOps
- ggen sync run regenerated: Elixir facade (`lib/beam4pm_rust4pm.ex`), Erlang
  facade (`src/beam4pm_rust4pm.erl`), Gleam stats surface, and
  `schema/beam4pm_engine_ops.tsv`
- Re-pinned the T14 hand-authored-source admission's `contentSha256`
- New Chicago-style test T14 (`test/beam4pm_rust4pm_test.exs`): builds a real,
  small, in-test OCEL v2 log (2 "meeting" objects — one with its 3 events
  inserted deliberately out of chronological order — plus 1 "room" object),
  runs `ocel_discover_powl`, and asserts exact structural equality on the
  discovered POWL model (a `PartialOrder` over 3 leaves reconstructing the
  correct schedule→notify→close sequence for both objects) plus the
  `object_type` filter (room object's event never leaks into the meeting
  flattening; an unknown `object_type` is refused with a real engine error)

## Verification

Per the full commit message:

- `cargo build -p rust4pm-wasm` (native + wasm32-wasip1 release): clean
- ggen sync run: clean (full clean-slate regen after a pre-existing
  drift-induced FM-WRITE-005, matching the gate_m2 clean-regen pattern)
- `mix compile --warnings-as-errors`: clean
- `rebar3 eunit`: All 3100 tests passed
- `scripts/gate_engine_dispatch_check.sh`: PASS, 0 findings
- `scripts/gate_authorship_check.sh`: PASS, 0 findings
- `mix test`: 1066 tests, 13 failures, 1 invalid, 20 skipped — differential
  baseline confirmed via `git stash` on the unchanged commit: 1065 tests, 13
  failures, 1 invalid, 20 skipped (identical failure set: RF2/RF3
  oracle-binary/env-var-absent tests, pre-existing and environmental). Net:
  +1 test (T14), +0 regressions.

## Related

None stated — no PR number or branch name mentioned in the commit subject or message.
