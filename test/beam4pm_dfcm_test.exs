defmodule BeamPM.DfcmTest do
  use ExUnit.Case, async: false

  alias BeamPM.Dfcm
  alias BeamPM.Ferroplan

  @fixture_dir Path.expand("../qualification/fixtures/dfcm", __DIR__)

  @planning_domain """
  (define (domain rooms)
    (:requirements :strips :typing)
    (:types room)
    (:predicates (at ?r - room) (link ?a - room ?b - room))
    (:action go
      :parameters (?a - room ?b - room)
      :precondition (and (at ?a) (link ?a ?b))
      :effect (and (at ?b) (not (at ?a)))))
  )
  """

  @planning_problem """
  (define (problem three-room)
    (:domain rooms)
    (:objects a b c - room)
    (:init (at a) (link a b) (link b c) (link c b))
    (:goal (at b)))
  """

  @fond_problem JSON.encode!(%{
                  "states" => [
                    %{"id" => "s0"},
                    %{"id" => "g", "facts" => ["done"]}
                  ],
                  "initial_states" => ["s0"],
                  "goal" => %{"facts" => ["done"]},
                  "transitions" => [
                    %{
                      "action" => "flip",
                      "from" => "s0",
                      "to" => "g",
                      "probability_ppm" => 500_000
                    },
                    %{
                      "action" => "flip",
                      "from" => "s0",
                      "to" => "s0",
                      "probability_ppm" => 500_000
                    }
                  ]
                })

  defp start_ferroplan! do
    case Ferroplan.start() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  defp new_session!(with_plan) do
    start_ferroplan!()
    {:ok, %{"handle" => handle}} = Ferroplan.session_new(@planning_domain, @planning_problem)

    if with_plan do
      {:ok, %{"solved" => true}} = Ferroplan.session_think(handle, 10_000, 64)
    end

    handle
  end

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

  @tag skip: not File.exists?(Dfcm.autofde_cli_path())
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

  @tag skip: not File.exists?(Dfcm.autofde_cli_path())
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

  describe "live DfCM Ferroplan runtime" do
    if not Ferroplan.wasm_built?() do
      @describetag skip: Ferroplan.wasm_missing_reason()
    end

    test "valid suffix is preserved before any new search" do
      handle = new_session!(true)

      assert {:ok, result} =
               Dfcm.observe_and_repair_session(
                 handle,
                 [{"(at a)", true}],
                 event_id: "evt-stable"
               )

      assert result.decision == :reuse_suffix
      assert result.trigger == :none
      assert result.plan_valid == true
      assert result.previous_plan_id == result.plan_id
      assert result.plan_lineage == nil
      assert result.plan_memory.plan_id == result.plan_id
      assert result.dynamic_replan_trigger == nil
      assert result.escalation == []
      assert result.authority_ceiling == :select

      {:ok, %{"freed" => true}} = Ferroplan.session_free(handle)
    end

    test "world drift triggers bounded repair with deterministic lineage and trigger evidence" do
      handle = new_session!(true)

      assert {:ok, before_suffix} = Ferroplan.session_suffix(handle)
      assert before_suffix != []

      assert {:ok, result} =
               Dfcm.observe_and_repair_session(
                 handle,
                 [{"(at a)", false}, {"(at c)", true}],
                 event_id: "evt-drift",
                 evals: 10_000,
                 mem_mb: 64
               )

      assert result.decision in [:replanned_full, :replanned_following]
      assert result.trigger == :invalid_plan
      assert result.plan_valid == false
      assert result.previous_plan_id != nil
      assert result.plan_id != nil
      assert result.plan_lineage.parent_plan_id == result.previous_plan_id
      assert result.plan_lineage.plan_id == result.plan_id
      assert byte_size(result.plan_lineage.lineage_hash) == 64
      assert result.dynamic_replan_trigger.event_id == "evt-drift"
      assert result.dynamic_replan_trigger.plan_id == result.previous_plan_id
      assert byte_size(result.dynamic_replan_trigger.trigger_hash) == 64
      assert result.plan_memory.plan_id == result.plan_id
      assert result.authority_ceiling == :select
      assert {:ok, %{"valid" => true}} = Ferroplan.session_valid?(handle)

      {:ok, %{"freed" => true}} = Ferroplan.session_free(handle)
    end

    test "an observed goal short-circuits repair: goal_met, no search, no escalation" do
      handle = new_session!(true)
      assert {:ok, before_suffix} = Ferroplan.session_suffix(handle)
      assert before_suffix != []

      assert {:ok, result} =
               Dfcm.observe_and_repair_session(
                 handle,
                 [{"(at a)", false}, {"(at b)", true}],
                 event_id: "evt-goal"
               )

      assert result.decision == :goal_met
      assert result.trigger == :goal_met
      assert result.plan_valid == nil
      assert result.previous_suffix == []
      assert result.suffix == []
      assert result.plan == nil
      assert result.plan_id == nil
      assert result.plan_memory == nil
      assert result.plan_lineage == nil
      assert result.dynamic_replan_trigger == nil
      assert result.escalation == []
      assert result.authority_ceiling == :select
      assert {:ok, %{"goal_met" => true}} = Ferroplan.session_goal_met?(handle)

      # goal-met wins even when evidence refuses reuse: nothing is left to reuse.
      assert {:ok, %{decision: :goal_met}} =
               Dfcm.observe_and_repair_session(handle, [{"(at b)", true}],
                 reuse_admissible: false
               )

      {:ok, %{"freed" => true}} = Ferroplan.session_free(handle)
    end

    test "admitted evidence is bound into event, memory, lineage and trigger hashes" do
      run = fn opts, observations ->
        handle = new_session!(true)
        {:ok, result} = Dfcm.observe_and_repair_session(handle, observations, opts)
        {:ok, %{"freed" => true}} = Ferroplan.session_free(handle)
        result
      end

      stable = [{"(at a)", true}]
      plain = run.([], stable)
      ev_a = run.([evidence: %{verdict: :a}], stable)
      ev_a2 = run.([evidence: %{verdict: :a}], stable)
      ev_b = run.([evidence: %{verdict: :b}], stable)

      # Evidence never changes the planning decision on its own ...
      assert Enum.map([plain, ev_a, ev_b], & &1.decision) == List.duplicate(:reuse_suffix, 3)
      assert plain.plan_id == ev_a.plan_id and ev_a.plan_id == ev_b.plan_id
      # ... but it is carried: digest, default event id and memory hash all move.
      assert plain.evidence_digest == nil
      assert "evidence:" <> _ = ev_a.evidence_digest
      assert ev_a.evidence_digest == ev_a2.evidence_digest
      assert ev_a.evidence_digest != ev_b.evidence_digest
      assert ev_a.event_id == ev_a2.event_id
      assert length(Enum.uniq([plain.event_id, ev_a.event_id, ev_b.event_id])) == 3
      assert ev_a.plan_memory == ev_a2.plan_memory

      assert length(
               Enum.uniq([
                 plain.plan_memory.evidence_hash,
                 ev_a.plan_memory.evidence_hash,
                 ev_b.plan_memory.evidence_hash
               ])
             ) == 3

      drift = [{"(at a)", false}, {"(at c)", true}]
      d_a = run.([evidence: %{verdict: :a}, event_id: "evt"], drift)
      d_b = run.([evidence: %{verdict: :b}, event_id: "evt"], drift)
      assert d_a.trigger == :invalid_plan and d_b.trigger == :invalid_plan
      assert d_a.plan_id == d_b.plan_id
      assert d_a.dynamic_replan_trigger.trigger_hash != d_b.dynamic_replan_trigger.trigger_hash
      assert d_a.plan_lineage.lineage_hash != d_b.plan_lineage.lineage_hash
    end

    test "evidence that refuses reuse forces a bounded replan of a still-valid suffix" do
      handle = new_session!(true)
      assert {:ok, previous_suffix} = Ferroplan.session_suffix(handle)

      assert {:ok, result} =
               Dfcm.observe_and_repair_session(handle, [{"(at a)", true}],
                 evidence: %{verdict: :deviant},
                 reuse_admissible: false,
                 event_id: "evt-refuse"
               )

      assert result.decision == :replanned_full
      assert result.trigger == :evidence_refused_reuse
      assert result.plan_valid == true
      assert result.previous_suffix == previous_suffix
      assert result.plan["solved"] == true
      assert result.suffix != []
      assert result.dynamic_replan_trigger.event_id == "evt-refuse"
      assert byte_size(result.dynamic_replan_trigger.trigger_hash) == 64
      assert result.escalation == []
      assert result.authority_ceiling == :select
      assert {:ok, %{"valid" => true}} = Ferroplan.session_valid?(handle)

      {:ok, %{"freed" => true}} = Ferroplan.session_free(handle)
    end

    test "counterfactual probes preserve parent world and parent plan slot" do
      handle = new_session!(false)

      assert {:ok, result} =
               Dfcm.probe_session(
                 handle,
                 [
                   %{id: "baseline", goal: "(at b)"},
                   %{
                     id: "counterfactual-c",
                     goal: "(at b)",
                     observations: [{"(at a)", false}, {"(at c)", true}]
                   },
                   %{
                     id: "unreachable-a",
                     goal: "(at a)",
                     observations: [{"(at a)", false}, {"(at c)", true}]
                   }
                 ],
                 evals: 10_000,
                 mem_mb: 64
               )

      assert result.candidate_count == 3
      assert result.authority_ceiling == :select
      assert result.backend in [:host_forks, :native_forks]

      outcomes =
        Enum.map(result.results, fn candidate ->
          Map.get(candidate, :outcome) || Map.get(candidate, "outcome")
        end)

      assert Enum.at(outcomes, 0) in [:solved, "solved"]
      assert Enum.at(outcomes, 1) in [:solved, "solved"]
      assert Enum.at(outcomes, 2) in [:unsolved, "unsolved"]

      assert {:ok, %{"has_plan" => false}} = Ferroplan.session_has_plan?(handle)
      assert {:ok, %{"value" => true}} = Ferroplan.session_fact(handle, "(at a)")
      assert {:ok, %{"value" => false}} = Ferroplan.session_fact(handle, "(at c)")

      {:ok, %{"freed" => true}} = Ferroplan.session_free(handle)
    end

    test "stale-plan refusal requires explicit identity drift" do
      assert Dfcm.stale_plan_refusal("plan:a", "same", "same") == nil

      refusal = Dfcm.stale_plan_refusal("plan:a", "admitted", "observed")
      assert refusal.plan_id == "plan:a"
      assert refusal.admitted_preimage_hash == "admitted"
      assert refusal.observed_preimage_hash == "observed"
      assert refusal.authority_ceiling == :select
    end
  end

  describe "FOND branch admission on admitted pins (producer lacks fond_validate)" do
    if not Ferroplan.wasm_built?() do
      @describetag skip: Ferroplan.wasm_missing_reason()
    end

    if Code.ensure_loaded?(Ferroplan) and function_exported?(Ferroplan, :fond_validate, 3) do
      @describetag skip: "pinned Ferroplan exposes fond_validate; the validated path is exercised"
    end

    test "a real, well-shaped producer policy is typed unavailable, never admitted" do
      start_ferroplan!()

      assert {:ok, %{"solved" => true} = plan} =
               Ferroplan.fond_policy(@fond_problem, @fond_problem, %{"max_wall_ms" => 0})

      assert Enum.any?(plan["policy"], &(&1["state"] == "s0"))

      for state <- ["s0", "unknown"] do
        assert {:error, :fond_validator_unavailable} =
                 Dfcm.admit_fond_branch(@fond_problem, plan, state)
      end

      # Shape refusal still precedes the missing validator.
      [entry | _] = plan["policy"]

      assert {:error, {:fond_state_ambiguous, "s0", 2}} =
               Dfcm.admit_fond_branch(@fond_problem, %{plan | "policy" => [entry, entry]}, "s0")
    end
  end

  describe "validated FOND branch admission" do
    if not (Code.ensure_loaded?(Ferroplan) and function_exported?(Ferroplan, :fond_validate, 3)) do
      @describetag skip: "pinned Ferroplan does not yet expose fond_validate"
    end

    test "only an independently valid policy becomes a SELECT candidate" do
      start_ferroplan!()

      assert {:ok, %{"solved" => true} = plan} =
               Ferroplan.fond_policy(@fond_problem, @fond_problem, %{"max_wall_ms" => 0})

      assert {:ok, candidate} = Dfcm.admit_fond_branch(@fond_problem, plan, "s0")
      assert candidate.kind == :fond_policy_branch
      assert candidate.state_id == "s0"
      assert candidate.action == "flip"
      assert length(candidate.outcomes) == 2
      assert candidate.guarantee == "STRONG_CYCLIC"
      assert byte_size(candidate.policy_evidence_hash) == 64
      assert candidate.authority_ceiling == :select
    end

    test "policy outcome drift is excluded instead of becoming an action candidate" do
      start_ferroplan!()

      assert {:ok, %{"solved" => true} = plan} =
               Ferroplan.fond_policy(@fond_problem, @fond_problem, %{"max_wall_ms" => 0})

      drifted =
        update_in(
          plan,
          ["policy", Access.at(0), "outcomes", Access.at(0), "probability_ppm"],
          fn _ ->
            400_000
          end
        )

      assert {:error, {:fond_policy_invalid, issues}} =
               Dfcm.admit_fond_branch(@fond_problem, drifted, "s0")

      assert issues != []
    end

    test "an uncovered exact state is typed and never inferred" do
      start_ferroplan!()

      assert {:ok, %{"solved" => true} = plan} =
               Ferroplan.fond_policy(@fond_problem, @fond_problem, %{"max_wall_ms" => 0})

      assert {:error, {:fond_state_uncovered, "unknown"}} =
               Dfcm.admit_fond_branch(@fond_problem, plan, "unknown")
    end
  end

  describe "runtime boundary falsifiers (no engine required)" do
    test "a self-contradictory or malformed delivery is refused before any engine call" do
      # handle 0 is never a live session: a typed refusal here proves the
      # guard fires before Ferroplan is consulted at all.
      assert {:error, {:contradictory_observations, ["(at b)"]}} =
               Dfcm.observe_and_repair_session(0, [{"(at b)", true}, {"(AT  B)", false}])

      assert {:error, {:malformed_observation, 1, {"(at c)", "yes"}}} =
               Dfcm.observe_and_repair_session(0, [{"(at a)", false}, {"(at c)", "yes"}])

      assert {:error, {:malformed_observation, 0, "(at a)"}} =
               Dfcm.observe_and_repair_session(0, ["(at a)"])

      assert {:error, {:malformed_observation, 0, {"", true}}} =
               Dfcm.observe_and_repair_session(0, [{"", true}])
    end

    test "a non-boolean reuse gate is refused before any engine call" do
      for value <- [nil, :no, "false", 0] do
        assert {:error, {:option_refused, :reuse_admissible, ^value}} =
                 Dfcm.observe_and_repair_session(0, [{"(at a)", true}], reuse_admissible: value)
      end
    end

    test "out-of-budget search is refused before observation or repair" do
      for {opts, field, value} <- [
            {[evals: 0], :evals, 0},
            {[evals: 1_000_001], :evals, 1_000_001},
            {[evals: 1.5], :evals, 1.5},
            {[mem_mb: 0], :mem_mb, 0},
            {[mem_mb: 4096], :mem_mb, 4096}
          ] do
        assert {:error, {:budget_refused, ^field, ^value}} =
                 Dfcm.observe_and_repair_session(0, [{"(at a)", true}], opts)

        assert {:error, {:budget_refused, ^field, ^value}} = Dfcm.repair_session(0, opts)

        assert {:error, {:budget_refused, ^field, ^value}} =
                 Dfcm.probe_session(0, [%{id: "x"}], opts)
      end
    end

    test "probe candidates need present, unique ids and well-formed observations" do
      assert {:error, {:probe_candidate_malformed, 1}} =
               Dfcm.probe_session(0, [%{id: "a"}, %{goal: "(at b)"}])

      assert {:error, {:probe_candidate_malformed, 0}} =
               Dfcm.probe_session(0, [%{id: nil}])

      assert {:error, {:probe_candidate_malformed, 0}} =
               Dfcm.probe_session(0, [%{id: "a", observations: [{"(at a)", :maybe}]}])

      assert {:error, {:probe_candidate_duplicate_ids, ["a"]}} =
               Dfcm.probe_session(0, [%{id: "a"}, %{id: :a}, %{id: "b"}])
    end

    test "native repair output outside the closed vocabulary fails closed to escalation" do
      for raw <- [
            %{"decision" => "execute", "trigger" => "none"},
            %{"decision" => "ok", "trigger" => "none"},
            %{"decision" => nil},
            %{"decision" => 7, "trigger" => "invalid_plan"},
            %{"decision" => "reuse_suffix", "trigger" => "actuate"},
            %{}
          ] do
        repair = Dfcm.normalize_native_repair(raw)
        assert repair.decision == :replan_unsolved
        assert repair.trigger == :none
        assert repair.escalation == [:hddl_recompile, :strategic_recompile]
        assert repair.vocabulary_refusal.decision == Map.get(raw, "decision")
        assert repair.authority_ceiling == :select
      end
    end

    test "admitted native repair vocabulary maps exactly and never grants authority" do
      steps = [%{"action" => "GO", "args" => ["C", "B"], "index" => 0}]

      repair =
        Dfcm.normalize_native_repair(%{
          "decision" => "replanned_following",
          "trigger" => "invalid_plan",
          "plan_valid" => false,
          "previous_suffix" => [%{"action" => "GO", "args" => ["A", "B"], "index" => 0}],
          "suffix" => steps,
          "authority_ceiling" => "do"
        })

      assert repair.decision == :replanned_following
      assert repair.trigger == :invalid_plan
      assert repair.vocabulary_refusal == nil
      assert repair.escalation == []
      assert repair.authority_ceiling == :select
      assert repair.plan_lineage.parent_plan_id == repair.previous_plan_id
      assert repair.plan_lineage.plan_id == repair.plan_id

      malformed = Dfcm.normalize_native_repair(%{"decision" => "goal_met", "suffix" => "GO"})
      assert malformed.suffix == []
      assert malformed.plan_id == nil

      assert Dfcm.repair_decisions() == [
               :goal_met,
               :replan_refused,
               :replan_unsolved,
               :replanned_following,
               :replanned_full,
               :reuse_suffix
             ]
    end

    test "FOND policy shape is admitted before validation; ambiguity is never resolved by order" do
      ambiguous = %{
        "policy" => [
          %{"state" => "s0", "action" => "flip", "outcomes" => []},
          %{"state" => "s0", "action" => "stay", "outcomes" => []}
        ]
      }

      assert {:error, {:fond_state_ambiguous, "s0", 2}} =
               Dfcm.admit_fond_branch(@fond_problem, ambiguous, "s0")

      assert {:error, {:fond_policy_malformed, 0}} =
               Dfcm.admit_fond_branch(
                 @fond_problem,
                 %{"policy" => [%{"state" => "s0", "outcomes" => []}]},
                 "s0"
               )

      assert {:error, {:fond_policy_malformed, {:policy_not_a_list, "flip"}}} =
               Dfcm.admit_fond_branch(@fond_problem, %{"policy" => "flip"}, "s0")
    end

    test "an empty identity is never explicit: stale-plan check refuses instead of admitting" do
      assert %{reason: :identity_missing, authority_ceiling: :select} =
               Dfcm.stale_plan_refusal("plan:a", "", "")

      assert %{reason: :identity_missing} = Dfcm.stale_plan_refusal("", "h", "h")
      assert %{reason: :identity_drift} = Dfcm.stale_plan_refusal("plan:a", "h1", "h2")
      assert Dfcm.stale_plan_refusal("plan:a", "h1", "h1") == nil
    end
  end

  describe "live runtime adversarial falsifiers" do
    if not Ferroplan.wasm_built?() do
      @describetag skip: Ferroplan.wasm_missing_reason()
    end

    test "a refused delivery leaves the live world and plan slot untouched" do
      handle = new_session!(true)
      {:ok, suffix} = Ferroplan.session_suffix(handle)

      assert {:error, {:contradictory_observations, _}} =
               Dfcm.observe_and_repair_session(handle, [{"(at a)", false}, {"(at a)", true}])

      assert {:error, {:budget_refused, :evals, 0}} =
               Dfcm.observe_and_repair_session(handle, [{"(at a)", false}], evals: 0)

      # an ungrounded fact is refused by the engine atomically
      assert {:error, {:engine, _}} =
               Dfcm.observe_and_repair_session(handle, [{"(at a)", false}, {"(at zz)", true}])

      assert {:ok, %{"value" => true}} = Ferroplan.session_fact(handle, "(at a)")
      assert {:ok, ^suffix} = Ferroplan.session_suffix(handle)
      assert {:ok, %{"valid" => true}} = Ferroplan.session_valid?(handle)

      {:ok, %{"freed" => true}} = Ferroplan.session_free(handle)
    end

    test "duplicate delivery of one drift event is idempotent" do
      handle = new_session!(true)
      drift = [{"(at a)", false}, {"(at c)", true}]

      assert {:ok, first} = Dfcm.observe_and_repair_session(handle, drift, event_id: "evt-1")
      assert first.trigger == :invalid_plan
      assert first.plan_id != nil

      assert {:ok, second} = Dfcm.observe_and_repair_session(handle, drift, event_id: "evt-1")
      assert second.decision == :reuse_suffix
      assert second.surprises == []
      assert second.plan_id == first.plan_id
      assert second.plan_lineage == nil
      assert second.dynamic_replan_trigger == nil

      {:ok, %{"freed" => true}} = Ferroplan.session_free(handle)
    end

    test "replay on independent forks is byte-identical; delivery order does not change the plan" do
      parent = new_session!(true)
      {:ok, %{"handle" => fork_a}} = Ferroplan.session_fork(parent)
      {:ok, %{"handle" => fork_b}} = Ferroplan.session_fork(parent)
      {:ok, %{"handle" => fork_c}} = Ferroplan.session_fork(parent)

      # forks copy the world, not the stashed plan slot: install the same
      # bounded plan on each so every fork starts from one admitted subject
      for fork <- [fork_a, fork_b, fork_c] do
        assert {:ok, %{"solved" => true}} = Ferroplan.session_think(fork, 10_000, 64)
      end

      drift = [{"(at a)", false}, {"(at c)", true}]
      assert {:ok, a} = Dfcm.observe_and_repair_session(fork_a, drift, event_id: "evt-r")
      assert {:ok, b} = Dfcm.observe_and_repair_session(fork_b, drift, event_id: "evt-r")

      assert {:ok, c} =
               Dfcm.observe_and_repair_session(fork_c, Enum.reverse(drift), event_id: "evt-r")

      assert a.plan_id == b.plan_id
      assert a.dynamic_replan_trigger.trigger_hash == b.dynamic_replan_trigger.trigger_hash
      assert a.plan_memory.memory_hash == b.plan_memory.memory_hash
      assert a.plan_lineage.lineage_hash == b.plan_lineage.lineage_hash

      # reordering is a different delivery (distinct trigger evidence) but the
      # same admitted world, so the repaired plan identity must agree
      assert c.plan_id == a.plan_id
      assert c.suffix == a.suffix
      assert c.dynamic_replan_trigger.trigger_hash != a.dynamic_replan_trigger.trigger_hash

      # the parent world was never touched by any fork
      assert {:ok, %{"value" => true}} = Ferroplan.session_fact(parent, "(at a)")
      assert {:ok, %{"valid" => true}} = Ferroplan.session_valid?(parent)

      for h <- [fork_a, fork_b, fork_c, parent],
          do: {:ok, %{"freed" => true}} = Ferroplan.session_free(h)
    end

    test "a restricted counterfactual is unsolved and cannot leak its restriction to the parent" do
      handle = new_session!(false)

      assert {:ok, result} =
               Dfcm.probe_session(handle, [
                 %{id: "restricted", goal: "(at b)", restrict_contains: "zzz"},
                 %{id: "open", goal: "(at b)"}
               ])

      assert [%{id: "restricted", outcome: :unsolved}, %{id: "open", outcome: :solved}] =
               Enum.map(result.results, &Map.take(&1, [:id, :outcome]))

      assert {:ok, %{"solved" => true}} = Ferroplan.session_think(handle, 10_000, 64)
      {:ok, %{"freed" => true}} = Ferroplan.session_free(handle)
    end
  end
end
