defmodule BeamPM.FerroplanBridge.Epoch do
  @enforce_keys [:subject, :generation, :artifact]
  defstruct [:subject, :generation, :artifact]
  def next(%__MODULE__{} = e, artifact), do: %__MODULE__{e | generation: e.generation + 1, artifact: artifact}
end
