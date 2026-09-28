defmodule BeamPM.ResearchRuntime.Failure do
  @moduledoc false
  def classify({:error,{k,r}}) when k in [:local,:edge,:refused,:timeout], do: {k,r}
  def classify(x), do: {:unknown,x}
end
