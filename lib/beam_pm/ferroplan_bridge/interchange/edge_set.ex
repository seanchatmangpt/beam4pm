defmodule BeamPM.FerroplanBridge.EdgeSet do
  @moduledoc "Bounded EdgeSet primitive for the Ferroplan provider composition runtime."
  def exclude(edges,id), do: Enum.reject(edges, &(Map.get(&1,:id) == id))
end
