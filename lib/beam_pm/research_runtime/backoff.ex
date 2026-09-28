defmodule BeamPM.ResearchRuntime.Backoff do
  @moduledoc false
  def delay(a,b \\ 25,c \\ 2000), do: min(c,trunc(b*:math.pow(2,max(a-1,0))))
end
