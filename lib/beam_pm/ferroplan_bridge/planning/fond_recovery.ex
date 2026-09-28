defmodule BeamPM.FerroplanBridge.FondRecovery do
  @moduledoc "Bounded FondRecovery primitive for the Ferroplan provider composition runtime."
  def recover(edges,failed), do: edges |> Enum.reject(&(Map.get(&1,:id)==failed)) |> List.first()
end
