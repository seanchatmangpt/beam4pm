defmodule BeamPM.ResearchRuntime.Capability do
  @moduledoc false
  defstruct [:name,constraints:%{}]
  def satisfies?(%__MODULE__{constraints:r},o), do: Enum.all?(r,fn {k,v}->Map.get(o,k)==v end)
end
