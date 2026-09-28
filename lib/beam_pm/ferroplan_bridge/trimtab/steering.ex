defmodule BeamPM.FerroplanBridge.Steering do
  def delta(before, after, hint), do: %{before: before, after: after, hint: hint, authority: :none}
end
