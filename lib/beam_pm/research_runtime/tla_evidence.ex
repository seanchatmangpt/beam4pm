defmodule BeamPM.ResearchRuntime.TlaEvidence do
  @moduledoc false
  def consume(%{subject_sha:s,counterexample:nil}) when is_binary(s), do: {:ok,:no_counterexample}
  def consume(%{counterexample:c}), do: {:error,{:counterexample,c}}
  def consume(_), do: {:error,:unknown}
end
