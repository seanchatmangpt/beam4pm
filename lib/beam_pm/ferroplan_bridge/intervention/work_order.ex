defmodule BeamPM.FerroplanBridge.WorkOrder do
  @enforce_keys [:id, :subject, :capability, :max_attempts]
  defstruct [:id, :subject, :capability, :max_attempts, attempt: 0, authority: :construct]
  def new(id, subject, capability, max_attempts) when max_attempts > 0, do: %__MODULE__{id: id, subject: subject, capability: capability, max_attempts: max_attempts}
  def exhausted?(%__MODULE__{attempt: a, max_attempts: m}), do: a >= m
end
