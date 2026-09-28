defmodule BeamPM.FerroplanBridge.ConsumerBoundary do
  @moduledoc "Bounded ConsumerBoundary primitive for the Ferroplan provider composition runtime."
  def request(subject,capability), do: %{subject:subject,capability:capability,authority: :none}
end
