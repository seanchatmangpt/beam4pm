# syntax=docker/dockerfile:1
# Composed beam4pm image: the ggen-manufactured Erlang projection compiled by
# rebar3, gated in-build by the real rebar3 eunit + mix test suites, and shipped
# as a slim erlang runtime whose default CMD runs a real process-discovery demo
# (beam4pm_discovery over a seeded OCEL log). Published to
# ghcr.io/<owner>/beam4pm by the ggen-manufactured
# .github/workflows/beam4pm-container.yml (see ontology.ttl's bex:containerWorkflow
# facts) -- the same manufactured-consumption pattern as
# ghcr.io/seanchatmangpt/ggen-ecosystem.
#
# Base image tags resolved for real against Docker Hub's tag API on 2026-08-29
# (hexpm/elixir and hexpm/erlang both list the exact tags below; multi-arch,
# so this builds natively on amd64 runners and arm64 laptops alike). OTP is
# 27.2.4 -- the newest real 27.2.x hexpm image; CI's erlef/setup-beam
# `otp-version: '27.2'` range resolves to the same 27.2.x line.
#
# GLEAM IS DELIBERATELY EXCLUDED from this image: the hexpm base images carry
# no gleam and no clean in-image install path exists (the gleam release
# tarballs are per-arch binaries, which would need arch-conditional download
# logic here). The Gleam projection is validated in CI instead, via
# erlef/setup-beam's real `gleam-version` input in beam4pm-ci.yml.

# --- builder ------------------------------------------------------------
FROM hexpm/elixir:1.18.5-erlang-27.2.4-debian-bookworm-20260824 AS builder

ENV LANG=C.UTF-8

# rebar3 is not in the hexpm image; its release escript is pure BEAM bytecode
# (arch-independent), pinned to the same 3.24.0 the CI workflow installs.
# git is needed by hex/mix for some package operations; build-essential
# provides the C/C++ toolchain the Rust NIF link step (and RocksDB inside
# oxrocksdb-sys) needs; clang/libclang-dev/llvm-dev are required because
# oxrocksdb-sys's build.rs runs bindgen against RocksDB's C API and bindgen
# needs a real libclang shared library at build time -- the exact same
# confirmed-the-hard-way requirement ggen-ecosystem's Dockerfile documents
# for the same crate. python3 is required at `mix test` time: the real
# BeamPM.Actuation/BeamPM.ProcessGovernor Chicago test suites spawn the real
# qualification/fixtures/toy_gym_bridge.py fixture as a subprocess (a real
# collaborator, not a mock) -- confirmed the hard way by a real CI failure
# ("fixture gym bridge not found") before this line was added.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git build-essential clang libclang-dev llvm-dev python3 \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL -o /usr/local/bin/rebar3 \
        https://github.com/erlang/rebar3/releases/download/3.24.0/rebar3 \
    && chmod +x /usr/local/bin/rebar3

# beam4pm's mix.exs declares {:ggen_igniter, only: [:dev, :test]} whose
# native/ggen_graph_nif crate (rustler 0.36 + oxigraph 0.5.9) compiles at
# `mix test` time -- Debian bookworm's apt rustc (1.63) is too old for
# oxigraph, so a real current stable toolchain comes from rustup. This is
# the price of keeping the FULL mix test suite as an in-image build gate
# instead of quietly shrinking the gate to prod-only compilation.
RUN curl -fsSL https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal
ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /app
COPY rebar.config mix.exs mix.lock ./
COPY src ./src
COPY lib ./lib
COPY test ./test
COPY qualification ./qualification
COPY native ./native
COPY scripts/env ./scripts/env

# RF1/RF2/RF3's real Chicago tests spawn these compiled Rust oracle binaries
# as subprocesses (rust4pm's own process_mining =0.6.2 function surface, no
# algorithm re-implemented) -- built fresh here, same as ggen-ecosystem's own
# Dockerfile builds oxrocksdb-sys against the rustup toolchain above.
RUN cd native/rf1-dfg-oracle && cargo build --release \
    && cd ../rf2-conformance-oracle && cargo build --release \
    && cd ../rf3-ocel-oracle && cargo build --release

