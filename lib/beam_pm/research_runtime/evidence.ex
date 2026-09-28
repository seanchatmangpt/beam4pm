defmodule BeamPM.ResearchRuntime.Evidence do
  @moduledoc false
  def admit(%{source_sha:s,witness:w,falsifier:f}) when is_binary(s) and not is_nil(w) and not is_nil(f), do: :ok
  def admit(_), do: {:refused,:incomplete_evidence}
end
