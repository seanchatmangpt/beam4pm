defmodule BeamPM.FerroplanBridge.Epoch do
  @moduledoc "Bounded Epoch primitive for the Ferroplan provider composition runtime."
  def next(%{id: id,generation: g}), do: %{id:id,generation:g+1}
end
