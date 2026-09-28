defmodule BeamPM.FerroplanBridge.Replay do
  @moduledoc "Bounded Replay primitive for the Ferroplan provider composition runtime."
  def route(%{edge: e},edges), do: Enum.find(edges,&(Map.get(&1,:id)==e))
end
