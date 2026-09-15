defmodule BeamPM.DfcmTest do
  use ExUnit.Case, async: true

  alias BeamPM.Dfcm

  @fixture_dir Path.expand("fixtures/dfcm", __DIR__)

  test "HDDL order is preserve through select and never DO" do
    assert Dfcm.phase_order() == [
             :preserve,
             :fence,
             :calculus,
             :exclusions,
             :falsifier,
             :extension,
             :construct_contingent_policy,
             :select
           ]

    assert Dfcm.authority_ceiling() == :select
  end

  test "unknown or inconclusive X preserves A B C and requests observation" do
    result = Dfcm.cycle(Dfcm.benchmark())

    assert result.preserved_options == ["A", "B", "C"]
    assert result.excluded_options == []
    assert result.pending_observations == [:x]
    assert result.decision.kind == :observe
    assert result.decision.observation == :x
    assert result.authority_ceiling == :select
    assert result.fond_policy.kind == :strong_cyclic
    assert result.fond_policy.inconclusive_successor == :observe
  end

  test "strong-cyclic policy observes again on inconclusive outcome" do
    policy = Dfcm.policy(Dfcm.benchmark())

    assert policy.kind == :strong_cyclic
    assert policy.fairness == :eventual_conclusive_observation
    assert policy.branches.inconclusive.kind == :observe
    assert policy.branches.inconclusive.observation == :x
    assert policy.authority_ceiling == :select
  end

  test "positive X admits C to selection without granting DO" do
    result =
      Dfcm.benchmark()
      |> Dfcm.observe(:x, :positive)
      |> Dfcm.cycle()

    assert result.pending_observations == []
    assert result.decision.kind == :select
    assert result.decision.selected_option == "C"
    assert result.decision.authority_ceiling == :select
  end

  test "negative X excludes C with receipt and falsifier then selects B" do
    result =
      Dfcm.benchmark()
      |> Dfcm.observe(:x, :negative)
      |> Dfcm.cycle()

    assert result.decision.kind == :select
    assert result.decision.selected_option == "B"

    exclusion = Enum.find(result.excluded_options, &(&1.option_id == "C"))
    assert exclusion.reason == {:observation_disables, :x, :negative}
    assert exclusion.falsifier == {:observation_is, :x, :positive}
    assert is_binary(exclusion.receipt_hash)
    assert byte_size(exclusion.receipt_hash) == 64
  end

  test "lower immediate cost cannot dominate a more reversible option by itself" do
    [a, b, _c] = Dfcm.benchmark().options

    refute Dfcm.dominates?(a, b)
  end

  test "failed or fenced edge does not collapse the graph" do
    problem =
      Dfcm.benchmark()
      |> Map.put(:observations, %{x: :negative})
      |> Map.put(:fences, [
        %{
          id: :b_blocked,
          excludes: ["B"],
          evidence: {:standing, "B", :blocked},
          falsifier: {:standing_changes, "B"}
        }
      ])

    result = Dfcm.cycle(problem)

    assert Enum.any?(result.excluded_options, &(&1.option_id == "B"))
    assert Enum.any?(result.excluded_options, &(&1.option_id == "C"))
    assert result.decision.kind == :select
    assert result.decision.selected_option == "A"
  end

  test "identical admitted state yields deterministic exclusion receipts" do
    problem =
      Dfcm.benchmark()
      |> Map.put(:observations, %{x: :negative})

    assert Dfcm.cycle(problem).excluded_options == Dfcm.cycle(problem).excluded_options
  end

  test "formal fixtures terminate at SELECT and encode FOND recurrence" do
    hddl = File.read!(Path.join(@fixture_dir, "dfcm.hddl"))
    fond = File.read!(Path.join(@fixture_dir, "dfcm-fond.pddl"))
    problem = File.read!(Path.join(@fixture_dir, "abcx-problem.pddl"))

    assert hddl =~ "preserve-known-options"
    assert hddl =~ "select-lawful-option"
    assert hddl =~ "construct-contingent-policy"

    assert fond =~ ":effect (oneof"
    assert fond =~ "clear-inconclusive"
    assert fond =~ "decision-observations-resolved"
    assert problem =~ "(:goal (selection-complete))"

    refute hddl =~ "(:action execute"
    refute hddl =~ "(:action actuate"
    refute fond =~ "(:action execute"
    refute fond =~ "(:action actuate"
  end
end
