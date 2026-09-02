//// Facade over the petgraph graph-algorithms wasm engine hosted by
//// Elixir/wasmex -- a third engine alongside `beam4pm/rust4pm.gleam`'s
//// process-mining facade and `beam4pm/ferroplan.gleam`'s PDDL planning
//// facade.
////
//// Hand-authored infrastructure (not ggen output): every function here is an
//// `@external` delegation to `Elixir.BeamPM.Petgraph`
//// (lib/beam4pm_petgraph.ex), which drives the single wasm32-wasip1
//// petgraph engine (native/petgraph-wasm submodule). No graph-algorithm
//// computation happens in Gleam -- this module is a typed facade over the
//// one engine, same directive as beam4pm/rust4pm.gleam and
//// beam4pm/ferroplan.gleam.
////
//// Compile-checked by `gleam build` (externals are not resolved at compile
//// time); runtime-tested ONLY from the mix context, because `gleam
//// test`/gleeunit runs without wasmex on its path. Documented, not faked.
////
//// Runtime contract (inherited verbatim from BeamPM.Petgraph):
////   - Elixir's `{:ok, map} | {:error, reason}` tuples ARE Gleam's `Result`
////     runtime representation, so every call types as
////     `Result(Dynamic, Dynamic)`: Ok carries a binary-keyed map decoded
////     from the engine's JSON response; Error carries
////     `{:engine, msg}` / `{:wasmex, term}` tagged tuples.
////   - `start()` must have been called (or the engine supervised) in the
////     hosting BEAM before any other function; a restart produces a fresh
////     wasm store, so ALL previously returned graph handles are invalid.
////   - `add_edge/4` in Elixir takes an `opts` keyword list as its fourth,
////     optional-arity argument (`weight` defaults to `1.0` if omitted from
////     opts) -- there is no clean positional-weight arity to bind from
////     Gleam (Gleam has no keyword-list literal that maps onto Elixir
////     `Keyword.t()`), so `add_edge/3` here binds Elixir's arity-3,
////     no-opts head (default weight `1.0`) only; there is no
////     `add_edge_weighted` variant.

import gleam/dynamic.{type Dynamic}

/// Start (or find already started) the named singleton wasmex engine
/// hosting petgraph_wasm.wasm. Idempotent; `Ok` carries the engine pid.
@external(erlang, "Elixir.BeamPM.Petgraph", "start")
pub fn start() -> Result(Dynamic, Dynamic)

/// A new, empty directed graph. `Ok` carries `{"handle": n}`.
@external(erlang, "Elixir.BeamPM.Petgraph", "graph_new")
pub fn graph_new() -> Result(Dynamic, Dynamic)

/// Add a node by name to the graph. Idempotent.
@external(erlang, "Elixir.BeamPM.Petgraph", "add_node")
pub fn add_node(handle: Int, name: String) -> Result(Dynamic, Dynamic)

/// Add a directed edge `from` -> `to`, auto-adding either endpoint as a
/// node if absent. Binds Elixir's arity-3, no-opts head -- edge weight
/// defaults to `1.0` (see moduledoc: there is no clean positional-weight
/// arity to bind from Gleam).
@external(erlang, "Elixir.BeamPM.Petgraph", "add_edge")
pub fn add_edge(handle: Int, from: String, to: String) -> Result(Dynamic, Dynamic)

/// Real A*-as-Dijkstra shortest path. `Ok` carries
/// `{"path": [names] | null, "cost": float | null}` -- unreachable or an
/// unknown name is a real `null` answer, never an error.
@external(erlang, "Elixir.BeamPM.Petgraph", "shortest_path")
pub fn shortest_path(
  handle: Int,
  from: String,
  to: String,
) -> Result(Dynamic, Dynamic)

/// Tarjan strongly-connected-components, deterministically sorted.
@external(erlang, "Elixir.BeamPM.Petgraph", "scc")
pub fn scc(handle: Int) -> Result(Dynamic, Dynamic)

/// Topological sort. `Ok` carries `{"acyclic": bool, "order": [names] |
/// null}` -- a cycle is a real, named answer, never an error.
@external(erlang, "Elixir.BeamPM.Petgraph", "toposort")
pub fn toposort(handle: Int) -> Result(Dynamic, Dynamic)

/// `Ok` carries `{"cyclic": bool}`.
@external(erlang, "Elixir.BeamPM.Petgraph", "is_cyclic?")
pub fn is_cyclic(handle: Int) -> Result(Dynamic, Dynamic)

/// Node count of the graph.
@external(erlang, "Elixir.BeamPM.Petgraph", "node_count")
pub fn node_count(handle: Int) -> Result(Dynamic, Dynamic)

/// Edge count of the graph.
@external(erlang, "Elixir.BeamPM.Petgraph", "edge_count")
pub fn edge_count(handle: Int) -> Result(Dynamic, Dynamic)

/// Release a graph handle. Subsequent use errors with an unknown-handle
/// message.
@external(erlang, "Elixir.BeamPM.Petgraph", "free_graph")
pub fn free_graph(handle: Int) -> Result(Dynamic, Dynamic)
