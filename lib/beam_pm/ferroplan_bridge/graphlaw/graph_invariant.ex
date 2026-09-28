defmodule BeamPM.FerroplanBridge.GraphInvariant do
  @moduledoc "Bounded GraphInvariant primitive for the Ferroplan provider composition runtime."
  def no_failed_edge?(edges,failed), do: Enum.all?(edges,&(Map.get(&1,:id)!=failed))
end
