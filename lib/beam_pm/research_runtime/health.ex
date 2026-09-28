defmodule BeamPM.ResearchRuntime.Health do
  @moduledoc false
  defstruct failures:0,successes:0,circuit: :closed
  def success(h), do: %{h|successes:h.successes+1}
  def failure(h,l \\ 3), do: %{h|failures:h.failures+1,circuit:if(h.failures+1>=l,do: :open,else:h.circuit)}
end
