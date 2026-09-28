defmodule BeamPM.ResearchRuntime.Selector do
  @moduledoc false
  def select(g,p), do: case BeamPM.ResearchRuntime.Policy.next(p,g) do nil->{:error,:no_edge}; id->{:ok,Map.fetch!(g.edges,id)} end
end
