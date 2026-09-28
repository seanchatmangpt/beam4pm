defmodule BeamPM.FerroplanBridge.SurvivalEvidence do
  def score(results) when is_list(results) do
    total = length(results)
    if total == 0, do: 0.0, else: Enum.count(results, &(&1 == :survived)) / total
  end
end
