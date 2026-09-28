defmodule BeamPM.FerroplanBridge.PortableContract do
  @enforce_keys [:capability, :abi, :digest]
  defstruct [:capability, :abi, :digest, version: 1]
  def compatible?(a, b), do: a.capability == b.capability and a.abi == b.abi and b.version >= a.version
end
