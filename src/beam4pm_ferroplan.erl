%%% beam4pm_ferroplan: thin Erlang facade over the ferroplan PDDL planning
%%% engine -- the ferroplan crate (native/ferroplan submodule) compiled to
%%% wasm32-wasip1 and hosted inside BEAM by Elixir/wasmex
%%% ('Elixir.BeamPM.Ferroplan', lib/beam4pm_ferroplan.ex). Hand-authored
%%% infrastructure, same class as beam4pm_rust4pm.erl and the native
%%% oracle crates; no ggen provenance header.
%%%
%%% Wire contract: every function here delegates 1:1 to the same-named
%%% function on 'Elixir.BeamPM.Ferroplan' and returns its result unchanged
%%% -- {ok, Map} | {error, Reason}, where Map is the JSON-decoded engine
%%% response with binary keys. Session handles are plain integers minted
%%% by the wasm engine; they are process-lifetime and are ALL invalidated
%%% when the Wasmex engine process restarts. No planning computation
%%% happens in Erlang: this module (like the Elixir and Gleam facades) is
%%% a facade over the single ferroplan wasm engine.
%%%
%%% Why there is no beam4pm_ferroplan_tests.erl: same reason as
%%% beam4pm_rust4pm.erl -- eunit runs under rebar3 (root rebar.config),
%%% which compiles src/ WITHOUT Mix dependencies, so wasmex is not on
%%% rebar3's code path. This facade is exercised for real from ExUnit
%%% (test/beam4pm_ferroplan_facades_test.exs), in the Mix context.

-module(beam4pm_ferroplan).

-export([start/0,
         plan/2, plan/3, plan_production/2, plan_production/3,
         readiness/0, version/0, explain/3,
         session_new/2, session_fork/1, session_free/1, session_set_goal/2,
         session_restrict_prefix_claims/3, session_restrict_contains/2,
         session_think/3, session_valid/1, session_step/1, session_suffix/1,
         session_advance/1, session_drop_plan/1, session_has_plan/1,
         session_set_fact/3, session_set_timed_fact/4, session_observe/2,
         session_goal_met/1, session_fact/2, session_apply_start/2,
         session_elapse/2, session_set_fluent/3, session_fluent/2,
         session_plan_valid/3, session_world_bytes/1, session_mind_bytes/1]).

-type result() :: {ok, map()} | {error, term()}.
-type handle() :: non_neg_integer().

%% Start (or find already-started) the named Wasmex engine process.
-spec start() -> {ok, pid()} | {error, term()}.
start() -> 'Elixir.BeamPM.Ferroplan':start().

%% Compatibility solve surface, engine defaults (mode/flags/search).
-spec plan(binary(), binary()) -> result().
plan(Domain, Problem) -> 'Elixir.BeamPM.Ferroplan':plan(Domain, Problem).

%% Explicit extra fields ("mode"/"flags"/"search"), merged into the request.
-spec plan(binary(), binary(), map()) -> result().
plan(Domain, Problem, Extra) -> 'Elixir.BeamPM.Ferroplan':plan(Domain, Problem, Extra).

-spec plan_production(binary(), binary()) -> result().
plan_production(Domain, Problem) ->
    'Elixir.BeamPM.Ferroplan':plan_production(Domain, Problem).

-spec plan_production(binary(), binary(), map()) -> result().
plan_production(Domain, Problem, Extra) ->
    'Elixir.BeamPM.Ferroplan':plan_production(Domain, Problem, Extra).

-spec readiness() -> result().
readiness() -> 'Elixir.BeamPM.Ferroplan':readiness().

-spec version() -> result().
version() -> 'Elixir.BeamPM.Ferroplan':version().

-spec explain(binary(), binary(), map()) -> result().
explain(Domain, Problem, Plan) -> 'Elixir.BeamPM.Ferroplan':explain(Domain, Problem, Plan).

-spec session_new(binary(), binary()) -> result().
session_new(Domain, Problem) -> 'Elixir.BeamPM.Ferroplan':session_new(Domain, Problem).

-spec session_fork(handle()) -> result().
session_fork(Handle) -> 'Elixir.BeamPM.Ferroplan':session_fork(Handle).

-spec session_free(handle()) -> result().
session_free(Handle) -> 'Elixir.BeamPM.Ferroplan':session_free(Handle).

