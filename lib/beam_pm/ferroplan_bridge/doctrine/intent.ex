defmodule BeamPM.FerroplanBridge.Intent do
  @moduledoc "Bounded Intent primitive for the Ferroplan provider composition runtime."
  def new(goal,constraints), do: %{goal:goal,constraints:constraints}
end
