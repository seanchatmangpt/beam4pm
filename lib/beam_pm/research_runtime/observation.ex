defmodule BeamPM.ResearchRuntime.Observation do
  @moduledoc false
  defstruct [:subject,:edge,:outcome,:at]
  def new(s,e,o), do: %__MODULE__{subject:s,edge:e,outcome:o,at:System.system_time(:millisecond)}
end
