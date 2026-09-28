defmodule BeamPM.FerroplanBridge.SemanticPart do
  @moduledoc "Bounded SemanticPart primitive for the Ferroplan provider composition runtime."
  def new(id,consequence), do: %{id:id,consequence:consequence}
end
