defmodule BeamPM.FerroplanBridge.SurvivalEvidence do
  @moduledoc "Bounded SurvivalEvidence primitive for the Ferroplan provider composition runtime."
  def score(xs), do: Enum.count(xs,&(&1==:survived)) / max(length(xs),1)
end
