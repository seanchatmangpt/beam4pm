defmodule BeamPM.ResearchRuntime.OCEL do
  @moduledoc false
  def event(t,o,a \\ %{}), do: %{id:BeamPM.ResearchRuntime.Idempotency.key(o,{t,a}),type:t,objects:o,attrs:a}
end
