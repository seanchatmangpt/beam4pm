defmodule BeamPM.FerroplanBridge.FondRecovery do
  alias BeamPM.FerroplanBridge.EdgeSet
  def recover(edges, failed, capability), do: edges |> EdgeSet.exclude(failed) |> EdgeSet.select(capability)
end
