defmodule BeamPM.FerroplanBridge.OcelEvent do
  @enforce_keys [:id, :type, :time, :objects]
  defstruct [:id, :type, :time, :objects, attributes: %{}]
  def new(id, type, time, objects), do: %__MODULE__{id: id, type: type, time: time, objects: Enum.sort(objects)}
end
