defmodule BeamPM.FerroplanBridge.QueryContract do
  @enforce_keys [:id, :requires, :returns]
  defstruct [:id, :requires, :returns]
  def supports?(%__MODULE__{returns: fields}, requested), do: Enum.all?(requested, &(&1 in fields))
end
