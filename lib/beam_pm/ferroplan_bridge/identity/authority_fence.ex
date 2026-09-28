defmodule BeamPM.FerroplanBridge.AuthorityFence do
  @rank %{none: 0, observe: 1, construct: 2, do: 3}
  def require(granted, needed) when is_map_key(@rank, granted) and is_map_key(@rank, needed) do
    if @rank[granted] >= @rank[needed], do: :ok, else: {:error, {:refused_authority, needed}}
  end
end
