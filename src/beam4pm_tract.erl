%%% beam4pm_tract: thin Erlang facade over the tract ONNX inference engine
%%% -- the sonos/tract crate (native/tract-wasm) compiled to wasm32-wasip1
%%% and hosted inside BEAM by Elixir/wasmex ('Elixir.BeamPM.Tract',
%%% lib/beam4pm_tract.ex). Hand-authored infrastructure, same class as
%%% beam4pm_rust4pm.erl, beam4pm_ferroplan.erl, and the native oracle
%%% crates; no ggen provenance header.
%%%
%%% Wire contract: every function here delegates 1:1 to the same-named
%%% function on 'Elixir.BeamPM.Tract' and returns its result unchanged --
%%% {ok, Map} | {error, Reason}, where Map is the JSON-decoded engine
%%% response with binary keys. Model handles are plain integers minted by
%%% the wasm engine; they are process-lifetime and are ALL invalidated
%%% when the Wasmex engine process restarts. No inference computation
%%% happens in Erlang: this module (like the Elixir facade) is a facade
%%% over the single tract wasm engine.
%%%
%%% load_model/1 and run/2 bind Elixir's load_model/2 and run/3 at their
%%% default-opts arity (no `timeout` override from Erlang callers).
%%%
%%% Why there is no beam4pm_tract_tests.erl: same reason as
%%% beam4pm_rust4pm.erl -- eunit runs under rebar3 (root rebar.config),
%%% which compiles src/ WITHOUT Mix dependencies, so wasmex is not on
%%% rebar3's code path. This facade is exercised for real from ExUnit,
%%% in the Mix context.

-module(beam4pm_tract).

-export([start/0,
         load_model/1, load_model_path/1,
         run/2,
         model_info/1, free_model/1]).

-type result() :: {ok, map()} | {error, term()}.
-type handle() :: non_neg_integer().
-type tensor() :: #{shape := [non_neg_integer()], data := [number()]}.

%% Start (or find already-started) the named Wasmex engine process.
-spec start() -> {ok, pid()} | {error, term()}.
start() -> 'Elixir.BeamPM.Tract':start().

%% Raw ONNX protobuf bytes; base64-encoded and framed by the Elixir side.
-spec load_model(binary()) -> result().
load_model(ModelBytes) -> 'Elixir.BeamPM.Tract':load_model(ModelBytes, []).

%% Reads the file host-side, then load_model/1 (raises if the path is absent).
-spec load_model_path(binary()) -> result().
load_model_path(Path) -> 'Elixir.BeamPM.Tract':load_model_path(Path, []).

%% One f32 tensor per declared model input, in order.
-spec run(handle(), [tensor()]) -> result().
run(Handle, Inputs) -> 'Elixir.BeamPM.Tract':run(Handle, Inputs, []).

-spec model_info(handle()) -> result().
model_info(Handle) -> 'Elixir.BeamPM.Tract':model_info(Handle, []).

-spec free_model(handle()) -> result().
free_model(Handle) -> 'Elixir.BeamPM.Tract':free_model(Handle, []).
