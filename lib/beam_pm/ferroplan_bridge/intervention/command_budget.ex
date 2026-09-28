defmodule BeamPM.FerroplanBridge.CommandBudget do
  @moduledoc "Bounded CommandBudget primitive for the Ferroplan provider composition runtime."
  def consume(%{used: u,budget: b}=x) when u < b, do: {:ok, Map.put(x,:used,u+1)}
  def consume(_), do: {:error,:budget_exhausted}
end
