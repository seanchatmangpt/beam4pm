defmodule BeamPM.ResearchRuntime.Reconciler do
  @moduledoc false
  def reconcile(g,hs), do: Enum.reduce(hs,g,fn {id,h},a->if BeamPM.ResearchRuntime.Circuit.allow?(h),do:a,else:BeamPM.ResearchRuntime.Graph.exclude(a,id) end)
end
