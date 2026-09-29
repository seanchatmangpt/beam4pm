defmodule BeamPM.FerroplanBridge.Substitution do
  def equivalent?(a, b), do: a.id != b.id and a.capability == b.capability and a.consequence == b.consequence and b.enabled
  def substitute(a, b), do: if(equivalent?(a, b), do: {:ok, b}, else: {:error, :consequence_drift})
end
