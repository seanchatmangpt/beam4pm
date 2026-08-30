# rf3-ocel-oracle

Differential-testing oracle for STREAM RF3:
`process_mining::bindings::slim_ocel_bindings` (`locel_new`, `locel_add_event_type`,
`locel_add_object_type`, `locel_add_event`, `locel_add_object`, `locel_add_e2o`,
`locel_add_o2o`, `locel_construct_ocel`) plus process_mining's real OCEL 2.0 JSON
importer, run against real `~/wasm4pm` OCEL fixtures — including the real
negative/adversarial fixtures under `wasm4pm/fixtures/negative/`.

## Pinned crate version

```toml
process_mining = { version = "=0.6.2", default-features = false, features = ["bindings"] }
```

The `bindings` feature is REQUIRED: `process_mining::bindings` is
`#![cfg(feature = "bindings")]` at the top of `src/bindings/mod.rs` — without it
none of this oracle's imports resolve at all.

## Real-function ground truth (read from the crate's own vendored source under
`~/.cargo/registry/src/.../process_mining-0.6.2/src`, not guessed)

* `process_mining::bindings::slim_ocel_bindings` is a **private** module
  (`mod slim_ocel_bindings;`, not `pub mod`). Its `#[register_binding]`
  functions (`locel_new`, `locel_add_event_type`, ...) are themselves private
  free functions, reachable only through the crate's dynamic binding-call
  registry (`bindings::call`/`bindings::list_functions`), never as plain Rust
  API. Each is a one-line, zero-extra-logic trampoline around a real **public**
  inherent method of `SlimLinkedOCEL` (e.g. `locel_add_event_type` is exactly
  `ocel.add_event_type(&event_type, attributes)`). This oracle calls those real
  `SlimLinkedOCEL` methods directly — the identical code path the private
  trampolines wrap — since running them as plain Rust does not require also
  standing up the crate's dynamic binding-call machinery.
* `num_events`, `num_objects`, `ocel_type_stats`, and `slim_link_ocel` ARE real,
  `pub`, directly-callable functions, but they live at the top of
  `process_mining::bindings` itself (`src/bindings/mod.rs`), not inside
  `slim_ocel_bindings.rs`. `slim_link_ocel(&OCEL) -> SlimLinkedOCEL` is exactly
  `SlimLinkedOCEL::from_ocel(ocel.clone())`.
* The real OCEL 2.0 JSON importer is
  `process_mining::core::event_data::object_centric::ocel_json::import_ocel_json_path`
  — there is no `import_ocel_json` re-exported at the crate root under that name.

## Discovered behavior against the real negative fixtures (disclosed, not assumed)

`import_ocel_json_path` is a plain `serde_json` deserialize into
`Vec<OCELEvent>`/`Vec<OCELObject>` — it performs **no** duplicate-id check, **no**
declared-type check, and **no** referential-integrity check on relationships.
Those checks (or their absence) only appear once the plain `OCEL` struct is
converted into a `SlimLinkedOCEL` via `slim_link_ocel`/`SlimLinkedOCEL::from_ocel`:

| Fixture | Real defect | process_mining 0.6.2's real behavior |
|---|---|---|
| `n13-duplicate-object-id.ocel.json` | `order-1` declared as an object twice | **Silently deduped.** `SlimLinkedOCEL::from_ocel` keeps the first occurrence, and the second `append_object` call returns `SlimAppendError::DuplicateObjectId`, caught and downgraded to a `stderr` warning (`"[rust4pm] warning: skipping object: Duplicate object id: order-1"`) — no error, no panic. Raw struct: `num_objects=2`, `distinct_object_ids=1`. Slim-linked: `num_objects=1`. |
| `n14-undeclared-event-type.ocel.json` | Event `e2` has type `"Teleport Order"`, never declared in `eventTypes` | **Silently auto-declared.** `SlimLinkedOCEL::append_event`'s `ensure_type_idx` creates the missing type on first use with **zero warning at all** — not even a `stderr` line. Both raw and slim-linked report `num_events=2`; `type_stats.event_type_counts` includes `"Teleport Order": 1` as if it had been declared from the start. |
| `n05-o2o-dangling.ocel.json` | Object `order-1` declares an O2O relationship to `item-99`, which is never declared as an object | **Silently dropped**, but only at `finalize()` (after both `SlimLinkedOCEL::from_ocel`'s per-object appends complete): `"[rust4pm] warning: dropping O2O reference to unknown object id \"item-99\""`. Raw struct still counts the relationship (`o2o_relationship_count=1`); the reconstructed `OCEL` (`slim.construct_ocel()`, after `finalize()` has run) shows `o2o_relationship_count=0`. Object/event counts are unaffected either way. |

None of the three real fixtures make process_mining 0.6.2 error, panic, or refuse.
Each produces a different silent partial-fidelity outcome. Nothing here is
guessed — every row was produced by actually running this oracle against the
real file and observing real stdout/stderr (see `../elixir_consumer/test/beam4pm_rf3_ocel_test.exs`
for the exact assertions).

Also checked and disclosed: `wasm4pm/fixtures/real/trace-conform-accepted/expected-ocel.json`
(wasm4pm's own OCEL-1.0-style shape: `ocel_version`/`ocel_global_log`/`ocel_events`/
`ocel_objects`) fails `import_ocel_json_path` cleanly with
`"missing field \`eventTypes\` at line 107 column 1"` — a real, typed, immediate
refusal, confirming it is not usable as an OCEL-2.0-JSON positive fixture. No file
under `wasm4pm/fixtures/` is both genuine positive/lawful data AND OCEL-2.0-JSON
shaped (every `fixtures/negative/*.ocel.json` file is an explicit adversarial
fixture for wasm4pm's own validator, declaring its own `expected_refusal`), so
`../fixtures/positive-self-authored.ocel.json` is a small OCEL 2.0 JSON file
authored by this session for the `:check_positive` scenario — documented as such,
not claimed to be a wasm4pm fixture.

## Wire contract

```text
in:  {"op":"ocel_stats","ocel_path":"<path>"}
out: {"ok":true,
      "num_events":N,"num_objects":N,
      "type_stats":{"event_type_counts":{...},"object_type_counts":{...}},
      "raw":{...plain-OCEL-struct diagnostics, zero dedup/validation applied...},
      "reconstructed":{...post-finalize()/construct_ocel() diagnostics...}}
   | {"ok":false,"error":"ocel_json_import_failed","detail":"<serde/io display>"}

in:  {"op":"ocel_build_slim"}
out: {"ok":true,
      "built":{"num_events":2,"num_objects":2,"type_stats":{...},
               "e2o_relationship_count":3,"o2o_relationship_count":1},
      "reconstructed_ocel":{"num_events":2,"num_objects":2,
                             "e2o_relationship_count":3,"o2o_relationship_count":1},
      "roundtrip":{"num_events":2,"num_objects":2,"type_stats":{...}}}
```

Exit 0 on success, including a *discovered* domain outcome (a structurally
malformed OCEL fixture that still parses, a duplicate id silently dropped, an
undeclared type silently auto-declared) — the JSON on stdout carries the
outcome. Exit nonzero with a `stderr` reason only for a WIRE-level problem this
oracle cannot even attempt to answer: malformed stdin JSON, an unknown `op`, or
an `ocel_path` that does not exist on disk.
