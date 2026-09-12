defmodule BeamPM.FrontierEvidenceTest do
  use ExUnit.Case, async: true

  test "projects planning evidence without manufacturing DO authority" do
    fragment =
      BeamPM.FrontierEvidence.from_results(
        {:ok, %{"plan" => ["diagnose", "repair"]}},
        {:ok, %{"policy" => %{"observe" => ["retry", "refuse"]}}},
        {:ok, %{"conformant" => true, "fitness" => 1.0}},
        producer_head: "c639d69a1f6591867dbcd96e9832363ce06be0b7",
        standing: "PARTIAL_ALIVE"
      )

    assert fragment.schema == "frontier-evidence/v1"
    assert fragment.producer == "beam4pm"
    assert fragment.authority_ceiling == "SELECT"
    assert fragment.standing == "PARTIAL_ALIVE"
    assert fragment.artifact_hash =~ ~r/^sha256:[0-9a-f]{64}$/
    assert "external_do" in fragment.refused
    refute Map.has_key?(fragment, :authority)
  end

  test "same observed results manufacture the same artifact hash" do
    args = [
      {:ok, %{hddl: :candidate}},
      {:ok, %{fond: :candidate}},
      {:ok, %{conformance: :candidate}}
    ]

    first =
      apply(BeamPM.FrontierEvidence, :from_results, args ++ [[producer_head: "head"]])

    second =
      apply(BeamPM.FrontierEvidence, :from_results, args ++ [[producer_head: "head"]])

    assert first.artifact_hash == second.artifact_hash
  end
end
