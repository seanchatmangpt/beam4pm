defmodule BeamPM.Dfcm.FabricParityTest do
  @moduledoc """
  Parity qualification for the AutoFDE-Lab `fabric match` / `fabric solve`
  bridge (`BeamPM.Dfcm.fabric_match/2`, `fabric_solve/2`) and its
  cross-validation against beam4pm's own ferroplan wasm engine
  (`BeamPM.Ferroplan.hddl_solve/4`, `fond_policy/4`, `plan/4`) over the SAME
  beam4pm-owned fixtures (`qualification/fixtures/dfcm/`).

  Both legs run for real in-process: the lab leg through `priv/bin/autofde`
  (standalone Typer CLI over `~/autofde-lab`), the ferroplan leg through the
  wasmex-hosted engine. A missing collaborator is a NAMED SKIP, never a
  silent pass and never a fake.

  Divergence attribution (recorded, not fixed here):

  * HDDL fixture (`dfcm.hddl` + `dfcm-abcx.hddl`): both engines solve. The
    fabric rollout carries one step per DfCM phase (8); ferroplan's
    UniversalPlan carries 9 policy entries -- one `htn:decompose` plus one
    `htn:exec` per phase -- planning_type `"fond"`, note `"strong FOND fixed
    point"`. Same decomposition, two receipt vocabularies.
  * FOND fixture (`dfcm-fond.pddl` + `abcx-problem.pddl`): the fabric
    honestly refuses (SKD-FABRIC-008 -- no registered FOND-capable domain;
    `PDDLDomain` is deterministic and skdecide's parser merely "recovers"
    from `:non-deterministic`). Ferroplan's raw-text surfaces refuse the
    same fixture too, for ingest-contract reasons: `fond_policy/4` accepts
    only a JSON `PlanningProblem` document (FP_ADAPTER), and `plan/4`'s
    classical parser does not accept `:non-deterministic` (FF version
    limit). Ferroplan's FOND solver itself is alive on this very problem
    family: `hddl_solve` runs it (planning_type `"fond"`) to a strong FOND
    fixed point. No engine today ingests this PDDL-text FOND fixture.
  * Registry pin drift (lab wasm registry `282fae4` vs ferroplan `e90928d`)
    does NOT bind these fabric legs: `fabric match`/`solve` are pure-Python
    scikit-decide paths that never invoke a lab wasm op. The pin is P9's
    ticket.
  """

  use ExUnit.Case, async: false

  alias BeamPM.Dfcm
  alias BeamPM.Ferroplan

  @fixture_dir Path.expand("../qualification/fixtures/dfcm", __DIR__)
  @hddl_domain_path Path.join(@fixture_dir, "dfcm.hddl")
  @hddl_problem_path Path.join(@fixture_dir, "dfcm-abcx.hddl")
  @fond_domain_path Path.join(@fixture_dir, "dfcm-fond.pddl")
  @fond_problem_path Path.join(@fixture_dir, "abcx-problem.pddl")

  @lab_available Dfcm.autofde_cli_available?()
  @wasm_built Ferroplan.wasm_built?()

  if not @lab_available do
    @moduletag skip:
                 "priv/bin/autofde unavailable (needs AUTOFDE_LAB_ROOT or ~/autofde-lab with a built venv)"
  end

  if not @wasm_built do
    @moduletag skip: Ferroplan.wasm_missing_reason()
  end

  if @lab_available do
    doctest Dfcm
  end

  setup do
    {:ok, _pid} = Ferroplan.start()
    :ok
  end

  @dfcm_phase_actions [
    "preserve-known-options",
    "apply-known-fences",
    "perform-dfcm-calculus",
    "exclude-invalid-options",
    "materialize-falsifiers",
    "extend-if-required",
    "construct-contingent-policy",
    "select-lawful-option"
  ]

  describe "fabric match (real CLI)" do
    test "HTNDomain over dfcm.hddl + dfcm-abcx.hddl matches deterministic solvers" do
      assert {:ok, match} =
               Dfcm.fabric_match("HTNDomain", %{
                 "domain_path" => "qualification/fixtures/dfcm/dfcm.hddl",
                 "problem_path" => "qualification/fixtures/dfcm/dfcm-abcx.hddl"
               })

      assert match["domain"] == "HTNDomain"
      assert match["domain_arguments"]["domain_path"] =~ "dfcm.hddl"
      assert "Astar" in match["compatible_solvers"]
      assert is_binary(match["identity_sha256"])
      assert byte_size(match["identity_sha256"]) == 64
      assert match["cache_status"] in ["MISS", "HIT", "BYPASS"]
    end

    test "unknown domain is a typed refusal carrying the lab envelope" do
      assert {:error, {:fabric_refused, refusal}} = Dfcm.fabric_match("NoSuchDomain", %{})
      assert refusal["standing"] == "REFUSED"
      assert refusal["code"] == "SKD-FABRIC-002"
      assert refusal["message"] =~ "NoSuchDomain"
    end
  end

  describe "fabric solve (real CLI, receipt-bearing trajectory)" do
    test "HTNDomain + Astar solves the dfcm HDDL fixture through all 8 DfCM phases" do
      assert {:ok, sol} =
               Dfcm.fabric_solve("HTNDomain",
                 solver: "Astar",
                 domain_arguments: %{
                   "domain_path" => "qualification/fixtures/dfcm/dfcm.hddl",
                   "problem_path" => "qualification/fixtures/dfcm/dfcm-abcx.hddl"
                 }
               )

      assert sol["standing"] == "SOLVED"
      assert sol["terminal"] == true
      assert length(sol["steps"]) == 8
      assert Enum.map(sol["steps"], & &1["action"]["name"]) == @dfcm_phase_actions

      for digest <- ~w(input_sha256 receipt_sha256 trajectory_sha256) do
        assert is_binary(sol[digest])
        assert byte_size(sol[digest]) == 64
      end

      # The trajectory terminates exactly at SELECT.
      last = List.last(sol["steps"])
      assert last["termination"] == true
      assert last["next_observation"] =~ "selection-complete"
    end

    test "FOND fixture is a typed fabric refusal (no FOND-capable registered domain)" do
      fabric_verdict =
        Dfcm.fabric_solve("PDDLDomain",
          solver: "Astar",
          domain_arguments: %{
            "domain_path" => "qualification/fixtures/dfcm/dfcm-fond.pddl",
            "problem_path" => "qualification/fixtures/dfcm/abcx-problem.pddl"
          }
        )

      case fabric_verdict do
        {:error, {:fabric_refused, refusal}} ->
          assert refusal["standing"] == "REFUSED"
          assert refusal["code"] == "SKD-FABRIC-008"

        # The lab may precede the envelope with a colored skdecide stdout
        # notice that defeats even the bridge's envelope extraction; that is
        # still an honest refusal, surfaced as undecodable output.
        {:error, {:invalid_json, _reason, raw}} ->
          assert raw =~ "REFUSED"

        other ->
          flunk("expected a fabric refusal for the FOND fixture, got: #{inspect(other)}")
      end
    end
  end

  describe "cross-validation: fabric vs ferroplan wasm on the SAME fixtures" do
    test "HDDL leg: both engines solve; ferroplan policy carries the same phase ladder" do
      assert {:ok, fabric_sol} =
               Dfcm.fabric_solve("HTNDomain",
                 solver: "Astar",
                 domain_arguments: %{
                   "domain_path" => "qualification/fixtures/dfcm/dfcm.hddl",
                   "problem_path" => "qualification/fixtures/dfcm/dfcm-abcx.hddl"
                 }
               )

      domain = File.read!(@hddl_domain_path)
      problem = File.read!(@hddl_problem_path)
      assert {:ok, policy} = Ferroplan.hddl_solve(domain, problem)
      refute Map.has_key?(policy, "error")

      assert fabric_sol["standing"] == "SOLVED"
      assert policy["solved"] == true
      assert policy["planning_type"] == "fond"
      assert policy["notes"] == ["strong FOND fixed point"]

      # Ferroplan's UniversalPlan = 1 decompose entry + 1 exec entry per DfCM
      # phase; the fabric rollout = 1 step per phase. Same ladder, counted in
      # each engine's own vocabulary.
      actions = Enum.map(policy["policy"], & &1["action"])
      assert length(actions) == 9
      assert Enum.count(actions, &String.contains?(&1, "htn:decompose")) == 1

      fabric_actions = Enum.map(fabric_sol["steps"], & &1["action"]["name"])
      assert length(fabric_actions) == 8

      for phase <- @dfcm_phase_actions do
        assert phase in fabric_actions
        assert Enum.any?(actions, &String.contains?(&1, phase)),
               "ferroplan policy missing DfCM phase #{phase}"
      end
    end

    test "FOND leg: ferroplan raw-text surfaces refuse with typed ingest errors" do
      domain = File.read!(@fond_domain_path)
      problem = File.read!(@fond_problem_path)

      # fond_policy/4's ingest contract is a JSON PlanningProblem document,
      # never raw PDDL text.
      assert {:error, {:engine, fond_message}} = Ferroplan.fond_policy(domain, problem)
      assert fond_message =~ "FP_ADAPTER"
      assert fond_message =~ "invalid PlanningProblem JSON"

      # plan/4's classical parser does not accept :non-deterministic.
      assert {:error, {:engine, plan_message}} = Ferroplan.plan(domain, problem)
      assert plan_message =~ "FP_ADAPTER"
      assert plan_message =~ ":NON-DETERMINISTIC"
    end
  end
end
