defmodule BeamPM.FerroplanBridge.PlannerBinding do
  def bind(%{id: id, authority: :none}, planner, capability), do: %{intent_id: id, planner: planner, capability: capability, authority: :none}
end
