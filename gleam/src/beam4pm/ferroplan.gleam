//// Facade over the ferroplan PDDL planning wasm engine hosted by
//// Elixir/wasmex -- a second engine alongside `beam4pm/rust4pm.gleam`'s
//// process-mining facade.
////
//// Hand-authored infrastructure (not ggen output): every function here is an
//// `@external` delegation to `Elixir.BeamPM.Ferroplan`
//// (lib/beam4pm_ferroplan.ex), which drives the single wasm32-wasip1
//// ferroplan engine (native/ferroplan submodule). No planning computation
//// happens in Gleam -- this module is a typed facade over the one engine,
//// same directive as beam4pm/rust4pm.gleam.
////
//// Compile-checked by `gleam build` (externals are not resolved at compile
//// time); runtime-tested ONLY from the mix context
//// (test/beam4pm_ferroplan_facades_test.exs appends gleam/build/dev/erlang/
//// beam4pm/ebin to the code path), because `gleam test`/gleeunit runs
//// without wasmex on its path. Documented, not faked.
////
//// Runtime contract (inherited verbatim from BeamPM.Ferroplan):
////   - Elixir's `{:ok, map} | {:error, reason}` tuples ARE Gleam's `Result`
////     runtime representation, so every call types as
////     `Result(Dynamic, Dynamic)`: Ok carries a binary-keyed map decoded
////     from the engine's JSON response; Error carries
////     `{:engine, msg}` / `{:wasmex, term}` tagged tuples.
////   - `start()` must have been called (or the engine supervised) in the
////     hosting BEAM before any other function; a restart produces a fresh
////     wasm store, so ALL previously returned session handles are invalid.
////   - Ops with optional trailing args in Elixir (extra fields map, opts)
////     are bound here at their minimal-arity default-arg heads --
////     plan/2, plan_production/2, session_new/2, session_think/3, etc.

import gleam/dynamic.{type Dynamic}

/// Start (or find already started) the named singleton wasmex engine
/// hosting ferroplan_wasm.wasm. Idempotent; `Ok` carries the engine pid.
@external(erlang, "Elixir.BeamPM.Ferroplan", "start")
pub fn start() -> Result(Dynamic, Dynamic)

/// Compatibility solve surface (engine defaults for mode/flags/search --
/// the arity-2 Elixir head). `Ok` carries the decoded Solution map.
@external(erlang, "Elixir.BeamPM.Ferroplan", "plan")
pub fn plan(domain: String, problem: String) -> Result(Dynamic, Dynamic)

/// Bounded production solve (engine defaults -- the arity-2 Elixir head).
/// `Ok` carries a versioned, always candidate-only OperationEnvelope map
/// (its own "outcome" field distinguishes solved/refused/capped, never a
/// bare {:error, _} for a strict-mode refusal).
@external(erlang, "Elixir.BeamPM.Ferroplan", "plan_production")
pub fn plan_production(domain: String, problem: String) -> Result(Dynamic, Dynamic)

/// Canonical capability contract and deterministic manifest fingerprint.
@external(erlang, "Elixir.BeamPM.Ferroplan", "readiness")
pub fn readiness() -> Result(Dynamic, Dynamic)

/// The crate's own semver, as `{"version": "..."}`.
@external(erlang, "Elixir.BeamPM.Ferroplan", "version")
pub fn version() -> Result(Dynamic, Dynamic)

/// Explain a plan (a decoded Plan map, not a JSON string) for its
/// domain + problem.
@external(erlang, "Elixir.BeamPM.Ferroplan", "explain")
pub fn explain(
  domain: String,
  problem: String,
  plan: Dynamic,
) -> Result(Dynamic, Dynamic)

/// Ground a new planning session. `Ok` carries `"handle"`: an engine
/// session handle.
@external(erlang, "Elixir.BeamPM.Ferroplan", "session_new")
pub fn session_new(domain: String, problem: String) -> Result(Dynamic, Dynamic)

/// A cheap fork sharing the grounded world but with independent mutable
/// state (fresh plan/cursor). `Ok` carries the new session's `"handle"`.
@external(erlang, "Elixir.BeamPM.Ferroplan", "session_fork")
pub fn session_fork(handle: Int) -> Result(Dynamic, Dynamic)

/// Release a session handle. Subsequent use errors with "unknown session
/// handle N".
@external(erlang, "Elixir.BeamPM.Ferroplan", "session_free")
pub fn session_free(handle: Int) -> Result(Dynamic, Dynamic)

/// Set the session's goal.
@external(erlang, "Elixir.BeamPM.Ferroplan", "session_set_goal")
pub fn session_set_goal(handle: Int, goal: String) -> Result(Dynamic, Dynamic)