# Build gates: the real test suites, run against real collaborators (the
# compiled projections themselves) -- a failing suite fails the image build.
# rebar3 compile populates _build/default/lib/beam4pm/ebin (the runtime
# artifacts); rebar3 eunit compiles/runs the test profile on top of it.
RUN rebar3 compile && rebar3 eunit
RUN mix local.hex --force && mix deps.get
RUN . ./scripts/env/rust4pm_reactor_env.sh && mix test

# Demo module: seeds the same known OCEL log shape the generated eunit court
# uses (8 events, 3 cases keyed by attribute "case_id", two skip cases), then
# runs the real discovery pipeline end to end: traces_from_events ->
# dfg_from_traces -> conformance, printing each result.
COPY <<'DEMO_EOF' /app/demo/beam4pm_demo.erl
%% Demo driver for the composed beam4pm container image (hand-authored infra,
%% same category as the Dockerfile that embeds it -- the beam4pm_* modules it
%% drives are ggen-manufactured and never hand-edited).
-module(beam4pm_demo).
-export([run/0]).

run() ->
    Events = seed_events(),
    Traces = beam4pm_discovery:traces_from_events(Events, <<"case_id">>),
    Dfg = beam4pm_discovery:dfg_from_traces(Traces),
    io:format("beam4pm discovery demo -- seeded OCEL log: ~b events, ~b cases~n",
              [length(Events), length(Traces)]),
    io:format("traces (case_id: activity_sequence):~n"),
    lists:foreach(
        fun(T) ->
            io:format("  ~s: ~p~n",
                      [beam4pm_discovery:log_trace_case_id(T),
                       beam4pm_discovery:log_trace_activity_sequence(T)])
        end, Traces),
    io:format("directly-follows graph (~b edges):~n", [length(Dfg)]),
    lists:foreach(
        fun(E) ->
            io:format("  ~s -> ~s (x~b)~n",
                      [beam4pm_discovery:dfg_edge_source_activity(E),
                       beam4pm_discovery:dfg_edge_target_activity(E),
                       beam4pm_discovery:dfg_edge_frequency(E)])
        end, Dfg),
    io:format("conformance of each trace against the discovered DFG:~n"),
    lists:foreach(
        fun(T) ->
            R = beam4pm_discovery:conformance(Dfg, T),
            io:format("  ~s: fitness ~.2f~n",
                      [beam4pm_discovery:conformance_result_trace_id(R),
                       beam4pm_discovery:conformance_result_fitness(R)])
        end, Traces),
    ok.

seed_events() ->
    [ev(<<"e5">>, <<"c">>, <<"2026-08-29T10:02:00Z">>, #{<<"case_id">> => <<"c1">>}),
     ev(<<"e4">>, <<"b">>, <<"2026-08-29T10:01:30Z">>, #{<<"case_id">> => <<"c2">>}),
     ev(<<"e1">>, <<"a">>, <<"2026-08-29T10:00:00Z">>, #{<<"case_id">> => <<"c1">>}),
     ev(<<"e7">>, <<"x">>, <<"2026-08-29T10:04:00Z">>, #{<<"other">> => <<"v">>}),
     ev(<<"e2">>, <<"a">>, <<"2026-08-29T10:01:30Z">>, #{<<"case_id">> => <<"c2">>}),
     ev(<<"e6">>, <<"a">>, <<"2026-08-29T10:03:00Z">>, #{<<"case_id">> => <<"c3">>}),
     ev(<<"e3">>, <<"b">>, <<"2026-08-29T10:01:00Z">>, #{<<"case_id">> => <<"c1">>})].

ev(Id, Type, Time, Attributes) ->
    {ok, Ev} = beam4pm_types:new_ocel_event(
        #{event_id => Id, event_type => Type, event_time => Time,
          attributes => Attributes}),
    Ev.
DEMO_EOF
RUN erlc -o /app/_build/default/lib/beam4pm/ebin /app/demo/beam4pm_demo.erl

# --- final ---------------------------------------------------------------
FROM hexpm/erlang:29.0-debian-bookworm-20260610-slim

ENV LANG=C.UTF-8

COPY --from=builder /app/_build/default/lib/beam4pm/ebin /opt/beam4pm/ebin

CMD ["erl", "-noshell", "-pa", "/opt/beam4pm/ebin", "-eval", "beam4pm_demo:run()", "-s", "init", "stop"]
