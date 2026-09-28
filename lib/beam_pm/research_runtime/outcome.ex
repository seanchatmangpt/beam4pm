defmodule BeamPM.ResearchRuntime.Outcome do
  @moduledoc false
  def ok(v), do: {:ok,v}
  def fail(k,r) when k in [:local,:edge,:refused,:timeout], do: {:error,{k,r}}
end
