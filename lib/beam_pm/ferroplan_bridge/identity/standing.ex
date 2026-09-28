defmodule BeamPM.FerroplanBridge.Standing do
  @moduledoc "Bounded Standing primitive for the Ferroplan provider composition runtime."
  def status([]), do: :unknown
  def status(_), do: :candidate
end
