defmodule BeamPM.ResearchRuntime.Scheduler do
  @moduledoc false
  def choose(xs), do: xs|>Enum.sort_by(&{Map.get(&1,:priority,0),Map.get(&1,:id)})|>List.first()
end
