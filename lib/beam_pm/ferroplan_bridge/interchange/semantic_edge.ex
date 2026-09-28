defmodule BeamPM.FerroplanBridge.SemanticEdge do
  @moduledoc "Bounded SemanticEdge primitive for the Ferroplan provider composition runtime."
  defstruct [:id, :capability, :provider, enabled: true]
  def eligible?(%__MODULE__{enabled: e, capability: c}, c), do: e
  def eligible?(_, _), do: false
end