-spec session_set_goal(handle(), binary()) -> result().
session_set_goal(Handle, Goal) ->
    'Elixir.BeamPM.Ferroplan':session_set_goal(Handle, Goal).

-spec session_restrict_prefix_claims(handle(), binary(), binary()) -> result().
session_restrict_prefix_claims(Handle, Prefix, Claimed) ->
    'Elixir.BeamPM.Ferroplan':session_restrict_prefix_claims(Handle, Prefix, Claimed).

-spec session_restrict_contains(handle(), binary()) -> result().
session_restrict_contains(Handle, Filter) ->
    'Elixir.BeamPM.Ferroplan':session_restrict_contains(Handle, Filter).

%% Bounded think: Evals/MemMb budget the search; stashes the resulting
%% plan (if solved) engine-side and resets the cursor.
-spec session_think(handle(), non_neg_integer(), non_neg_integer()) -> result().
session_think(Handle, Evals, MemMb) ->
    'Elixir.BeamPM.Ferroplan':session_think(Handle, Evals, MemMb).

-spec session_valid(handle()) -> result().
session_valid(Handle) -> 'Elixir.BeamPM.Ferroplan':'session_valid?'(Handle).

-spec session_step(handle()) -> result().
session_step(Handle) -> 'Elixir.BeamPM.Ferroplan':session_step(Handle).

-spec session_suffix(handle()) -> result().
session_suffix(Handle) -> 'Elixir.BeamPM.Ferroplan':session_suffix(Handle).

-spec session_advance(handle()) -> result().
session_advance(Handle) -> 'Elixir.BeamPM.Ferroplan':session_advance(Handle).

-spec session_drop_plan(handle()) -> result().
session_drop_plan(Handle) -> 'Elixir.BeamPM.Ferroplan':session_drop_plan(Handle).

-spec session_has_plan(handle()) -> result().
session_has_plan(Handle) -> 'Elixir.BeamPM.Ferroplan':'session_has_plan?'(Handle).

-spec session_set_fact(handle(), binary(), boolean()) -> result().
session_set_fact(Handle, Name, Value) ->
    'Elixir.BeamPM.Ferroplan':session_set_fact(Handle, Name, Value).

-spec session_set_timed_fact(handle(), number(), binary(), boolean()) -> result().
session_set_timed_fact(Handle, Dt, Name, Value) ->
    'Elixir.BeamPM.Ferroplan':session_set_timed_fact(Handle, Dt, Name, Value).

%% Sight: a list of {Name, Value} 2-tuples (fact name, boolean).
-spec session_observe(handle(), [{binary(), boolean()}]) -> result().
session_observe(Handle, Sight) -> 'Elixir.BeamPM.Ferroplan':session_observe(Handle, Sight).

-spec session_goal_met(handle()) -> result().
session_goal_met(Handle) -> 'Elixir.BeamPM.Ferroplan':'session_goal_met?'(Handle).

-spec session_fact(handle(), binary()) -> result().
session_fact(Handle, Name) -> 'Elixir.BeamPM.Ferroplan':session_fact(Handle, Name).

-spec session_apply_start(handle(), binary()) -> result().
session_apply_start(Handle, Name) ->
    'Elixir.BeamPM.Ferroplan':session_apply_start(Handle, Name).

-spec session_elapse(handle(), number()) -> result().
session_elapse(Handle, Dt) -> 'Elixir.BeamPM.Ferroplan':session_elapse(Handle, Dt).

-spec session_set_fluent(handle(), binary(), number()) -> result().
session_set_fluent(Handle, Name, Value) ->
    'Elixir.BeamPM.Ferroplan':session_set_fluent(Handle, Name, Value).

-spec session_fluent(handle(), binary()) -> result().
session_fluent(Handle, Name) -> 'Elixir.BeamPM.Ferroplan':session_fluent(Handle, Name).

-spec session_plan_valid(handle(), map(), non_neg_integer()) -> result().
session_plan_valid(Handle, Plan, From) ->
    'Elixir.BeamPM.Ferroplan':'session_plan_valid?'(Handle, Plan, From).

-spec session_world_bytes(handle()) -> result().
session_world_bytes(Handle) -> 'Elixir.BeamPM.Ferroplan':session_world_bytes(Handle).

-spec session_mind_bytes(handle()) -> result().
session_mind_bytes(Handle) -> 'Elixir.BeamPM.Ferroplan':session_mind_bytes(Handle).
