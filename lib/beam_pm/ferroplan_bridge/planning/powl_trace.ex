defmodule BeamPM.FerroplanBridge.PowlTrace do
  def ready?(%{after: deps}, done), do: Enum.all?(deps, &MapSet.member?(done, &1))
  def append(trace, event), do: trace ++ [event]
end
