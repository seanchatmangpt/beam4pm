defmodule BeamPM.FerroplanBridge.PolyEvidence do
  def combine(subject, evidence) when is_list(evidence) do
    digest = :crypto.hash(:sha256, :erlang.term_to_binary({subject, evidence})) |> Base.encode16(case: :lower)
    %{subject: subject, evidence: evidence, digest: digest}
  end
end
