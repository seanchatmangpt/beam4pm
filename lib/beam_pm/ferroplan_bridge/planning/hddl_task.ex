defmodule BeamPM.FerroplanBridge.HddlTask do
  @moduledoc "Bounded HddlTask primitive for the Ferroplan provider composition runtime."
  def new(name,methods), do: %{name:name,methods:methods}
end
