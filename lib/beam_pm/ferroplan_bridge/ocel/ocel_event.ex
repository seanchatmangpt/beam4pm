defmodule BeamPM.FerroplanBridge.OcelEvent do
  @moduledoc "Bounded OcelEvent primitive for the Ferroplan provider composition runtime."
  def new(type,objects), do: %{type:type,objects:objects}
end
