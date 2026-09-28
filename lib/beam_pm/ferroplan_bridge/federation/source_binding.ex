defmodule BeamPM.FerroplanBridge.SourceBinding do
  @moduledoc "Bounded SourceBinding primitive for the Ferroplan provider composition runtime."
  def bind(id,uri,digest), do: %{id:id,uri:uri,digest:digest}
end
