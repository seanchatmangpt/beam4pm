defmodule BeamPM.FerroplanBridge.AuthorityFence do
  @moduledoc "Bounded AuthorityFence primitive for the Ferroplan provider composition runtime."
  def admit(%{authority: a}, a), do: :ok
  def admit(_, _), do: {:error, :authority_refused}
end
