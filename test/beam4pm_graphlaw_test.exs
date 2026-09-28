# Hand-authored qualification (not ggen-generated) -- see
# bap:hand_authored_test_graphlaw in ontology.ttl.
defmodule BeamPM.GraphlawTest do
  @moduledoc """
  Chicago-style qualification of `BeamPM.Graphlaw`, `BeamPM.PlanAdmission`,
  the deviation SHACL gate and the `ReplanRouter` admission gate against the
  REAL graphlaw wasm module (and the real ferroplan wasm for the router
  case) -- no mocks. A missing artifact is a NAMED SKIP.
  """

  use ExUnit.Case, async: false

  alias BeamPM.{DeviationAdmission, Ferroplan, Graphlaw, PlanAdmission, ReplanRouter}

  if not BeamPM.Graphlaw.wasm_built?() do
    @moduletag skip: BeamPM.Graphlaw.wasm_missing_reason()
  end

  @moduletag timeout: 120_000

  @at "urn:p:at"
  @link "urn:p:link"

  defp at(r), do: {"urn:r:#{r}", @at, "urn:p:true"}
  defp link(a, b), do: {"urn:r:#{a}", @link, "urn:r:#{b}"}

  defp go(a, b), do: %{name: "go #{a} #{b}", pre: [at(a), link(a, b)], add: [at(b)], del: [at(a)]}

  # ferroplan's PlanStep: %{"action" => "GO", "args" => ["A", "B"]}
  defp model do
    %{
      "GO" => fn [a, b] -> %{pre: [at(a), link(a, b)], add: [at(b)], del: [at(a)]} end
    }
  end

  @domain """
  (define (domain rooms)
    (:requirements :strips :typing)
    (:types room)
    (:predicates (at ?r - room) (link ?a - room ?b - room))
    (:action go
      :parameters (?a - room ?b - room)
      :precondition (and (at ?a) (link ?a ?b))
      :effect (and (at ?b) (not (at ?a)))))
  """

  @problem """
  (define (problem three-room)
    (:domain rooms)
    (:objects a b c - room)
    (:init (at a) (link a b) (link b c))
    (:goal (at c)))
  """

  setup do
    {:ok, _} = Graphlaw.start()
    :ok
  end

  describe "BeamPM.Graphlaw.admit_plan/4" do
    test "a valid plan is admitted with one chained receipt per action" do
      state = [at("A"), link("A", "B"), link("B", "C")]

      assert {:ok, %{"receipts" => [r1, r2], "states" => [_, _, final]}} =
               Graphlaw.admit_plan(state, [go("A", "B"), go("B", "C")], [at("C")])

      assert r1["step"] == "plan-action"
      assert r1["child"] == r2["parent"]
      assert r2["child"] == final
    end

    test "falsifier: an unmet precondition mid-plan is refused at that step" do
      state = [at("A"), link("A", "B")]

      assert {:error, {:refused, refusal}} =
               Graphlaw.admit_plan(state, [go("A", "B"), go("B", "C")], [at("C")])

      assert refusal["message"] =~ "plan refused at step 1"
    end

    test "replay is byte-identical" do
      state = [at("A"), link("A", "B")]

      assert Graphlaw.admit_plan(state, [go("A", "B")], [at("B")]) ==
               Graphlaw.admit_plan(state, [go("A", "B")], [at("B")])
    end
  end

  describe "BeamPM.PlanAdmission" do
    test "an action with no model is refused, never skipped" do
      admission = %{state: [at("A")], model: model(), goal: []}
      plan = %{"steps" => [%{"action" => "TELEPORT", "args" => []}]}
      assert {:error, {:refused, %{"message" => msg}}} = PlanAdmission.admit(plan, admission)
      assert msg =~ "no action model"
    end
  end

  describe "ReplanRouter.execute(:session_replan) with an admission spec" do
    if not BeamPM.Ferroplan.wasm_built?() do
      @describetag skip: BeamPM.Ferroplan.wasm_missing_reason()
    end

    setup do
      {:ok, _} = Ferroplan.start()
      {:ok, %{"handle" => handle}} = Ferroplan.session_new(@domain, @problem)
      on_exit(fn -> Ferroplan.session_free(handle) end)
      %{handle: handle}
    end

    test "a real ferroplan plan is independently admitted", %{handle: handle} do
      admission = %{
        state: [at("A"), link("A", "B"), link("B", "C")],
        model: model(),
        goal: [at("C")]
      }

      assert {:ok, res} = ReplanRouter.execute(:session_replan, handle, %{admission: admission})
      assert res.outcome == :solved
      assert length(res.admission.receipts) == res.plan["length"]
    end

    test "falsifier: the same plan is refused when the world lacks a link", %{handle: handle} do
      admission = %{state: [at("A"), link("A", "B")], model: model(), goal: [at("C")]}

      assert {:error, {:plan_refused, refusal}} =
               ReplanRouter.execute(:session_replan, handle, %{admission: admission})

      assert refusal["message"] =~ "plan refused at step 1"
    end

    test "anti-vacuity: the gate is what refuses -- ungated router admits the SAME mutated world",
         %{
           handle: handle
         } do
      mutated = %{state: [at("A"), link("A", "B")], model: model(), goal: [at("C")]}

      assert {:ok, %{outcome: :solved}} = ReplanRouter.execute(:session_replan, handle, %{})

      assert {:error, {:plan_refused, _}} =
               ReplanRouter.execute(:session_replan, handle, %{admission: mutated})
    end

    test "without an admission spec the router behaves as before", %{handle: handle} do
      assert {:ok, %{outcome: :solved} = res} = ReplanRouter.execute(:session_replan, handle, %{})
      refute Map.has_key?(res, :admission)
    end
  end

  describe "DeviationAdmission with graphlaw_gate: true" do
    setup do
      path = Path.join(System.tmp_dir!(), "dev_gate_#{System.unique_integer([:positive])}.ttl")
      File.write!(path, "@prefix bpm: <https://ggen.dev/ontology/beam-process-model#> .\n")
      on_exit(fn -> File.rm(path) end)
      %{path: path}
    end

    @deviant %{conforms: false, deviations: [["clean_house", ">>"]]}

    test "a well-formed deviation is admitted and appended", %{path: path} do
      assert {:ok, name} =
               DeviationAdmission.admit_deviation(@deviant, "ref-1", "cand-1", path,
                 graphlaw_gate: true
               )

      assert File.read!(path) =~ name
    end

    test "falsifier: a malformed deviation is refused and the file is byte-identical", %{
      path: path
    } do
      before = File.read!(path)

      assert {:error, {:deviation_refused, _}} =
               DeviationAdmission.admit_deviation(@deviant, "ref-1", "", path,
                 graphlaw_gate: true
               )

      assert File.read!(path) == before
    end

    test "anti-vacuity: the same malformed input is appended without the gate, refused with it",
         %{
           path: path
         } do
      assert {:ok, name} = DeviationAdmission.admit_deviation(@deviant, "ref-1", "", path)
      assert File.read!(path) =~ name

      File.write!(path, "@prefix bpm: <https://ggen.dev/ontology/beam-process-model#> .\n")
      before = File.read!(path)

      assert {:error, {:deviation_refused, _}} =
               DeviationAdmission.admit_deviation(@deviant, "ref-1", "", path,
                 graphlaw_gate: true
               )

      assert File.read!(path) == before
    end
  end

  describe "FOND policy admission" do
    if not BeamPM.Ferroplan.wasm_built?() do
      @describetag skip: BeamPM.Ferroplan.wasm_missing_reason()
    end

    @retry_loop JSON.encode!(%{
                  "states" => [%{"id" => "s0"}, %{"id" => "g", "facts" => ["done"]}],
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

    @preimage %{subject: "s", pack: "p", policy: "q", world: "w"}

    setup do
      {:ok, _} = Ferroplan.start()
      :ok
    end

    test "load_policy with the graphlaw court admits the real synthesized policy" do
      {:ok, synthesized} = Ferroplan.fond_policy("", @retry_loop)
      pre = %{@preimage | policy: ReplanRouter.policy_digest(synthesized)}
      st0 = ReplanRouter.new(plan_id: "rooms-1", preimage: pre, run_id: "fond")

      assert {:ok, st} = ReplanRouter.load_policy(st0, @retry_loop, nil, graphlaw_court: true)
      assert [%{"state" => "s0", "action" => "flip"}] = st.universal_plan["policy"]
    end

    test "falsifier: the court refuses a real policy with skewed probability mass" do
      {:ok, synthesized} = Ferroplan.fond_policy("", @retry_loop)
      assert {:ok, _} = Graphlaw.admit_policy(@retry_loop, synthesized)

      skewed =
        update_in(
          synthesized,
          ["policy", Access.at(0), "outcomes", Access.at(0), "probability_ppm"],
          fn _ -> 1 end
        )

      assert {:error, {:refused, %{"message" => msg}}} =
               Graphlaw.admit_policy(@retry_loop, skewed)

      assert msg =~ "policy refused (BadMass)"
    end

    test "falsifier: a policy missing its only entry is refused as MissingEntry" do
      {:ok, synthesized} = Ferroplan.fond_policy("", @retry_loop)

      assert {:error, {:refused, %{"message" => msg}}} =
               Graphlaw.admit_policy(@retry_loop, Map.put(synthesized, "policy", []))

      assert msg =~ "policy refused (MissingEntry)"
    end
  end
end
