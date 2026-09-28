defmodule BeamPM.ResearchRuntime.Circuit do
  @moduledoc false
  def allow?(%{circuit: :closed}), do: true
  def allow?(_), do: false
end
