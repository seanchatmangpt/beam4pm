defmodule BeamPM.ResearchRuntime.Trace do
  @moduledoc false
  defstruct events:[]
  def append(t,e), do: %{t|events:[e|t.events]}
  def ordered(t), do: Enum.reverse(t.events)
end
