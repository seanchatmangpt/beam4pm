defmodule BeamPM.FerroplanBridge.ModelRole do
  @moduledoc "Bounded ModelRole primitive for the Ferroplan provider composition runtime."
  def permissions, do: %{context:true,select:false,construct:false,do:false}
end
