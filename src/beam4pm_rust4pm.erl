%%% beam4pm_rust4pm: thin Erlang facade over the ONE process-mining engine --
%%% the rust4pm (process_mining =0.6.2) crate compiled to wasm32-wasip1 and
%%% hosted inside BEAM by Elixir/wasmex ('Elixir.BeamPM.Rust4PM',
%%% lib/beam4pm_rust4pm.ex). Hand-authored infrastructure, like the
%%% native/rf1-rf4 oracle crates; no ggen provenance header.
%%%
%%% Wire contract: every function here delegates 1:1 to the same-named
%%% function on 'Elixir.BeamPM.Rust4PM' and returns its result unchanged --
%%% {ok, Map} | {error, Reason}, where Map is the JSON-decoded engine
%%% response with binary keys (Elixir stdlib JSON decoding). Handles are
%%% plain integers minted by the wasm engine; they are process-lifetime and
%%% are ALL invalidated when the Wasmex engine process restarts (callers
%%% must re-import). The /2 and /3 arities of discover_alphappp,
%%% align_variants, align_trace and compute_fitness bind the Elixir
%%% default-argument heads (config/options = nil means "engine defaults").
%%% No process-mining computation happens in Erlang: this module (like the
%%% Elixir and Gleam facades) is a facade over the single wasm engine.
%%%
%%% Why there is no beam4pm_rust4pm_tests.erl: eunit in this repo runs under
%%% rebar3 (root rebar.config), which compiles src/ without Mix dependencies
%%% -- wasmex is a hex dep of the Mix project only, so it is not on rebar3's
%%% code path and any eunit test of this module could not start the engine.
%%% Instead this facade is exercised for real from ExUnit
%%% (test/beam4pm_rust4pm_facades_test.exs), which runs in the Mix context
%%% where wasmex and the compiled wasm are available. Documented, not faked.

-module(beam4pm_rust4pm).

-export([start/0, import_xes/1, import_xes_path/1, import_xes_gz/1, log_stats/1,
         top_n_variants/2, discover_dfg/1, discover_alphappp/1, discover_alphappp/2,
         import_pnml/1, import_pnml_path/1, align_variants/2, align_variants/3,
         align_trace/2, align_trace/3, compute_fitness/2, compute_fitness/3,
         activities_to_alphabet/1, activity_position/2, free_log/1, free_net/1]).

-type result() :: {ok, map()} | {error, term()}.
-type handle() :: non_neg_integer().

%% Start (or find already-started) the named Wasmex engine process.
-spec start() -> {ok, pid()} | {error, term()}.
start() -> 'Elixir.BeamPM.Rust4PM':start().

%% Import a full XES document (UTF-8 binary content, not a path).
-spec import_xes(binary()) -> result().
import_xes(Content) -> 'Elixir.BeamPM.Rust4PM':import_xes(Content).

%% Read Path host-side and import its XES content.
-spec import_xes_path(binary()) -> result().
import_xes_path(Path) -> 'Elixir.BeamPM.Rust4PM':import_xes_path(Path).

%% Import gzipped XES; GzBytes are the raw .xes.gz bytes (base64 is applied
%% host-side by the Elixir wrapper before crossing the wasm boundary).
-spec import_xes_gz(binary()) -> result().
import_xes_gz(GzBytes) -> 'Elixir.BeamPM.Rust4PM':import_xes_gz(GzBytes).

-spec log_stats(handle()) -> result().
log_stats(Handle) -> 'Elixir.BeamPM.Rust4PM':log_stats(Handle).

-spec top_n_variants(handle(), non_neg_integer()) -> result().
top_n_variants(Handle, N) -> 'Elixir.BeamPM.Rust4PM':top_n_variants(Handle, N).

-spec discover_dfg(handle()) -> result().
discover_dfg(Handle) -> 'Elixir.BeamPM.Rust4PM':discover_dfg(Handle).

%% Alpha+++ discovery with the engine-default AlphaPPPConfig.
-spec discover_alphappp(handle()) -> result().
discover_alphappp(Handle) -> 'Elixir.BeamPM.Rust4PM':discover_alphappp(Handle).

%% Alpha+++ discovery with an explicit config map (all 7 AlphaPPPConfig
%% fields required when present -- serde deserializes it verbatim).
-spec discover_alphappp(handle(), map() | nil) -> result().
discover_alphappp(Handle, Config) ->
    'Elixir.BeamPM.Rust4PM':discover_alphappp(Handle, Config).

%% Import a full PNML document (UTF-8 binary content, not a path).
-spec import_pnml(binary()) -> result().
import_pnml(Content) -> 'Elixir.BeamPM.Rust4PM':import_pnml(Content).

-spec import_pnml_path(binary()) -> result().
import_pnml_path(Path) -> 'Elixir.BeamPM.Rust4PM':import_pnml_path(Path).

%% Align all log variants against a net; default AlignmentOptions
%% (max_states 5_000_000, standard 1/1/0/0 cost function).
-spec align_variants(handle(), handle()) -> result().
align_variants(LogHandle, NetHandle) ->
    'Elixir.BeamPM.Rust4PM':align_variants(LogHandle, NetHandle).

%% Explicit options map; a discounted-cost key ("exponent"/"discount"/
%% "discount_exponent") is refused by the engine as unsupported, never faked.
-spec align_variants(handle(), handle(), map() | nil) -> result().
align_variants(LogHandle, NetHandle, Options) ->
    'Elixir.BeamPM.Rust4PM':align_variants(LogHandle, NetHandle, Options).

%% Align one trace (list of activity-name binaries) against a net.
-spec align_trace(handle(), [binary()]) -> result().
align_trace(NetHandle, Trace) ->
    'Elixir.BeamPM.Rust4PM':align_trace(NetHandle, Trace).

-spec align_trace(handle(), [binary()], map() | nil) -> result().
align_trace(NetHandle, Trace, Options) ->
    'Elixir.BeamPM.Rust4PM':align_trace(NetHandle, Trace, Options).

-spec compute_fitness(handle(), handle()) -> result().
compute_fitness(LogHandle, NetHandle) ->
    'Elixir.BeamPM.Rust4PM':compute_fitness(LogHandle, NetHandle).

-spec compute_fitness(handle(), handle(), map() | nil) -> result().
compute_fitness(LogHandle, NetHandle, Options) ->
    'Elixir.BeamPM.Rust4PM':compute_fitness(LogHandle, NetHandle, Options).

-spec activities_to_alphabet(handle()) -> result().
activities_to_alphabet(Handle) ->
    'Elixir.BeamPM.Rust4PM':activities_to_alphabet(Handle).

-spec activity_position(handle(), binary()) -> result().
activity_position(Handle, Activity) ->
    'Elixir.BeamPM.Rust4PM':activity_position(Handle, Activity).

-spec free_log(handle()) -> result().
free_log(Handle) -> 'Elixir.BeamPM.Rust4PM':free_log(Handle).

-spec free_net(handle()) -> result().
free_net(Handle) -> 'Elixir.BeamPM.Rust4PM':free_net(Handle).
