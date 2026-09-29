defmodule BeamPM.ResearchRuntime.Router do
  @moduledoc false
  def route(g,p,c), do: with {:ok,e}<-BeamPM.ResearchRuntime.Selector.select(g,p),true<-e.capability==c,do:{:ok,e},else:(false->{:error,:capability_mismatch};x->x)
end
