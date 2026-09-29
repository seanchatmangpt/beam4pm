defmodule BeamPM.FerroplanBridge.SourceBinding do
  @enforce_keys [:id, :origin, :digest]
  defstruct [:id, :origin, :digest]
  def bind(id, origin, digest) when origin != "" and digest != "", do: {:ok, %__MODULE__{id: id, origin: origin, digest: digest}}
  def bind(_, _, _), do: {:error, :refused_source}
end
