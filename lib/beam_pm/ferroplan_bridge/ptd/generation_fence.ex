defmodule BeamPM.FerroplanBridge.GenerationFence do
  def admit(%{subject: s, generation: g}, %{subject: s, generation: g}), do: :ok
  def admit(_, _), do: {:error, :generation_drift}
end