/// Bounded think: `evals`/`mem_mb` budget the search; stashes the
/// resulting plan (if solved) engine-side and resets the cursor. `Ok`
/// carries the decoded Solution map.
@external(erlang, "Elixir.BeamPM.Ferroplan", "session_think")
pub fn session_think(
  handle: Int,
  evals: Int,
  mem_mb: Int,
) -> Result(Dynamic, Dynamic)

/// Free replay check of the stashed plan's suffix from the current
/// cursor -- no search spent. `Ok` carries `{"valid": bool}`.
@external(erlang, "Elixir.BeamPM.Ferroplan", "session_valid?")
pub fn session_valid(handle: Int) -> Result(Dynamic, Dynamic)

/// The plan step under the cursor right now, or `null`.
@external(erlang, "Elixir.BeamPM.Ferroplan", "session_step")
pub fn session_step(handle: Int) -> Result(Dynamic, Dynamic)

/// Whatever remains of the stashed plan from the cursor onward.
@external(erlang, "Elixir.BeamPM.Ferroplan", "session_suffix")
pub fn session_suffix(handle: Int) -> Result(Dynamic, Dynamic)

/// Advance the cursor by one step.
@external(erlang, "Elixir.BeamPM.Ferroplan", "session_advance")
pub fn session_advance(handle: Int) -> Result(Dynamic, Dynamic)

/// Clear the stashed plan and reset the cursor.
@external(erlang, "Elixir.BeamPM.Ferroplan", "session_drop_plan")
pub fn session_drop_plan(handle: Int) -> Result(Dynamic, Dynamic)

/// `Ok` carries `{"has_plan": bool}`.
@external(erlang, "Elixir.BeamPM.Ferroplan", "session_has_plan?")
pub fn session_has_plan(handle: Int) -> Result(Dynamic, Dynamic)

/// Set a boolean fact in the session's world.
@external(erlang, "Elixir.BeamPM.Ferroplan", "session_set_fact")
pub fn session_set_fact(
  handle: Int,
  name: String,
  value: Bool,
) -> Result(Dynamic, Dynamic)

/// Set a fact scheduled at time offset `dt`.
@external(erlang, "Elixir.BeamPM.Ferroplan", "session_set_timed_fact")
pub fn session_set_timed_fact(
  handle: Int,
  dt: Float,
  name: String,
  value: Bool,
) -> Result(Dynamic, Dynamic)

/// Apply a batch of observed (fact, value) pairs; returns the resulting
/// news/deltas as a Dynamic list.
@external(erlang, "Elixir.BeamPM.Ferroplan", "session_observe")
pub fn session_observe(
  handle: Int,
  sight: List(#(String, Bool)),
) -> Result(Dynamic, Dynamic)

/// `Ok` carries `{"goal_met": bool}`.
@external(erlang, "Elixir.BeamPM.Ferroplan", "session_goal_met?")
pub fn session_goal_met(handle: Int) -> Result(Dynamic, Dynamic)

/// Current belief for a fact name. `Ok` carries `{"value": bool | null}`.
@external(erlang, "Elixir.BeamPM.Ferroplan", "session_fact")
pub fn session_fact(handle: Int, name: String) -> Result(Dynamic, Dynamic)

/// Apply the start of a (possibly durative) action by name.
@external(erlang, "Elixir.BeamPM.Ferroplan", "session_apply_start")
pub fn session_apply_start(handle: Int, name: String) -> Result(Dynamic, Dynamic)

/// Advance simulated time by `dt`; returns the set of effects/events
/// that fired.
@external(erlang, "Elixir.BeamPM.Ferroplan", "session_elapse")
pub fn session_elapse(handle: Int, dt: Float) -> Result(Dynamic, Dynamic)

/// Set a numeric fluent's value.
@external(erlang, "Elixir.BeamPM.Ferroplan", "session_set_fluent")
pub fn session_set_fluent(
  handle: Int,
  name: String,
  value: Float,
) -> Result(Dynamic, Dynamic)

/// Current value of a numeric fluent. `Ok` carries `{"value": float | null}`.
@external(erlang, "Elixir.BeamPM.Ferroplan", "session_fluent")
pub fn session_fluent(handle: Int, name: String) -> Result(Dynamic, Dynamic)

/// Check an externally-supplied plan is still valid from step index
/// `from`, without mutating session state.
@external(erlang, "Elixir.BeamPM.Ferroplan", "session_plan_valid?")
pub fn session_plan_valid(
  handle: Int,
  plan: Dynamic,
  from: Int,
) -> Result(Dynamic, Dynamic)

/// Byte size of the shared/grounded world state.
@external(erlang, "Elixir.BeamPM.Ferroplan", "session_world_bytes")
pub fn session_world_bytes(handle: Int) -> Result(Dynamic, Dynamic)

/// Byte size of this session's private mutable state.
@external(erlang, "Elixir.BeamPM.Ferroplan", "session_mind_bytes")
pub fn session_mind_bytes(handle: Int) -> Result(Dynamic, Dynamic)
