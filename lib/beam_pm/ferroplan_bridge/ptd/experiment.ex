defmodule BeamPM.FerroplanBridge.Experiment do
  @moduledoc "Bounded Experiment primitive for the Ferroplan provider composition runtime."
  def pair(a,b), do: %{baseline:a,phased:b,same_semantics: Map.get(a,:semantics)==Map.get(b,:semantics)}
end
