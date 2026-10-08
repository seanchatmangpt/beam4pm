defmodule BeamPM.W601MapUpdateDualSafeTest do
  @moduledoc """
  W601 regression: the three ABSENT-KEY-RELIANT `Map.update/4` census sites
  (w525d sweep) were replaced with the dual-safe `Map.fetch`/`Map.put` idiom.
  The idiom stores `default` directly on the absent-key path and applies the
  update function only on the present-key path — so the result is identical
  whether the underlying runtime implements documented `Map.update` semantics
  (fun applied to default) or the observed otp-29 deviation (fun skipped).
  These tests pin that invariance through the public API.
  """

  use ExUnit.Case, async: true

  alias BeamPM.Discovery
  alias BeamPM.Pro.Simulation
  alias BeamPM.Types.ServiceSpan

  describe "discovery link counts (lib/beam4pm_discovery.ex:310)" do
    test "repeated identical parent/child pair counts each link once" do
      spans = [
        span!("s1", "a", nil, "t1", "2026-09-05T10:00:00.000Z"),
        span!("s2", "a", "s1", "t1", "2026-09-05T10:00:00.010Z"),
        span!("s3", "a", "s2", "t1", "2026-09-05T10:00:00.020Z"),
        span!("s4", "a", "s3", "t1", "2026-09-05T10:00:00.030Z")
      ]

      assert {:ok, evidence} = Discovery.causal_dfg_from_spans(spans)

      observed =
        evidence.observed
        |> Enum.filter(&(&1.source_service == "a" and &1.target_service == "a"))
        |> Enum.map(& &1.frequency)

      # one distinct pair {a, a}, each of the 3 links counted exactly once
      assert observed == [3]
    end
  end

  describe "simulation adjacency (lib/beam4pm_pro_simulation.ex:53,76)" do
    test "reachable_from follows repeated edges correctly" do
      edges = [{"a", "b", 1}, {"a", "b", 2}, {"b", "c", 1}]
      assert Simulation.reachable_from(edges, "a") == MapSet.new(["a", "b", "c"])
    end

    test "has_cycle? detects a cycle through duplicated edges" do
      edges = [{"a", "b", 1}, {"a", "b", 2}, {"b", "a", 1}]
      assert Simulation.has_cycle?(edges) == true
    end
  end

  defp span!(span_id, service_name, parent_span_id, trace_id, start_time) do
    {:ok, span} =
      ServiceSpan.new(%{
        span_id: span_id,
        service_name: service_name,
        duration_ms: 10,
        parent_span_id: parent_span_id,
        trace_id: trace_id,
        start_time: start_time
      })

    span
  end
end
