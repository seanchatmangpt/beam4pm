defmodule BeamPM.FerroplanBridge.PromotionPolicy do
  alias BeamPM.FerroplanBridge.RacapPair
  def decide(pair, min_delta, survival) do
    with {:ok, delta} <- RacapPair.delta(pair), true <- delta >= min_delta and survival >= 0.5, do: :promote, else: (_ -> :refuse)
  end
end
