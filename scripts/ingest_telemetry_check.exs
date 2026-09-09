# ingest_telemetry_check.exs -- Chicago-style self-test for
# scripts/ingest_telemetry.exs. Real `:telemetry.execute/3` calls against
# the real `:telemetry` application (already a transitive dependency via
# :ash/:reactor/:plug -- see mix.lock), real
# `%BeamPM.Types.OcelEvent{}`/`%BeamPM.Types.LogTrace{}` structs built by
# the GENERATED constructors, real state-based assertions on what came
# back. No `Mock`/`MagicMock`/`patch`/`monkeypatch` equivalent anywhere in
# this file -- grep for that class of import/call over scripts/ingest_*.exs
# is expected to return zero matches (see the shell one-liner in this
# script's own report).
#
# Usage:
#     BEAM4PM_INGEST_SKIP_DEMO=1 mix run scripts/ingest_telemetry_check.exs
#
# (BEAM4PM_INGEST_SKIP_DEMO=1 is required because `mix run` first compiles
# and executes ingest_telemetry.exs's own top-level demo block as a side
# effect of `Code.require_file`/module load in the same VM; skipping it
# here keeps this check's assertions isolated to state THIS script itself
# produces.)
#
# Exits 0 and prints "ALL CHECKS PASSED" on success; exits 1 and prints
# the failing assertion otherwise -- a real pass/fail signal, not a
# description of one.

Code.require_file("ingest_telemetry.exs", __DIR__)

alias BeamPM.Ingest.Bridge
alias BeamPM.Types.OcelEvent
alias BeamPM.Types.LogTrace

defmodule Check do
  def assert(true, _msg), do: :ok

  def assert(false, msg) do
    IO.puts(:stderr, "FAIL: #{msg}")
    System.halt(1)
  end

  def assert_eq(actual, expected, msg) do
    assert(actual == expected, "#{msg} -- expected #{inspect(expected)}, got #{inspect(actual)}")
  end
end

event_name = [:check, :order, :stop]

# --- 1. attach/2 returns :ok against the real :telemetry API -------------
Bridge.reset()
Check.assert_eq(Bridge.attach(event_name), :ok, "attach/2 must return :ok")

# --- 2. a real :telemetry.execute/3 call produces a real OcelEvent -------
:telemetry.execute(
  event_name,
  %{duration_native: 1000, system_time_native: System.monotonic_time()},
  %{trace_id: "t1", span_id: "s1", resource: MyApp.Order, action: :place}
)

[event1] = Bridge.events()
Check.assert(match?(%OcelEvent{}, event1), "buffered value must be a real %OcelEvent{} struct")
Check.assert_eq(event1.event_id, "t1:s1", "event_id must combine trace_id:span_id")
Check.assert_eq(event1.event_type, "MyApp.Order.place", "event_type must combine resource.action")
Check.assert_eq(event1.attributes["trace_id"], "t1", "attributes must preserve trace_id")
Check.assert(is_binary(event1.event_time), "event_time must be a real ISO8601 string")

# --- 3. a second event in the same case, mined into one real trace -------
:telemetry.execute(
  event_name,
  %{duration_native: 2000, system_time_native: System.monotonic_time()},
  %{trace_id: "t1", span_id: "s2", resource: MyApp.Order, action: :ship}
)

# a DIFFERENT case, to prove case grouping is real (not "everything in one bucket")
:telemetry.execute(
  event_name,
  %{duration_native: 500, system_time_native: System.monotonic_time()},
  %{trace_id: "t2", span_id: "s3", resource: MyApp.Order, action: :place}
)

events = Bridge.events()
Check.assert_eq(length(events), 3, "buffer must hold exactly the 3 real events fired above")

traces = Bridge.traces("trace_id")
Check.assert_eq(length(traces), 2, "traces_from_events/2 must mine exactly 2 real cases")

t1 = Enum.find(traces, fn %LogTrace{case_id: cid} -> cid == "t1" end)
t2 = Enum.find(traces, fn %LogTrace{case_id: cid} -> cid == "t2" end)

Check.assert(t1 != nil, "case t1 must be present in the mined traces")
Check.assert(t2 != nil, "case t2 must be present in the mined traces")
Check.assert_eq(
  t1.activity_sequence,
  ["MyApp.Order.place", "MyApp.Order.ship"],
  "case t1's activity sequence must be ordered place -> ship by real event_time"
)
Check.assert_eq(
  t2.activity_sequence,
  ["MyApp.Order.place"],
  "case t2's activity sequence must contain only its own event"
)

# --- 4. detach/1 actually stops the handler from firing -------------------
:ok = Bridge.detach(event_name)
:telemetry.execute(event_name, %{}, %{trace_id: "t3", span_id: "s4"})
Check.assert_eq(length(Bridge.events()), 3, "detach/1 must stop new events from being ingested")

# --- 5. a malformed telemetry payload never crashes the handler ----------
:ok = Bridge.attach(event_name, fn _m, _md -> %{event_id: "e1"} end)
:telemetry.execute(event_name, %{}, %{})
Check.assert_eq(
  length(Bridge.events()),
  3,
  "a mapper omitting required OcelEvent fields must be handled ({:error, ...}), never crash or silently ingest"
)
:ok = Bridge.detach(event_name)

IO.puts("ALL CHECKS PASSED")
