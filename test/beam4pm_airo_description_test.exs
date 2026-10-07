defmodule BeamPM.AiroDescriptionTest do
  @moduledoc """
  W634 court for beam4pm's AIRo risk description (`priv/airo_risk_description.ttl`).

  Chicago-style: real files, real hashing, real filesystem checks — no mocks.
  Asserts:

    1. the TTL exists and is structurally sound (prefixes, statement
       termination, every block subject-typed, balanced object lists);
    2. every `airo:` term used is declared in the W600-vendored AIRo v1.0
       vocabulary (sha256 pinned to the w600 receipt);
    3. every cited repository path exists on disk;
    4. the mapped individuals are present (1 AISystem, 3 risks, 3 risk
       sources, 4 risk controls, 3 consequences, 3 impacts);
    5. likelihood/severity are stated via the declared AIRo classes;
    6. this lane introduced no `Map.update/4` call (OS-20 hazard guard),
       checked without embedding the literal pattern in this source.
  """

  use ExUnit.Case, async: true

  @ttl "priv/airo_risk_description.ttl"
  @vocab "/Users/sac/xaas/priv/semantic/airo/airo.ttl"
  @vocab_sha "6274d2d8711e046cf38f1b5b2980188094d4aa87b5af79804005a06468fd8469"

  @cited_paths [
    "lib/beam4pm_rust4pm.ex",
    "lib/beam4pm_discovery.ex",
    "lib/beam4pm_pro_simulation.ex",
    "lib/beam4pm_art72_conformance.ex",
    "test/beam4pm_art72_conformance_test.exs",
    "test/beam4pm_w601_map_update_dual_safe_test.exs",
    "scripts/gate_authorship_check.sh",
    "test/beam4pm_authorship_gate_test.exs"
  ]

  @expected_subjects %{
    "bpm:ProcessMiningEngine" => 1,
    "bpm:Risk-ConformanceMetricMismatch" => 1,
    "bpm:Risk-SilentAggregationDrift" => 1,
    "bpm:Risk-EvidenceChainShaDrift" => 1,
    "bpm:RiskSource-OTP29MapUpdateDeviation" => 1,
    "bpm:RiskSource-ConformanceSplit" => 1,
    "bpm:RiskSource-GeneratedArtifactDrift" => 1,
    "bpm:RiskControl-DualSafeMapUpdatePatches" => 1,
    "bpm:RiskControl-Art72Conformance" => 1,
    "bpm:RiskControl-AuthorshipGate" => 1,
    "bpm:RiskControl-FullTestSuite" => 1,
    "bpm:Consequence-MisleadingConformanceVerdicts" => 1,
    "bpm:Consequence-CorruptedAggregates" => 1,
    "bpm:Consequence-UntrustworthyEvidence" => 1,
    "bpm:Impact-WrongComplianceDecision" => 1,
    "bpm:Impact-WrongProcessInsights" => 1,
    "bpm:Impact-LostProvenance" => 1
  }

  defp ttl, do: File.read!(@ttl)
  defp strip_comments(text), do: text |> String.split("\n") |> Enum.reject(&String.starts_with?(&1, "#")) |> Enum.join("\n")
  defp strip_prefixes(text), do: text |> String.split("\n") |> Enum.reject(&String.starts_with?(&1, "@prefix")) |> Enum.join("\n")

  test "TTL exists and declares the required prefixes" do
    assert File.exists?(@ttl)
    text = ttl()
    for p <- ["airo:", "bpm:", "rdfs:"] do
      assert text =~ "@prefix #{p}"
    end
  end

  test "every statement block has a subject and a terminating dot" do
    blocks =
      ttl() |> strip_comments() |> strip_prefixes() |> String.split("\n\n", trim: true)
      |> Enum.reject(&(&1 == "" or &1 =~ ~r/^\s+$/))

    assert length(blocks) >= 20
    for b <- blocks do
      lines = b |> String.split("\n") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
      # first line is a subject token (prefixed name, not a predicate object)
      assert hd(lines) =~ ~r/^(airo|bpm|rdfs):[A-Za-z][A-Za-z0-9_-]*/,
             "block lacks a subject: #{inspect(hd(lines))}"
      # terminates
      assert List.last(lines) =~ ~r/\.\s*$/
      # has at least one type triple
      assert b =~ ~r/\ba (airo:[A-Za-z]+|owl:(Class|ObjectProperty))\b/
    end
  end

  test "vocabulary copy matches the w600 sha256 pin and defines every airo: term used" do
    assert File.exists?(@vocab), "vendored AIRo vocabulary missing at #{@vocab}"
    assert :crypto.hash(:sha256, File.read!(@vocab)) == Base.decode16!(@vocab_sha, case: :lower)

    vocab = File.read!(@vocab)
    used =
      Regex.scan(~r/\bairo:([A-Za-z][A-Za-z0-9_]*)/, ttl() |> strip_comments())
      |> Enum.map(&Enum.at(&1, 1))
      |> Enum.uniq()

    assert length(used) >= 15
    for term <- used do
      assert vocab =~ "airo:#{term}",
             "airo:#{term} used in description but absent from the AIRo v1.0 vocabulary"
    end
  end

  test "every cited repository path exists" do
    for p <- @cited_paths do
      assert File.exists?(p), "cited path does not exist: #{p}"
    end
  end

  test "mapped individuals are present" do
    text = ttl()
    for {subject, _} <- @expected_subjects do
      assert text =~ subject
    end
    # exactly the declared cardinalities
    assert Enum.count(Regex.scan(~r/a airo:AISystem ;/, text)) == 1
    assert Enum.count(Regex.scan(~r/a airo:Risk ;/, text)) == 3
    assert Enum.count(Regex.scan(~r/a airo:RiskSource ;/, text)) == 3
    assert Enum.count(Regex.scan(~r/a airo:RiskControl ;/, text)) == 4
    assert Enum.count(Regex.scan(~r/a airo:Consequence ;/, text)) == 3
    assert Enum.count(Regex.scan(~r/a airo:Impact ;/, text)) == 3
  end

  test "likelihood and severity are stated via declared AIRo classes" do
    text = ttl()
    for edge <- ["airo:hasLikelihood", "airo:hasSeverity"] do
      assert text =~ edge
    end
    assert Enum.count(Regex.scan(~r/a airo:Likelihood ;/, text)) == 3
    assert Enum.count(Regex.scan(~r/a airo:Severity ;/, text)) == 3
  end

  test "risk controls are wired to their risk sources and risks" do
    text = strip_comments(ttl())
    # 1 declaration + 3 uses each
    assert Enum.count(Regex.scan(~r/airo:detectsRiskConcept\b/, text)) == 4
    assert Enum.count(Regex.scan(~r/airo:isRiskSourceFor\b/, text)) == 4
    # 1 declaration + at least one use per control (4 controls)
    assert Enum.count(Regex.scan(~r/airo:mitigatesRiskConcept\b/, text)) >= 5
  end

  test "no Map.update call was introduced by this lane (OS-20 hazard guard)" do
    pattern = "Map." <> "update("
    # the TTL mentions Map.update/4 in prose strings; check code positions only
    ttl_code =
      ttl()
      |> strip_comments()
      |> String.split("\n")
      |> Enum.reject(&(&1 =~ ~r/rdfs:(comment|label|seeAlso)/ or &1 =~ ~r/^\s*"/))
      |> Enum.join("\n")

    refute ttl_code =~ pattern, "OS-20 hazard: new Map.update/4 call in #{@ttl}"

    test_src = File.read!(__ENV__.file) |> strip_comments()
    refute test_src =~ pattern, "OS-20 hazard: new Map.update/4 call in #{__ENV__.file}"
  end
end
