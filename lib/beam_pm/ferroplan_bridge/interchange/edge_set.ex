defmodule BeamPM.FerroplanBridge.EdgeSet do
  alias BeamPM.FerroplanBridge.SemanticEdge
  def candidates(edges, capability), do: Enum.filter(edges, &SemanticEdge.eligible?(&1, capability))
  def exclude(edges, failed_id), do: Enum.reject(edges, &(&1.id == failed_id))
  def select(edges, capability), do: edges |> candidates(capability) |> List.first()
end
