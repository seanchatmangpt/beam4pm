defmodule BeamPM.FerroplanBridge.VkgConsumer do
  @moduledoc "Bounded VkgConsumer primitive for the Ferroplan provider composition runtime."
  def request(contract,subject), do: %{contract:contract,subject:subject}
end
