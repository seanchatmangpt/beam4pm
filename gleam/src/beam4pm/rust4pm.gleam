//// Facade over the one rust4pm wasm engine hosted by Elixir/wasmex.
////
//// Hand-authored infrastructure (not ggen output): every function here is an
//// `@external` delegation to `Elixir.BeamPM.Rust4PM` (lib/beam4pm_rust4pm.ex),
//// which drives the single wasm32-wasip1 process_mining =0.6.2 engine. No
//// process-mining computation happens in Gleam -- this module is a typed
//// facade over the one engine, per the beam4pm directive.
////
//// Compile-checked by `gleam build` (externals are not resolved at compile
//// time); runtime-tested ONLY from the mix context
//// (test/beam4pm_rust4pm_facades_test.exs appends gleam/build/dev/erlang/
//// beam4pm/ebin to the code path), because `gleam test`/gleeunit runs
//// without wasmex on its path. Documented, not faked.
////
//// Runtime contract (inherited verbatim from BeamPM.Rust4PM):
////   - Elixir's `{:ok, map} | {:error, reason}` tuples ARE Gleam's `Result`
////     runtime representation, so every call types as
////     `Result(Dynamic, Dynamic)`: Ok carries a binary-keyed map decoded
////     from the engine's JSON response; Error carries
////     `{:engine, msg}` / `{:wasmex, term}` tagged tuples.
////   - `start()` must have been called (or the engine supervised) in the
////     hosting BEAM before any other function; a restart produces a fresh
////     wasm store, so ALL previously returned log/net handles are invalid
////     and callers must re-import.
////   - Ops with optional trailing args in Elixir (config/options/timeout)
////     are bound here at their default-arg arities: discover_alphappp/1
////     (AlphaPPPConfig default), align_variants/2 and compute_fitness/2 and
////     align_trace/2 (AlignmentOptions default, max_states 5_000_000).
////     pm4py's discounted-A* exponent is UNSUPPORTED by the engine and its
////     Elixir-side option key is rejected, never faked -- see
////     docs/reference/rust4pm-wasm-beam.md.

import gleam/dynamic.{type Dynamic}

/// Start (or find already started) the named singleton wasmex engine
/// hosting rust4pm_wasm.wasm. Idempotent; `Ok` carries the engine pid.
@external(erlang, "Elixir.BeamPM.Rust4PM", "start")
pub fn start() -> Result(Dynamic, Dynamic)

/// Import an entire XES document (UTF-8 content, by value -- no filesystem
/// access inside wasm). `Ok` map carries `"handle"`: an engine log handle.
@external(erlang, "Elixir.BeamPM.Rust4PM", "import_xes")
pub fn import_xes(content: String) -> Result(Dynamic, Dynamic)

/// Case/variant/activity statistics for an imported log handle: num_cases,
/// num_variants, num_activities, lexicographically sorted activities,
/// top_variant and top_variant_count.
@external(erlang, "Elixir.BeamPM.Rust4PM", "log_stats")
pub fn log_stats(handle: Int) -> Result(Dynamic, Dynamic)

/// Top `n` variants by descending frequency (crate order), each with
/// activities, count and percentage (0-100).
@external(erlang, "Elixir.BeamPM.Rust4PM", "top_n_variants")
pub fn top_n_variants(handle: Int, n: Int) -> Result(Dynamic, Dynamic)

/// Directly-follows graph of a log handle: edges sorted by (source, target),
/// byte-comparable with the rf1-dfg-oracle wire.
@external(erlang, "Elixir.BeamPM.Rust4PM", "discover_dfg")
pub fn discover_dfg(handle: Int) -> Result(Dynamic, Dynamic)

/// Alpha+++ Petri-net discovery over a log handle with AlphaPPPConfig
/// defaults (the arity-1 Elixir head). `Ok` carries `"net_handle"` plus a
/// structural summary; the discovered net always has initial/final markings.
@external(erlang, "Elixir.BeamPM.Rust4PM", "discover_alphappp")
pub fn discover_alphappp(handle: Int) -> Result(Dynamic, Dynamic)

/// Import an entire PNML document (UTF-8 content, by value). `Ok` carries
/// `"net_handle"` plus the same structural summary as discover_alphappp;
/// nets without markings import but fail alignment ops honestly.
@external(erlang, "Elixir.BeamPM.Rust4PM", "import_pnml")
pub fn import_pnml(content: String) -> Result(Dynamic, Dynamic)

/// Align every log variant against a net (default AlignmentOptions,
/// max_states 5_000_000 -- the arity-2 Elixir head). Per-variant results in
/// descending-frequency order; pm4py-style [log_side, model_side] moves.
@external(erlang, "Elixir.BeamPM.Rust4PM", "align_variants")
pub fn align_variants(
  log_handle: Int,
  net_handle: Int,
) -> Result(Dynamic, Dynamic)

/// Align a single explicit activity-name trace against a net (default
/// AlignmentOptions -- the arity-2 Elixir head). This is the port surface
/// for pm4py's alignment example, with standard optimal alignments only.
@external(erlang, "Elixir.BeamPM.Rust4PM", "align_trace")
pub fn align_trace(
  net_handle: Int,
  trace: List(String),
) -> Result(Dynamic, Dynamic)

/// Fitness aggregates (log_fitness, average_fitness, perfectly_fitting_frac,
/// total_costs, num_variants_aligned) for a log against a net (default
/// AlignmentOptions -- the arity-2 Elixir head). Field names match the
/// rf2-conformance-oracle wire for differential comparison.
@external(erlang, "Elixir.BeamPM.Rust4PM", "compute_fitness")
pub fn compute_fitness(
  log_handle: Int,
  net_handle: Int,
) -> Result(Dynamic, Dynamic)

/// pm4py activities_to_alphabet port: activities ranked by descending total
/// event count (ties pinned to first occurrence in the log), mapped to
/// bijective base-26 letters A..Z, AA, AB, ...
@external(erlang, "Elixir.BeamPM.Rust4PM", "activities_to_alphabet")
pub fn activities_to_alphabet(handle: Int) -> Result(Dynamic, Dynamic)

/// pm4py get_activity_position_summary port: histogram of the activity's
/// 0-based within-trace indexes as ascending [index, count] pairs plus a
/// total; an unknown activity yields an empty histogram, not an error.
@external(erlang, "Elixir.BeamPM.Rust4PM", "activity_position")
pub fn activity_position(
  handle: Int,
  activity: String,
) -> Result(Dynamic, Dynamic)

/// Drop an imported log from the engine's handle map. Subsequent use of the
/// handle errors with "unknown log handle N".
@external(erlang, "Elixir.BeamPM.Rust4PM", "free_log")
pub fn free_log(handle: Int) -> Result(Dynamic, Dynamic)

/// Drop a discovered/imported net from the engine's handle map. Subsequent
/// use of the handle errors with "unknown net handle N".
@external(erlang, "Elixir.BeamPM.Rust4PM", "free_net")
pub fn free_net(handle: Int) -> Result(Dynamic, Dynamic)
