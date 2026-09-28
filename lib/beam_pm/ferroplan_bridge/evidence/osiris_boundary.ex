defmodule BeamPM.FerroplanBridge.OsirisBoundary do
  @moduledoc "Bounded OsirisBoundary primitive for the Ferroplan provider composition runtime."
  def bound(ctx,max), do: Enum.take(ctx,-max)
end
