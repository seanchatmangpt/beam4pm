defmodule BeamPM.ResearchRuntime.POWL do
  @moduledoc false
  defstruct [:id,steps:[],partial_order:[]]
  def ready(p,d), do: Enum.filter(p.steps,fn s->Enum.all?(for {a,b}<-p.partial_order,b==s,do:a,&MapSet.member?(d,&1)) end)
end
