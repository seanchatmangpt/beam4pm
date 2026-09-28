defmodule BeamPM.FerroplanBridge.RecoveryReceipt do
  @moduledoc "Bounded RecoveryReceipt primitive for the Ferroplan provider composition runtime."
  def new(subject,failed,replacement), do: %{subject:subject,failed_edge:failed,replacement_edge:replacement}
end
