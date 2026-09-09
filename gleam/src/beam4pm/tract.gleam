//// Facade over the sonos/tract ONNX inference wasm engine hosted by
//// Elixir/wasmex -- a fourth engine alongside `beam4pm/rust4pm.gleam`
//// (process mining), `beam4pm/ferroplan.gleam` (PDDL planning), and
//// `beam4pm/petgraph.gleam` (graph algorithms).
////
//// Hand-authored infrastructure (not ggen output): every function here is an
//// `@external` delegation to `Elixir.BeamPM.Tract` (lib/beam4pm_tract.ex),
//// which drives the single wasm32-wasip1 tract-wasm engine
//// (native/tract-wasm submodule). No inference math happens in Gleam --
//// this module is a typed facade over the one engine, same directive as
//// beam4pm/rust4pm.gleam and beam4pm/ferroplan.gleam.
////
//// Compile-checked by `gleam build` (externals are not resolved at compile
//// time); runtime-tested ONLY from the mix context, because `gleam
//// test`/gleeunit runs without wasmex on its path. Documented, not faked.
////
//// Runtime contract (inherited verbatim from BeamPM.Tract):
////   - Elixir's `{:ok, map} | {:error, reason}` tuples ARE Gleam's `Result`
////     runtime representation, so every call types as
////     `Result(Dynamic, Dynamic)`: Ok carries a binary-keyed map decoded
////     from the engine's JSON response; Error carries
////     `{:engine, msg}` / `{:wasmex, term}` tagged tuples.
////   - `start()` must have been called (or the engine supervised) in the
////     hosting BEAM before any other function; a restart produces a fresh
////     wasm store, so ALL previously returned model handles are invalid.
////   - Ops with optional trailing args in Elixir (an `opts` keyword list,
////     currently only `:timeout`) are bound here at their minimal-arity
////     default-arg heads -- load_model/2, load_model_path/2, run/3,
////     model_info/2, free_model/2.
////   - `load_model/2` takes a Gleam `BitArray` for the raw ONNX protobuf
////     bytes; Gleam `BitArray` marshals to an Elixir binary across the
////     `@external(erlang, ...)` boundary the same way every other binary
////     parameter does elsewhere in this facade family (see
////     `beam4pm/rust4pm.gleam`), so no extra encoding is needed here --
////     `BeamPM.Tract.load_model/2` base64-encodes it host-side before it
////     ever reaches the wasm module.
////   - `run/3`'s `inputs` stays `Dynamic` here rather than a typed list:
////     the wire shape is a list of `%{shape: [dims], data: [floats]}`
////     maps, which Gleam's type system can't cleanly express without a
////     bespoke record type mirrored on both sides of the boundary. This
////     facade doesn't invent one -- callers build the `Dynamic` shape (or
////     drop to Elixir) themselves, the same honesty-over-invention
////     convention as the rest of the facade family.

import gleam/dynamic.{type Dynamic}

/// Start (or find already started) the named singleton wasmex engine
/// hosting tract_wasm.wasm. Idempotent; `Ok` carries the engine pid.
@external(erlang, "Elixir.BeamPM.Tract", "start")
pub fn start() -> Result(Dynamic, Dynamic)

/// Load and compile an ONNX model from raw protobuf bytes (engine
/// defaults -- the arity-2 Elixir head). `Ok` carries `{"handle": n,
/// "inputs": [...], "outputs": [...]}`.
@external(erlang, "Elixir.BeamPM.Tract", "load_model")
pub fn load_model(model_bytes: BitArray) -> Result(Dynamic, Dynamic)

/// `File.read!/1` host-side, then `load_model/2` (engine defaults --
/// the arity-2 Elixir head; raises if the path is absent).
@external(erlang, "Elixir.BeamPM.Tract", "load_model_path")
pub fn load_model_path(path: String) -> Result(Dynamic, Dynamic)

/// Run inference against a loaded model (engine defaults -- the arity-3
/// Elixir head). `inputs` is a list of `%{shape: [dims], data: [floats]}`
/// maps, one per declared model input, in order -- see the module doc
/// comment for why this stays `Dynamic`. `Ok` carries `{"outputs":
/// [{"shape": [dims], "data": [floats]}]}`, one per declared model
/// output, in order.
@external(erlang, "Elixir.BeamPM.Tract", "run")
pub fn run(handle: Int, inputs: Dynamic) -> Result(Dynamic, Dynamic)

/// Same input/output fact shape as `load_model/2` (engine defaults --
/// the arity-2 Elixir head).
@external(erlang, "Elixir.BeamPM.Tract", "model_info")
pub fn model_info(handle: Int) -> Result(Dynamic, Dynamic)

/// Free a model handle (engine defaults -- the arity-2 Elixir head).
@external(erlang, "Elixir.BeamPM.Tract", "free_model")
pub fn free_model(handle: Int) -> Result(Dynamic, Dynamic)
