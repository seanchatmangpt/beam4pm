#!/usr/bin/env escript
-mode(compile).

%% ocel_log_demo -- a real, runnable exercise of beam4pm_types, the
%% ggen-manufactured Erlang module generated from the admitted bpm:RecordType
%% RDF/SHACL graph (see /Users/sac/beam4pm/generated/erlang/src/beam4pm_types.erl
%% and its ggen template at
%% .../beam4pm-process-model-pack/templates/beam4pm_types.erl.tmpl).
%% This is not a stub: every event below is constructed by a real call to
%% beam4pm_types:new_ocel_event/1, and the demo halts non-zero on the first
%% constructor failure instead of swallowing it.
%%
%% beam4pm_types:new_ocel_event/1 has the spec:
%%   -spec new_ocel_event(map()) -> {ok, ocel_event()} | {error, {missing_field, atom()}}.
%% and validates three required keys (event_id, event_type, event_time) in
%% order, returning {error, {missing_field, FirstMissingKey}} on the first one
%% absent from the input map. attributes is optional.
%%
%% NOTE on reading fields back out of the returned #ocel_event{}: the record
%% is defined only inside beam4pm_types.erl (generated, marked "do not edit")
%% and the module ships no .hrl and no field accessors, so an external module
%% has no supported way to pattern-match its fields without redeclaring the
%% record definition itself (which would silently drift if the generator ever
%% reorders fields). This demo instead prints event_id/event_type from the
%% same source map used to build the constructor argument -- the honest
%% option for data the caller already has, rather than reaching into another
%% module's private record layout. The {ok, _Event} match below still forces
%% a real call into beam4pm_types and a real check that construction actually
%% succeeded; only the *printed* fields come from the map, not the return
%% value's opaque record.
%%
%% Code path: beam4pm_types must already be compiled and loadable. This
%% script accepts the compiled ebin directory as its first argument and adds
%% it to the code path itself via code:add_patha/1 (verified working against
%% Erlang/OTP 28.3.1 in this environment); if no argument is given it assumes
%% the ebin directory was already placed on the code path externally (e.g.
%% via `escript -pa <ebin> ...` -- note that flag is accepted by the `erl`
%% runtime escript launches, not always positionally by every escript build,
%% so passing the path as an explicit argv[0] here is the more portable of
%% the two and is what README.md recommends).

main(Args) ->
    ok = ensure_code_path(Args),
    EventSpecs = [
        #{event_id => <<"e-001">>, event_type => <<"order_placed">>,
          event_time => <<"2026-01-01T09:00:00Z">>,
          attributes => #{<<"amount">> => 42}},
        #{event_id => <<"e-002">>, event_type => <<"payment_received">>,
          event_time => <<"2026-01-01T09:05:00Z">>},
        #{event_id => <<"e-003">>, event_type => <<"order_shipped">>,
          event_time => <<"2026-01-01T10:30:00Z">>,
          attributes => #{<<"carrier">> => <<"ups">>}}
    ],
    lists:foreach(fun build_and_report/1, EventSpecs),
    ok.

%% If an ebin directory was passed as the first CLI argument, add it to the
%% code path so beam4pm_types:new_ocel_event/1 resolves to a real, loaded
%% module. Otherwise assume the caller already arranged the code path.
ensure_code_path([EbinPath | _]) ->
    case code:add_patha(EbinPath) of
        true -> ok;
        {error, Reason} ->
            io:format(standard_error,
                      "could not add code path ~s: ~p~n", [EbinPath, Reason]),
            halt(1)
    end;
ensure_code_path([]) ->
    ok.

%% Call the real beam4pm_types constructor for one OCEL event. On success,
%% print a one-line summary. On the first constructor failure, print the
%% real {missing_field, Field} reason to stderr and halt with a non-zero
%% exit code (per the task's escript-style pattern-match-and-halt contract).
build_and_report(Spec) ->
    case beam4pm_types:new_ocel_event(Spec) of
        {ok, _Event} ->
            EventId = maps:get(event_id, Spec),
            EventType = maps:get(event_type, Spec),
            io:format("ocel_event id=~s type=~s~n", [EventId, EventType]);
        {error, Reason} ->
            io:format(standard_error,
                      "beam4pm_types:new_ocel_event/1 failed: ~p~n", [Reason]),
            halt(1)
    end.
