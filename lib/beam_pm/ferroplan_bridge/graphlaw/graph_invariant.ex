defmodule BeamPM.FerroplanBridge.GraphInvariant do
  def enforce(name, value, check) when is_function(check, 1), do: if(check.(value), do: {:ok, value}, else: {:error, {:invariant, name}})
end
