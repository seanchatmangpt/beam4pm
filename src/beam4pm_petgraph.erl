%%% beam4pm_petgraph: thin Erlang facade over the petgraph graph-algorithms
%%% engine -- the petgraph crate (native/petgraph-wasm) compiled to
%%% wasm32-wasip1 and hosted inside BEAM by Elixir/wasmex
%%% ('Elixir.BeamPM.Petgraph', lib/beam4pm_petgraph.ex). Hand-authored
%%% infrastructure, same class as beam4pm_rust4pm.erl and beam4pm_ferroplan.erl;
%%% no ggen provenance header.
%%%
%%% Wire contract: every function here delegates 1:1 to the same-named
%%% function on 'Elixir.BeamPM.Petgraph' and returns its result unchanged
%%% -- {ok, Map} | {error, Reason}, where Map is the JSON-decoded engine
%%% response with binary keys. Graph handles are plain integers minted by
%%% the wasm engine; they are process-lifetime and are ALL invalidated
%%% when the Wasmex engine process restarts. No graph computation happens
%%% in Erlang: this module (like the Elixir facade) is a facade over the
%%% single petgraph wasm engine.
%%%
%%% add_edge/3 delegates to 'Elixir.BeamPM.Petgraph':add_edge/3 (default
%%% weight 1.0, per that function's own opts default). add_edge/4 takes an
%%% explicit Weight and builds the [{weight, Weight}] opts keyword list
%%% itself, since Erlang has no keyword-list default-argument sugar.
%%%
%%% Why there is no beam4pm_petgraph_tests.erl: same reason as
%%% beam4pm_ferroplan.erl -- eunit runs under rebar3 (root rebar.config),
%%% which compiles src/ WITHOUT Mix dependencies, so wasmex is not on
%%% rebar3's code path. This facade is exercised for real from ExUnit, in
%%% the Mix context.

-module(beam4pm_petgraph).

-export([start/0,
         graph_new/0,
         add_node/2,
         add_edge/3, add_edge/4,
         shortest_path/3,
         scc/1,
         toposort/1,
         is_cyclic/1,
         node_count/1,
         edge_count/1,
         free_graph/1]).

-type result() :: {ok, map()} | {error, term()}.
-type handle() :: non_neg_integer().

%% Start (or find already-started) the named Wasmex engine process.
-spec start() -> {ok, pid()} | {error, term()}.
start() -> 'Elixir.BeamPM.Petgraph':start().

%% A new, empty directed graph.
-spec graph_new() -> result().
graph_new() -> 'Elixir.BeamPM.Petgraph':graph_new().

-spec add_node(handle(), binary()) -> result().
add_node(Handle, Name) -> 'Elixir.BeamPM.Petgraph':add_node(Handle, Name).

%% Weight defaults to 1.0 (the Elixir side's own opts default).
-spec add_edge(handle(), binary(), binary()) -> result().
add_edge(Handle, From, To) -> 'Elixir.BeamPM.Petgraph':add_edge(Handle, From, To).

%% Explicit weight, since Erlang has no keyword-list default arguments.
-spec add_edge(handle(), binary(), binary(), number()) -> result().
add_edge(Handle, From, To, Weight) ->
    'Elixir.BeamPM.Petgraph':add_edge(Handle, From, To, [{weight, Weight}]).

-spec shortest_path(handle(), binary(), binary()) -> result().
shortest_path(Handle, From, To) ->
    'Elixir.BeamPM.Petgraph':shortest_path(Handle, From, To).

%% Tarjan strongly-connected-components, deterministically sorted.
-spec scc(handle()) -> result().
scc(Handle) -> 'Elixir.BeamPM.Petgraph':scc(Handle).

%% A cycle is a real, named answer ({"acyclic" => false, "order" => nil}),
%% never an error.
-spec toposort(handle()) -> result().
toposort(Handle) -> 'Elixir.BeamPM.Petgraph':toposort(Handle).

-spec is_cyclic(handle()) -> result().
is_cyclic(Handle) -> 'Elixir.BeamPM.Petgraph':'is_cyclic?'(Handle).

-spec node_count(handle()) -> result().
node_count(Handle) -> 'Elixir.BeamPM.Petgraph':node_count(Handle).

-spec edge_count(handle()) -> result().
edge_count(Handle) -> 'Elixir.BeamPM.Petgraph':edge_count(Handle).

-spec free_graph(handle()) -> result().
free_graph(Handle) -> 'Elixir.BeamPM.Petgraph':free_graph(Handle).
