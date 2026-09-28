defmodule BeamPM.FerroplanBridge.Substitution do
  @moduledoc "Bounded Substitution primitive for the Ferroplan provider composition runtime."
  def equivalent?(a,b), do: Map.get(a,:consequence) == Map.get(b,:consequence)
end
