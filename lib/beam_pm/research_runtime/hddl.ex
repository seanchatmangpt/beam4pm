defmodule BeamPM.ResearchRuntime.HDDL do
  @moduledoc false
  defstruct [:task,:methods]
  def methods_for(h,s), do: Enum.filter(h.methods,fn m->m.precondition.(s) end)
end
