defmodule BeamPM.FerroplanBridge.CommandTopology do
  @moduledoc "Bounded CommandTopology primitive for the Ferroplan provider composition runtime."
  def distribute(intent,planners), do: Enum.map(planners,&%{intent:intent,planner:&1})
end
