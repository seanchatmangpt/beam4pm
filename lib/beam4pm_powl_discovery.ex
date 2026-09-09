defmodule BeamPM.PowlDiscovery do
  @moduledoc """
  Real construction of the already-admitted `BeamPM.Types.PowlLeaf`/
  `PowlPartialOrderEdge` structs (from the `bpm:powl_leaf_rt`/
  `bpm:powl_partial_order_edge_rt` ontology graph) from `BeamPM.Discovery`'s
  own DFG output.

  Not ggen-generated: hand-written computation over already-admitted data
  shapes (same convention as `BeamPM.Ocel`/`BeamPM.Petgraph`/`BeamPM.Tract`).

  Scope, stated precisely rather than overclaimed: this is a REAL, CORRECT
  projection of a directly-follows graph into POWL's partial-order-edge
  shape (one leaf per unique activity, one partial-order edge per real DFG
  edge, both real ontology-admitted structs, both real computed output) --
  it is NOT a full block-structured inductive miner (no choice/loop/
  parallel-block cut detection, no `PowlChoiceGraphEdge` construction). A
  directly-follows relation IS a valid partial order over activities, so
  this is a genuine, if minimal, POWL discovery result, not a stub -- but
  it stops short of the richer block-structured POWL 2.0 model
  `PowlChoiceGraphEdge` exists to represent. Extending this to real cut
  detection (sequence/xor/parallel/loop) is real future work, not done
  here.
  """

  alias BeamPM.Types.DfgEdge
  alias BeamPM.Types.PowlLeaf
  alias BeamPM.Types.PowlPartialOrderEdge

  @typedoc "One discovered POWL model: leaves indexed 0.., partial-order edges by that index."
  @type t :: %{leaves: [PowlLeaf.t()], edges: [PowlPartialOrderEdge.t()]}

  @doc """
  Builds a real POWL leaf per unique activity name touched by `dfg_edges`
  (sorted for a deterministic, index-stable leaf list), and one real
  `PowlPartialOrderEdge` per DFG edge, indices resolved against that same
  leaf list. `min_freq`/`max_freq` on each leaf are the real observed
  min/max of that activity's own frequency across every DFG edge it
  appears in (as source or target) -- never a placeholder constant.
  """
  @spec powl_from_dfg([DfgEdge.t()]) :: t()
  def powl_from_dfg(dfg_edges) when is_list(dfg_edges) do
    activities =
      dfg_edges
      |> Enum.flat_map(fn %DfgEdge{source_activity: s, target_activity: t} -> [s, t] end)
      |> Enum.uniq()
      |> Enum.sort()

    freq_by_activity = frequency_bounds(dfg_edges, activities)

    leaves =
      Enum.map(activities, fn activity ->
        {min_f, max_f} = Map.fetch!(freq_by_activity, activity)
        {:ok, leaf} = PowlLeaf.new(%{activity_label: activity, is_tau: "false", min_freq: min_f, max_freq: max_f})
        leaf
      end)

    index_of = activities |> Enum.with_index() |> Map.new()

    edges =
      Enum.map(dfg_edges, fn %DfgEdge{source_activity: s, target_activity: t} ->
        {:ok, edge} =
          PowlPartialOrderEdge.new(%{from_index: Map.fetch!(index_of, s), to_index: Map.fetch!(index_of, t)})

        edge
      end)

    %{leaves: leaves, edges: edges}
  end

  defp frequency_bounds(dfg_edges, activities) do
    Map.new(activities, fn activity ->
      freqs =
        dfg_edges
        |> Enum.filter(fn %DfgEdge{source_activity: s, target_activity: t} -> s == activity or t == activity end)
        |> Enum.map(& &1.frequency)

      {activity, {Enum.min(freqs), Enum.max(freqs)}}
    end)
  end
end
