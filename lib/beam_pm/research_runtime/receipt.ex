defmodule BeamPM.ResearchRuntime.Receipt do
  @moduledoc false
  defstruct [:subject,:policy,:edge,:outcome,:trace_digest]
  def digest(r), do: :crypto.hash(:sha256,:erlang.term_to_binary(r))|>Base.encode16(case: :lower)
end
