defmodule BeamPM.FerroplanBridge.HddlTask do
  @enforce_keys [:name]
  defstruct [:name, methods: []]
  def leaves(%__MODULE__{methods: []} = task), do: [task.name]
  def leaves(%__MODULE__{methods: methods}), do: Enum.flat_map(methods, &leaves/1)
end
