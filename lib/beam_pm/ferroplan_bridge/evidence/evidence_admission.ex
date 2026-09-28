defmodule BeamPM.FerroplanBridge.EvidenceAdmission do
  @moduledoc "Bounded EvidenceAdmission primitive for the Ferroplan provider composition runtime."
  def admit(%{subject_sha: s,evidence_id: e}=x) when is_binary(s) and is_binary(e), do: {:ok,x}
  def admit(_), do: {:error,:unbound_evidence}
end
