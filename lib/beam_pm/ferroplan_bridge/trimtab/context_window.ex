defmodule BeamPM.FerroplanBridge.ContextWindow do
  def fit(items, budget) do
    {kept, _} = items |> Enum.sort_by(&Map.get(&1, :salience, 0), :desc) |> Enum.reduce({[], budget}, fn x, {acc, left} -> t = Map.get(x, :tokens, 0); if t <= left, do: {[x | acc], left - t}, else: {acc, left} end)
    Enum.reverse(kept)
  end
end
