defmodule BeamPM.ResearchRuntime.Replay do
  @moduledoc false
  def decision(r), do: {r.subject,r.policy,r.edge}
end
