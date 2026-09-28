defmodule BeamPM.ResearchRuntime.State do
  @moduledoc false
  defstruct phase: :bound,graph:nil,policy:nil,attempt:0
  @allowed %{bound:[:admitted],admitted:[:running,:refused],running:[:recovering,:done],recovering:[:running,:done]}
  def transition(s,to), do: if(to in Map.get(@allowed,s.phase,[]),do:{:ok,%{s|phase:to}},else:{:error,:illegal_transition})
end
