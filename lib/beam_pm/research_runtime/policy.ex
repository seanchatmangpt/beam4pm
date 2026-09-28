defmodule BeamPM.ResearchRuntime.Policy do
  @moduledoc false
  defstruct [:id,order:[],max_attempts:3]
  def next(%__MODULE__{order:o},g), do: Enum.find(o,fn id->Enum.any?(BeamPM.ResearchRuntime.Graph.available(g),&(&1.id==id)) end)
end
