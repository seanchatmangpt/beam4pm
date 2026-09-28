defmodule BeamPM.FerroplanBridge.RecoveryReceipt do
  @enforce_keys [:subject, :failed_edge, :replacement_edge, :provider]
  defstruct [:subject, :failed_edge, :replacement_edge, :provider]
  def new(subject, failed, replacement), do: %__MODULE__{subject: subject, failed_edge: failed.id, replacement_edge: replacement.id, provider: replacement.provider}
end
