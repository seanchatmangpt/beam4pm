defmodule BeamPM.FerroplanBridge.ExecutionEnvelope do
  @moduledoc "Bounded ExecutionEnvelope primitive for the Ferroplan provider composition runtime."
  def new(subject,evidence,epoch), do: %{subject:subject,evidence:evidence,epoch:epoch,status: :candidate}
end
