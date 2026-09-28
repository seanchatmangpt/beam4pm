defmodule BeamPM.FerroplanBridge.Coordinator do
  @moduledoc "Bounded Coordinator primitive for the Ferroplan provider composition runtime."
  def failover(edges,failed), do: BeamPM.FerroplanBridge.FondRecovery.recover(edges,failed)
end
