defmodule BeamPM.ResearchRuntime.Idempotency do
  @moduledoc false
  def key(s,o), do: :crypto.hash(:sha256,:erlang.term_to_binary({s,o}))|>Base.encode16(case: :lower)
end
