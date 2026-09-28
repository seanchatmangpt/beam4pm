defmodule BeamPM.FerroplanBridge.GenerationFence do
  @moduledoc "Bounded GenerationFence primitive for the Ferroplan provider composition runtime."
  def admit(%{generation: g}, g), do: :ok
  def admit(_, _), do: {:error,:stale_generation}
end
