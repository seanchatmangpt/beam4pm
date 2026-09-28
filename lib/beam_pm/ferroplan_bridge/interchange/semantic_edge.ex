defmodule BeamPM.FerroplanBridge.SemanticEdge do
  @enforce_keys [:id, :capability, :provider, :consequence]
  defstruct [:id, :capability, :provider, :consequence, enabled: true]
  def eligible?(%__MODULE__{enabled: true, capability: c}, c), do: true
  def eligible?(_, _), do: false
end
