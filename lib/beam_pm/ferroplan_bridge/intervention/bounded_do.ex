defmodule BeamPM.FerroplanBridge.BoundedDo do
  @moduledoc "Bounded BoundedDo primitive for the Ferroplan provider composition runtime."
  def authorize(order) do
    case BeamPM.FerroplanBridge.CommandBudget.consume(order) do {:ok,o}->{:ok,o}; e->e end
  end
end
