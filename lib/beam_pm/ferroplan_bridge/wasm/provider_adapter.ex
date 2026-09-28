defmodule BeamPM.FerroplanBridge.ProviderAdapter do
  def normalize({:ok, value}, provider), do: {:ok, %{provider: provider, value: value}}
  def normalize({:error, reason}, provider), do: {:error, %{provider: provider, reason: reason}}
  def normalize(other, provider), do: {:error, %{provider: provider, reason: {:invalid_result, other}}}
end
