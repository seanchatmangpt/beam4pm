defmodule BeamPM.FerroplanBridge.PlannerBinding do
  @moduledoc "Bounded PlannerBinding primitive for the Ferroplan provider composition runtime."
  def bind(intent,planner), do: %{intent:intent,planner:planner,authority: :none}
end
