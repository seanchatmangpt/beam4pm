defmodule BeamPM.PowlDiscoveryTest do
  use ExUnit.Case, async: true

  alias BeamPM.Discovery
  alias BeamPM.PowlDiscovery
  alias BeamPM.Types.LogTrace

  defp trace!(case_id, activities) do
    {:ok, t} = LogTrace.new(%{case_id: case_id, activity_sequence: activities})
    t
  end

  test "powl_from_dfg/1 builds one real leaf per unique activity, sorted deterministically" do
    dfg =
      Discovery.dfg_from_traces([
        trace!("c-1", ["Create Order", "Ship Order", "Close Order"]),
        trace!("c-2", ["Create Order", "Ship Order", "Close Order"])
      ])

    %{leaves: leaves} = PowlDiscovery.powl_from_dfg(dfg)

    assert Enum.map(leaves, & &1.activity_label) == ["Close Order", "Create Order", "Ship Order"]
    assert Enum.all?(leaves, &(&1.is_tau == "false"))
  end

  test "powl_from_dfg/1 builds one real partial-order edge per real DFG edge, indices resolving to the real leaf list" do
    dfg =
      Discovery.dfg_from_traces([
        trace!("c-1", ["A", "B"])
      ])

    %{leaves: leaves, edges: [edge]} = PowlDiscovery.powl_from_dfg(dfg)

    labels_by_index = leaves |> Enum.with_index() |> Map.new(fn {leaf, idx} -> {idx, leaf.activity_label} end)

    assert Map.fetch!(labels_by_index, edge.from_index) == "A"
    assert Map.fetch!(labels_by_index, edge.to_index) == "B"
  end

  test "a leaf's min_freq/max_freq are the real observed bounds, not a placeholder" do
    # A appears in two DFG edges: A->B (freq 3, from 3 traces) and A also
    # never appears as a target, so its only observed frequency is 3.
    # B appears as target of A->B (freq 3) AND source of B->C (freq 1) --
    # its real bounds are min 1, max 3.
    dfg =
      Discovery.dfg_from_traces([
        trace!("c-1", ["A", "B"]),
        trace!("c-2", ["A", "B"]),
        trace!("c-3", ["A", "B", "C"])
      ])

    %{leaves: leaves} = PowlDiscovery.powl_from_dfg(dfg)
    by_label = Map.new(leaves, &{&1.activity_label, &1})

    assert by_label["B"].min_freq == 1
    assert by_label["B"].max_freq == 3
  end

  test "an empty DFG produces a real, empty (not crashing) POWL model" do
    assert PowlDiscovery.powl_from_dfg([]) == %{leaves: [], edges: []}
  end
end
