defmodule BeamPM.FerroplanBridge.ProviderAdapter do
  @moduledoc "Bounded ProviderAdapter primitive for the Ferroplan provider composition runtime."
  def normalize({:ok,x}), do: {:ok,x}
  def normalize({:error,r}), do: {:error,{:provider,r}}
end
