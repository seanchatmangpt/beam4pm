defmodule BeamPM.FerroplanBridge.RacapPair do
  @moduledoc "Bounded RacapPair primitive for the Ferroplan provider composition runtime."
  def delta(%{candidate: c, control: k}), do: c-k
end
