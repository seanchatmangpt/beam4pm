defmodule BeamPM.FerroplanBridge.PolyEvidence do
  @moduledoc "Bounded PolyEvidence primitive for the Ferroplan provider composition runtime."
  def combine(xs), do: %{evidence:xs,digest: Base.encode16(:crypto.hash(:sha256,:erlang.term_to_binary(xs)),case: :lower)}
end
