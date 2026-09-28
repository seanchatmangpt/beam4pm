defmodule BeamPM.FerroplanBridge.WorkOrder do
  @moduledoc "Bounded WorkOrder primitive for the Ferroplan provider composition runtime."
  def new(id, subject, budget), do: %{id: id, subject: subject, budget: budget, used: 0}
end
