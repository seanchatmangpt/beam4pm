defmodule BeamPM.FerroplanBridge.ContextWindow do
  @moduledoc "Bounded ContextWindow primitive for the Ferroplan provider composition runtime."
  def fit(items,max), do: Enum.take(items,-max)
end
