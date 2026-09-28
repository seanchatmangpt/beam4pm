defmodule BeamPM.FerroplanBridge.QueryContract do
  @moduledoc "Bounded QueryContract primitive for the Ferroplan provider composition runtime."
  def new(query,sources), do: %{query:query,sources:sources}
end
