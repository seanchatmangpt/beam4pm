defmodule BeamPM.FerroplanBridge.PortableContract do
  @moduledoc "Bounded PortableContract primitive for the Ferroplan provider composition runtime."
  def compatible?(%{abi: a},%{abi: a}), do: true
  def compatible?(_, _), do: false
end
