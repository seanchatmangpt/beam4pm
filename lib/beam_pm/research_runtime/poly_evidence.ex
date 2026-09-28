defmodule BeamPM.ResearchRuntime.PolyEvidence do
  @moduledoc false
  def pipeline(e,c,v), do: with :ok<-BeamPM.ResearchRuntime.Evidence.admit(e),{:ok,a}<-c.(e),:ok<-v.(a),do:{:ok,a}
end
