defmodule BeamPM.FerroplanBridge.Steering do
  @moduledoc "Bounded Steering primitive for the Ferroplan provider composition runtime."
  def delta(before,after), do: %{before:before,after:after}
end
