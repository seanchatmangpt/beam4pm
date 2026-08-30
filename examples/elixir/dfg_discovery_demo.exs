# dfg_discovery_demo -- a real, runnable exercise of actual process-mining
# behavior (GATE M4) through the ggen-manufactured modules BeamPM.Types,
# BeamPM.Discovery and BeamPM.Codec: DFG discovery from a seeded OCEL event
# log, then conformance checking against the discovered model. All results
# printed below come out of the real pipeline; the script raises on any
# constructor error and exits non-zero if the assertions at the bottom fail.
#
# Run from the repo root:
#   mix run examples/elixir/dfg_discovery_demo.exs

alias BeamPM.{Codec, Discovery, Types}

raw = [
  {"e5", "validate_order", "2026-08-29T10:05:00Z", "c2"},
  {"e1", "receive_order",  "2026-08-29T10:00:00Z", "c1"},
  {"e6", "ship_order",     "2026-08-29T10:06:00Z", "c2"},
  {"e2", "validate_order", "2026-08-29T10:01:00Z", "c1"},
  {"e4", "receive_order",  "2026-08-29T10:04:00Z", "c2"},
  {"e3", "ship_order",     "2026-08-29T10:02:00Z", "c1"},
  {"e7", "receive_order",  "2026-08-29T10:07:00Z", "c3"},
  {"e8", "ship_order",     "2026-08-29T10:08:00Z", "c3"}
]

events =
  for {id, ty, ts, case_id} <- raw do
    {:ok, e} =
      Types.OcelEvent.new(%{
        event_id: id,
        event_type: ty,
        event_time: ts,
        attributes: %{"case_id" => case_id}
      })

    e
  end

traces = Discovery.traces_from_events(events, "case_id")
IO.puts("traces discovered: #{length(traces)}")

for t <- traces do
  m = Codec.to_map(t)
  IO.puts("  #{m["case_id"]}: #{inspect(m["activity_sequence"])}")
end

edges = Discovery.dfg_from_traces(traces)
IO.puts("dfg edges:")

for ed <- edges do
  m = Codec.to_map(ed)
  IO.puts("  #{m["source_activity"]} -> #{m["target_activity"]} x#{m["frequency"]}")
end

IO.puts("conformance (model = discovered dfg):")

for t <- traces do
  m = Codec.to_map(Discovery.conformance(edges, t))
  IO.puts("  fitness(#{m["trace_id"]}) = #{m["fitness"]}")
end

{:ok, deviant} =
  Types.LogTrace.new(%{case_id: "d1", activity_sequence: ["receive_order", "cancel_order"]})

dev = Codec.to_map(Discovery.conformance(edges, deviant))
IO.puts("  fitness(d1 deviant) = #{dev["fitness"]}")

# Hard assertions -- fail loudly if discovery is wrong.
3 = length(traces)
true = dev["fitness"] < 1.0
IO.puts("dfg_discovery_demo: PASS")
