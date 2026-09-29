defmodule BeamPM.FerroplanBridge.RacapPair do
  def delta(%{control: c, candidate: k, same_subject: true}) when is_number(c) and is_number(k), do: {:ok, k - c}
  def delta(_), do: {:error, :subject_drift}
end
