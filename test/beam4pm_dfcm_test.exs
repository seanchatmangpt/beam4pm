defmodule BeamPM.DfcmTest do
  use ExUnit.Case, async: true

  alias BeamPM.Dfcm

  @fixture_dir Path.expand("../qualification/fixtures/dfcm", __DIR__)

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

  test "allocate_options allocates capacity across surviving options without DO authority" do
    result = Dfcm.allocate_options(Dfcm.benchmark())

    assert result.authority_ceiling == :select
    assert is_list(result["allocations"])
    assert length(result["allocations"]) >= 2
    assert Enum.all?(result["allocations"], &(&1["standing"] == "ADMITTED"))
  end

  test "preserves option entropy across non-dominated branches" do
    # When multiple non-dominated branches are active, option entropy is conserved
    problem = %{
      options: [
        %{id: "B1", goal_progress: 5, reversibility: :reversible, reuse: 3},
        %{id: "B2", goal_progress: 6, reversibility: :reversible, reuse: 2},
        %{id: "B3", goal_progress: 4, reversibility: :reversible, reuse: 4}
      ]
    }

    result = Dfcm.allocate_options(problem)
    assert result.authority_ceiling == :select
    assert result["total_option_value_preserved"] > 0.0
    assert result["entropy"] > 0.0

    allocations = result["allocations"]
    assert length(allocations) == 3

    # Total allocated fraction sums to 1.0 (option mass preserved)
    sum_fractions = Enum.reduce(allocations, 0.0, fn a, acc -> acc + a["allocated_fraction"] end)
    assert_in_delta sum_fractions, 1.0, 1.0e-5
  end

  test "rarity funding on deceptive traps preserves non-greedy exploration branch" do
    # Deceptive trap scenario:
    # Trap option has immediate high goal progress but irreversible loss
    # Latent breakthrough option has lower immediate progress but high information gain and reversibility
    problem = %{
      options: [
        %{
          id: "deceptive_trap",
          goal_progress: 9,
          reversibility: :irreversible,
          irreversible_loss: 5,
          information_gain: 0,
          reuse: 1
        },
        %{
          id: "rare_latent_breakthrough",
          goal_progress: 3,
          reversibility: :reversible,
          irreversible_loss: 0,
          information_gain: 8,
          reuse: 7
        }
      ]
    }

    # Neither option dominates the other, so both are preserved in the non-dominated set
    cycle_result = Dfcm.cycle(problem)
    assert "deceptive_trap" in cycle_result.nondominated_options
    assert "rare_latent_breakthrough" in cycle_result.nondominated_options

    # Allocation preserves funding to the rare latent breakthrough branch rather than collapsing to trap
    allocation = Dfcm.allocate_options(problem)
    assert allocation.authority_ceiling == :select

    rare_alloc =
      Enum.find(allocation["allocations"], &(&1["branch_id"] == "rare_latent_breakthrough"))

    assert rare_alloc != nil
    assert rare_alloc["allocated_fraction"] > 0.0
    assert rare_alloc["standing"] == "ADMITTED"
  end

  test "strict adherence to :select authority ceiling across all API returns (no DO or actuation)" do
    assert Dfcm.authority_ceiling() == :select

    # Cycle with observation
    cycle_obs = Dfcm.cycle(Dfcm.benchmark())
    assert cycle_obs.authority_ceiling == :select
    assert cycle_obs.decision.authority_ceiling == :select
    refute Map.has_key?(cycle_obs, :execute)
    refute Map.has_key?(cycle_obs, :actuate)
    refute Map.has_key?(cycle_obs, :do)

    # Cycle with select decision
    cycle_sel = Dfcm.cycle(Dfcm.observe(Dfcm.benchmark(), :x, :positive))
    assert cycle_sel.authority_ceiling == :select
    assert cycle_sel.decision.authority_ceiling == :select
    refute cycle_sel.decision.kind == :do
    refute cycle_sel.decision.kind == :actuate

    # Policy
    policy = Dfcm.policy(Dfcm.benchmark())
    assert policy.authority_ceiling == :select
    refute Map.has_key?(policy, :do)

    # Allocation
    alloc = Dfcm.allocate_options(Dfcm.benchmark())
    assert alloc.authority_ceiling == :select
    refute Map.has_key?(alloc, :do)
  end

  test "proper handling of 1 to 8 candidate branches" do
    for count <- 1..8 do
      options =
        for i <- 1..count do
          %{
            id: "branch_#{i}",
            goal_progress: i,
            reversibility: :reversible,
            reuse: 1
          }
        end

      problem = %{options: options}
      cycle_res = Dfcm.cycle(problem)
      assert length(cycle_res.preserved_options) == count
      assert cycle_res.authority_ceiling == :select

      alloc_res = Dfcm.allocate_options(problem)
      assert alloc_res.authority_ceiling == :select
      assert is_list(alloc_res["allocations"])
      assert length(alloc_res["allocations"]) >= 1
      assert length(alloc_res["allocations"]) <= count
    end
  end

  test "Dfcm runs standalone AutoFDE Typer binary in priv/bin/autofde" do
    assert Dfcm.autofde_cli_available?()

    assert {:ok, %{domains: domains, solvers: solvers}} = Dfcm.catalog()
    assert length(domains) == 33
    assert length(solvers) == 58
    assert "GymDomain" in domains
    assert "Astar" in solvers

    intended_phases = [
      "freedom_gym.meeting_phase.open",
      "freedom_gym.meeting_phase.trust_god",
      "freedom_gym.meeting_phase.clean_house",
      "freedom_gym.meeting_phase.help_others",
      "freedom_gym.meeting_phase.fellowship",
      "freedom_gym.meeting_phase.close"
    ]

    deviant_log = Path.expand("../qualification/gym_bridge/deviant_ocel_events.json", __DIR__)
    assert {:ok, resp} = Dfcm.ocel_conformance(deviant_log, %{"e2e-deviant-1" => intended_phases})
    assert resp["all_conform"] == false
    assert resp["overall_fitness"] < 1.0
  end

  test "Dfcm executes native Praxis GraphLaw WASM engine via standalone AutoFDE bridge" do
    sample_ttl = """
    @prefix ex: <http://example.org/> .
    ex:item1 ex:val "test" .
    """

    # 1. Deterministic canonical BLAKE3 graph hash
    assert {:ok, hash} = Dfcm.graphlaw_hash(sample_ttl)
    assert byte_size(hash) == 64

    # 2. Native GraphLaw validation (SHACL, ShEx, Datalog, N3 denials)
    assert {:ok, val_res} = Dfcm.graphlaw_validate(sample_ttl)
    assert val_res["action"] == "validate"
    assert val_res["conforms"] == true
    assert val_res["graph_hash"] == hash

    # 3. Knowledge Hooks execution
    event_ttl = """
    @prefix ex: <http://example.org/> .
    ex:item1 ex:event "fired" .
    """
    assert {:ok, hook_res} = Dfcm.graphlaw_hooks(sample_ttl, event_ttl)
    assert hook_res["status"] == "ADMITTED"
  end
end

