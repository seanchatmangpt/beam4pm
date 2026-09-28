defmodule BeamPM.FerroplanBridge.PromotionPolicy do
  @moduledoc "Bounded PromotionPolicy primitive for the Ferroplan provider composition runtime."
  def decide(delta,min) when delta >= min, do: :promote
  def decide(_, _), do: :refuse
end
