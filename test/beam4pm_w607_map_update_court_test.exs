# W607 lane court (WP-4 / OS-20 Map.update sweep). Parameterized court over the
# three class-(b) Map.update/3 sites, exercised through their real public entry
# points on both empty and populated accumulators (Chicago-style: real module
# collaborators, no mocks). No site was patched: classification is default-
# intended accumulator insert, relied-upon semantics preserved.
#
# Parameterization: scenarios/0 is a {tag, description, probe} table; the single
# runner test executes every probe and asserts none failed. Each probe asserts
# deterministic-insertion behavior on empty and populated accumulator state
# through the module's real public function.

defmodule BeamPM.W607MapUpdateCourtTest do
  use ExUnit.Case, async: true

  alias BeamPM.ClaudeWorkflowReactor
  alias BeamPM.Discovery
  alias BeamPM.Revenue.Metering
  alias BeamPM.Types.OcelEvent
  alias BeamPM.Types.ServiceSpan

  defp scenarios do
    [
    {:metering_populated,
     "metering populated accumulator: better_last picks max, not first-inserted",
     fn ->
       ev = fn id, time ->
         %OcelEvent{
           event_id: id,
           event_type: "task",
           event_time: time,
           attributes: %{"case" => "C1"}
         }
       end

       events = [
         ev.("e1", "2026-10-07T10:00:00Z"),
         ev.("e2", "2026-10-07T09:30:00Z"),
         ev.("e3", "2026-10-07T11:15:00Z")
       ]

       out =
         Metering.emit_usage_events(
           events,
           "ent-1",
           "actions",
           {"2026-10-01T00:00:00Z", "2026-10-08T00:00:00Z"}
         )

       assert [%BeamPM.Billing.UsageEvent{} = usage] = out
       assert usage.occurred_at == "2026-10-07T11:15:00Z"
     end},
    {:metering_empty,
     "metering empty accumulator: only case-carrying events enter the map",
     fn ->
       events = [
         %OcelEvent{
           event_id: "x",
           event_type: "t",
           event_time: "2026-10-07T00:00:00Z",
           attributes: %{}
         }
       ]

       out =
         Metering.emit_usage_events(
           events,
           "ent-1",
           "actions",
           {"2026-10-01T00:00:00Z", "2026-10-08T00:00:00Z"}
         )

       assert [] = out
     end},
    {:discovery_populated,
     "discovery counting accumulator: repeated pair increments (populated)",
     fn ->
       span = fn id, svc, parent ->
         %ServiceSpan{
           span_id: id,
           service_name: svc,
           duration_ms: 1,
           parent_span_id: parent,
           trace_id: "t1",
           start_time: "2026-10-07T00:00:0" <> id
         }
       end

       # Parent-child pairs: (gateway,svc) x1, (svc,svc) x2, (svc,db) x1.
       spans = [
         span.("1", "gateway", nil),
         span.("2", "svc", "1"),
         span.("3", "svc", "2"),
         span.("4", "db", "3"),
         span.("5", "svc", "2")
       ]

       assert {:ok, %{observed: edges, orphans: []}} =
                 Discovery.causal_dfg_from_spans(spans)

       pair_counts =
         Map.new(edges, fn edge ->
           {{edge.source_service, edge.target_service}, edge.frequency}
         end)

       # Populated accumulator: repeated pair reaches frequency 2 via
       # Map.update(counts, pair, 1, &(&1 + 1)).
       assert pair_counts[{"svc", "svc"}] == 2
       assert pair_counts[{"gateway", "svc"}] == 1
       assert pair_counts[{"svc", "db"}] == 1
     end},
    {:discovery_empty,
     "discovery empty accumulator: first pair inserts default 1",
     fn ->
       span = fn id, svc, parent ->
         %ServiceSpan{
           span_id: id,
           service_name: svc,
           duration_ms: 1,
           parent_span_id: parent,
           trace_id: "t1",
           start_time: "2026-10-07T00:00:0" <> id
         }
       end

       spans = [span.("1", "gateway", nil), span.("2", "svc", "1")]

       assert {:ok, %{observed: [%BeamPM.Types.SpanEdge{} = edge], orphans: []}} =
                 Discovery.causal_dfg_from_spans(spans)

       assert edge.source_service == "gateway"
       assert edge.target_service == "svc"
       # Empty accumulator: first occurrence inserts the default 1.
       assert edge.frequency == 1
     end},
    {:reactor_populated,
     "reactor max accumulator: max line wins across out-of-order results",
     fn ->
       entries = [
         %{type: "started", agent_id: "a1", line: 10},
         %{type: "result", agent_id: "a1", line: 42},
         %{type: "started", agent_id: "a2", line: 50},
         %{type: "result", agent_id: "a2", line: 33},
         %{type: "result", agent_id: "a2", line: 77}
       ]

       waves = ClaudeWorkflowReactor.derive_waves(entries)
       labeled = ClaudeWorkflowReactor.label_phases(waves)

       assert [
                %{phase: :measure, ordinal_span: {10, 42}},
                %{phase: :qualify, ordinal_span: {50, 77}}
              ] = labeled
     end},
    {:reactor_empty,
     "reactor empty accumulator: no results gives nil ordinal span end",
     fn ->
       entries = [%{type: "started", agent_id: "a1", line: 5}]

       waves = ClaudeWorkflowReactor.derive_waves(entries)
       labeled = ClaudeWorkflowReactor.label_phases(waves)

       assert [%{phase: :measure, ordinal_span: {5, nil}}] = labeled
     end}
    ]
  end

  test "w607 map.update court: all scenarios pass", do: run_scenarios()

  defp run_scenarios do
    results =
      for {tag, desc, probe} <- scenarios() do
        {tag, desc,
         try do
           probe.()
           :pass
         rescue
           e -> {:fail, Exception.message(e)}
         end}
      end

    failures = Enum.reject(results, fn {_tag, _desc, r} -> r == :pass end)

    assert failures == [], """
    W607 Map.update court failures:
    #{Enum.map_join(failures, "\n", fn {tag, desc, r} -> "#{tag}: #{desc}\n  #{inspect(r)}" end)}
    """
  end
end
