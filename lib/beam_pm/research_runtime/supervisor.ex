defmodule BeamPM.ResearchRuntime.Supervisor do
  @moduledoc false
  use Supervisor
  def start_link(o \\ []), do: Supervisor.start_link(__MODULE__,o,name:__MODULE__)
  def init(_), do: Supervisor.init([{BeamPM.ResearchRuntime.ProviderRegistry,[]}],strategy: :rest_for_one)
end
