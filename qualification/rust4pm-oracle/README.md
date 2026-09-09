# rust4pm-oracle

Differential-testing oracle that makes **rust4pm** (the
[`process_mining`](https://crates.io/crates/process_mining) crate,
<https://github.com/aarkue/rust4pm>) the CANONICAL process-discovery
implementation that beam4pm's generated DFG code is verified against.

## Why this exists

beam4pm ships ggen-manufactured discovery modules
(`beam4pm_discovery:traces_from_events/2` -> `dfg_from_traces/1` in Erlang,
`BeamPM.Discovery` in Elixir). Without an external oracle, every new BEAM
target would re-assert its own correctness against hand-written expectations —
and the ecosystem would grow duplicate, potentially divergent algorithm
implementations with no single source of algorithmic truth.

This crate closes that gap as a differential gate: the same event log is fed
to beam4pm's generated code and to this oracle, and the DFG edge sets must be
identical. The oracle's counting is done by rust4pm itself — an actively
maintained, independent process-mining implementation — not by code written
alongside beam4pm.

**Division of labor (load-bearing):** the adapter in `src/main.rs` only maps
the wire format into the crate's own `EventLog` representation. The
directly-follows counting is performed by the crate's own
`process_mining::discovery::case_centric::dfg::discover_dfg`
(`DirectlyFollowsGraph::discover`). No fallback counting was needed — the
crate exposes a real public DFG-from-log function, so there is **no disclosed
algorithm duplication** in this adapter.

## Pinned crate version

```toml
process_mining = { version = "=0.6.2", default-features = false }
```

Exact pin `=0.6.2` (latest on crates.io as of 2026-08-29; requires Rust 1.88+).
`default-features = false` — the crate's optional features (polars dataframes,
sqlite/duckdb, graphviz export, token-based replay, ...) are all unnecessary
here and several would not compile for `wasm32-wasip1`. With features off,
both native and `wasm32-wasip1` release builds succeed with no further feature
gymnastics (verified 2026-08-29, rustc 1.97.0, wasmtime 48.0.1).

## POWL differential testing (added on feature/rust4pm-powl-fork)

The oracle also exposes the fork's real POWL (Partially Ordered Workflow
Language) discovery, `process_mining::discovery::case_centric::powl::discover_powl`,
selected via an `"op": "powl"` field in the same wire input shape (omitted or
`"dfg"` keeps the original DFG-only behavior for backward compatibility).
Output is the `Powl` struct serialized as-is (it derives `Serialize` in the
fork) under a top-level `"powl"` key — real discovery output, not a
projection or stub. See the full wire contract restated at the top of
`src/main.rs`.

`testdata/concurrent_bc_events.json` exercises genuine concurrency: two
traces `[a,b,c]` and `[a,c,b]`. Real run:

```bash
cargo build --release
python3 -c 'import json;d=json.load(open("testdata/concurrent_bc_events.json"));d["op"]="powl";print(json.dumps(d))' \
  | ./target/release/rust4pm-oracle
```

produced (verified 2026-09-01):

```json
{"powl":{"root":{"PartialOrder":{"children":[{"Leaf":{"activity_label":{"Activity":"a"}}},{"Leaf":{"activity_label":{"Activity":"b"}}},{"Leaf":{"activity_label":{"Activity":"c"}}}],"order":[[0,1],[0,2]]}}}}
```

`a` precedes both `b` and `c` (`order` edges `[0,1]`, `[0,2]`); no edge
exists between `b` and `c` — the discovered model correctly leaves them
unordered rather than forcing a false directly-follows relation between
them.

`cargo test --release` runs two real subprocess integration tests
(`src/main.rs`'s `#[cfg(test)] mod tests`) that spawn the actual built
binary against `testdata/seeded_8_events.json` (op `dfg`) and
`testdata/concurrent_bc_events.json` (op `powl`) and assert on the real
stdout — no mocking of the wire contract.

## Wire contract (FIXED — all streams code against this)

stdin — one JSON object:

```json
{
  "case_attr_key": "<string>",
  "events": [
    {"event_id": "e1", "event_type": "receive_order",
     "event_time": "2026-08-29T10:00:00Z",
     "attributes": {"case_id": "c1"}}
  ]
}
```

Events are beam4pm `ocel_event` `to_map` objects (`event_id`, `event_type`,
`event_time`, `attributes`).

stdout — exactly this and nothing else:

```json
{"edges": [{"source_activity": "s", "target_activity": "t", "frequency": 1}]}
```

sorted by `source_activity` then `target_activity`.

Exit code 0 on success; nonzero with a reason on stderr for malformed input
(non-JSON, missing/mistyped required fields, an `attributes` value that is
present but not an object).

Grouping/sorting semantics mirror beam4pm's generated
`beam4pm_discovery:traces_from_events/2` exactly: the case id is read from
each event's `attributes` map at `case_attr_key`; events with absent/null
`attributes` or without that key are skipped (not an error); per case, events
sort by `event_time` (byte-wise lexicographic, i.e. ISO8601 order) with
`event_id` tie-break; `dfg_from_traces` counts adjacent activity pairs.

## Build

```bash
cargo build --release                                # native
cargo build --release --target wasm32-wasip1         # WASM (WASI preview 1)
```

## Run

```bash
./target/release/rust4pm-oracle < testdata/seeded_8_events.json
wasmtime run target/wasm32-wasip1/release/rust4pm-oracle.wasm \
    < testdata/seeded_8_events.json
```

## Verified result (real runs, 2026-08-29)

`testdata/seeded_8_events.json` is the seeded 8-event / 3-case order-to-ship
log from beam4pm's `examples/erlang/dfg_discovery_demo.erl` (events
deliberately shuffled in timestamp order). Native binary and
`wasmtime`-executed WASM produced **byte-identical** output
(sha256 `ac9fd660...f75123` for both):

```json
{"edges":[
  {"frequency":1,"source_activity":"receive_order","target_activity":"ship_order"},
  {"frequency":2,"source_activity":"receive_order","target_activity":"validate_order"},
  {"frequency":2,"source_activity":"validate_order","target_activity":"ship_order"}]}
```

The real Erlang demo (`erlc`-compiled generated modules, `escript` run of
`dfg_discovery_demo.erl`) printed the same three edges with the same
frequencies (`receive_order -> ship_order x1`,
`receive_order -> validate_order x2`, `validate_order -> ship_order x2`) —
the differential gate closes: beam4pm == rust4pm on this log.

## See Also

- `src/main.rs` — the full adapter, with the wire contract restated at the top
- beam4pm `generated/erlang/src/beam4pm_discovery.erl` — the generated
  implementation this oracle verifies
- rust4pm DFG discovery source:
  `process_mining-0.6.2/src/discovery/case_centric/dfg.rs`
