defmodule BeamPM.FerroplanBridge.PowlTrace do
  @moduledoc "Bounded PowlTrace primitive for the Ferroplan provider composition runtime."
  def append(trace,event), do: trace ++ [event]
end
