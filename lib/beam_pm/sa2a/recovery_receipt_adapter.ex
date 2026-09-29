defmodule BeamPM.SA2A.RecoveryReceiptAdapter do
  @moduledoc false

  alias BeamPM.FerroplanBridge.RecoveryReceipt
  alias BeamPM.SA2A.ReplanConsumer

  def from_loop(subject, %{provider: provider, excluded: excluded}, edges)
      when is_list(excluded) and excluded != [] do
    with %{} = failed <- edge_for_provider(edges, List.last(excluded)),
         %{} = replacement <- edge_for_provider(edges, provider) do
      RecoveryReceipt.new(subject, failed, replacement)
    else
      _ -> nil
    end
  end

  def from_loop(_subject, _result, _edges), do: nil

  def edge_for_provider(edges, provider) do
    Enum.find(edges, fn edge ->
      ReplanConsumer.provider_id(Map.get(edge, :provider)) == ReplanConsumer.provider_id(provider)
    end)
  end
end
