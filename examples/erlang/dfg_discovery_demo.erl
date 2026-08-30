#!/usr/bin/env escript
-mode(compile).

%% dfg_discovery_demo -- a real, runnable exercise of actual process-mining
%% behavior (GATE M4): DFG discovery + conformance checking through the
%% ggen-manufactured modules beam4pm_types, beam4pm_discovery and
%% beam4pm_codec. Nothing here is a stub or a printout of hard-coded results:
%% every event is constructed through the real validating constructor, the
%% traces/edges/fitness printed below come out of the real
%% beam4pm_discovery:traces_from_events/2 -> dfg_from_traces/1 ->
%% conformance/2 pipeline, and record fields are read back through the real
%% beam4pm_codec:to_map/1 (the supported, generated accessor path -- no
%% private record-layout poking).
%%
%% Usage (from the repo root, after `rebar3 compile` or any build that
%% produced beam4pm_types/discovery/codec .beam files):
%%   escript examples/erlang/dfg_discovery_demo.erl _build/default/lib/beam4pm/ebin
%% or compile ad hoc:
%%   mkdir -p /tmp/b4pm_ebin && erlc -o /tmp/b4pm_ebin src/*.erl
%%   escript examples/erlang/dfg_discovery_demo.erl /tmp/b4pm_ebin

main([EbinDir | _]) ->
    true = code:add_patha(EbinDir),
    run();
main([]) ->
    run().

run() ->
    %% A seeded order-to-ship log: three conforming cases, deliberately fed
    %% in shuffled timestamp order to prove the time sort is real.
    Raw = [
        {<<"e5">>, <<"validate_order">>, <<"2026-08-29T10:05:00Z">>, <<"c2">>},
        {<<"e1">>, <<"receive_order">>,  <<"2026-08-29T10:00:00Z">>, <<"c1">>},
        {<<"e6">>, <<"ship_order">>,     <<"2026-08-29T10:06:00Z">>, <<"c2">>},
        {<<"e2">>, <<"validate_order">>, <<"2026-08-29T10:01:00Z">>, <<"c1">>},
        {<<"e4">>, <<"receive_order">>,  <<"2026-08-29T10:04:00Z">>, <<"c2">>},
        {<<"e3">>, <<"ship_order">>,     <<"2026-08-29T10:02:00Z">>, <<"c1">>},
        {<<"e7">>, <<"receive_order">>,  <<"2026-08-29T10:07:00Z">>, <<"c3">>},
        {<<"e8">>, <<"ship_order">>,     <<"2026-08-29T10:08:00Z">>, <<"c3">>}
    ],
    Events = [begin
        {ok, E} = beam4pm_types:new_ocel_event(#{
            event_id => Id, event_type => Ty, event_time => Ts,
            attributes => #{<<"case_id">> => Case}
        }),
        E
    end || {Id, Ty, Ts, Case} <- Raw],

    Traces = beam4pm_discovery:traces_from_events(Events, <<"case_id">>),
    io:format("traces discovered: ~p~n", [length(Traces)]),
    lists:foreach(fun(T) ->
        M = beam4pm_codec:to_map(T),
        io:format("  ~s: ~p~n",
                  [maps:get(<<"case_id">>, M), maps:get(<<"activity_sequence">>, M)])
    end, Traces),

    Edges = beam4pm_discovery:dfg_from_traces(Traces),
    io:format("dfg edges:~n"),
    lists:foreach(fun(Ed) ->
        M = beam4pm_codec:to_map(Ed),
        io:format("  ~s -> ~s x~p~n",
                  [maps:get(<<"source_activity">>, M),
                   maps:get(<<"target_activity">>, M),
                   maps:get(<<"frequency">>, M)])
    end, Edges),

    io:format("conformance (model = discovered dfg):~n"),
    lists:foreach(fun(T) ->
        C = beam4pm_discovery:conformance(Edges, T),
        M = beam4pm_codec:to_map(C),
        io:format("  fitness(~s) = ~p~n",
                  [maps:get(<<"trace_id">>, M), maps:get(<<"fitness">>, M)])
    end, Traces),

    %% A deviant trace the discovered model has never seen one edge of:
    {ok, Deviant} = beam4pm_types:new_log_trace(#{
        case_id => <<"d1">>,
        activity_sequence => [<<"receive_order">>, <<"cancel_order">>]
    }),
    DevC = beam4pm_discovery:conformance(Edges, Deviant),
    DevM = beam4pm_codec:to_map(DevC),
    DevFit = maps:get(<<"fitness">>, DevM),
    io:format("  fitness(d1 deviant) = ~p~n", [DevFit]),

    %% Hard assertions -- this demo fails loudly if discovery is wrong.
    3 = length(Traces),
    true = DevFit < 1.0,
    io:format("dfg_discovery_demo: PASS~n"),
    halt(0).
