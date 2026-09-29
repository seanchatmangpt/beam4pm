# Hand-authored qualification (not ggen-generated).
defmodule BeamPM.ActionModelTest do
  @moduledoc """
  Chicago-style: real ferroplan plans a real domain, `ActionModel` derives the
  admission spec from the same PDDL, real graphlaw admits/refuses.
  """
  use ExUnit.Case, async: false

  alias BeamPM.{ActionModel, Ferroplan, Graphlaw, ReplanRouter}

  if not (BeamPM.Graphlaw.wasm_built?() and BeamPM.Ferroplan.wasm_built?()) do
    @moduletag skip: "graphlaw and/or ferroplan wasm missing"
  end

  @moduletag timeout: 120_000

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
    {:ok, _} = Ferroplan.start()
    :ok
  end

  defp session do
    {:ok, %{"handle" => h}} = Ferroplan.session_new(@domain, @problem)
    on_exit(fn -> Ferroplan.session_free(h) end)
    h
  end

  test "derives state, goal and a parameterised model" do
    assert {:ok, %{state: state, goal: goal, model: %{"GO" => f}}} =
             ActionModel.from_pddl(@domain, @problem)

    assert {"urn:r:A", "urn:p:at", "urn:p:true"} in state
    assert {"urn:r:B", "urn:p:link", "urn:r:C"} in state
    assert goal == [{"urn:r:C", "urn:p:at", "urn:p:true"}]

    assert f.(["A", "B"]) == %{
             pre: [{"urn:r:A", "urn:p:at", "urn:p:true"}, {"urn:r:A", "urn:p:link", "urn:r:B"}],
             add: [{"urn:r:B", "urn:p:at", "urn:p:true"}],
             del: [{"urn:r:A", "urn:p:at", "urn:p:true"}]
           }
  end

  test "a real ferroplan plan is admitted through the router with the derived spec" do
    {:ok, spec} = ActionModel.from_pddl(@domain, @problem)

    assert {:ok, res} = ReplanRouter.execute(:session_replan, session(), %{admission: spec})
    assert res.outcome == :solved
    assert length(res.admission.receipts) == res.plan["length"]
  end

  test "falsifier: derived model refuses a world lacking a link; dropped-precondition model admits it" do
    {:ok, spec} = ActionModel.from_pddl(@domain, @problem)

    world = %{
      spec
      | state: Enum.reject(spec.state, &(&1 == {"urn:r:B", "urn:p:link", "urn:r:C"}))
    }

    assert {:error, {:plan_refused, r}} =
             ReplanRouter.execute(:session_replan, session(), %{admission: world})

    assert r["message"] =~ "plan refused at step 1"

    mutated_domain = String.replace(@domain, "(link ?a ?b)", "")
    {:ok, mutant} = ActionModel.from_pddl(mutated_domain, @problem)
    mutant_world = %{mutant | state: world.state}
    assert {:ok, _} = ReplanRouter.execute(:session_replan, session(), %{admission: mutant_world})
  end

  test "falsifier: dropping the add effect leaves the goal unmet and is refused" do
    mutated = String.replace(@domain, "(and (at ?b) (not (at ?a)))", "(and (not (at ?a)))")
    {:ok, spec} = ActionModel.from_pddl(mutated, @problem)

    assert {:error, {:plan_refused, _}} =
             ReplanRouter.execute(:session_replan, session(), %{admission: spec})
  end

  for {label, frag, what} <- [
        {"disjunction", "(or (at ?a) (at ?b))", "or"},
        {"negated conjunction", "(not (and (at ?b) (link ?a ?b)))", "not in precondition"},
        {"double negation", "(not (not (at ?b)))", "not in precondition"},
        {"negated disjunction", "(not (or (at ?a) (at ?b)))", "not in precondition"},
        {"quantifier", "(forall (?x - room) (at ?x))", "forall"},
        {"conditional effect", nil, "when"}
      ] do
    test "unsupported #{label} is refused" do
      dom =
        if unquote(frag) do
          String.replace(@domain, "(and (at ?a) (link ?a ?b))", "(and #{unquote(frag)})")
        else
          String.replace(@domain, "(and (at ?b) (not (at ?a)))", "(when (at ?a) (at ?b))")
        end

      assert {:error, {:unsupported, w}} = ActionModel.from_pddl(dom, @problem)
      assert w =~ unquote(what)
    end
  end

  test "numeric fluents are refused" do
    dom = String.replace(@domain, "(:predicates", "(:functions (cost))\n (:predicates")
    assert {:error, {:unsupported, _}} = ActionModel.from_pddl(dom, @problem)
  end

  # ---- negative preconditions / goals --------------------------------------

  @neg_domain """
  (define (domain rooms-neg)
    (:requirements :strips :typing :negative-preconditions)
    (:types room)
    (:predicates (at ?r - room) (link ?a - room ?b - room) (blocked ?r - room))
    (:action go
      :parameters (?a - room ?b - room)
      :precondition (and (at ?a) (link ?a ?b) (not (blocked ?b)))
      :effect (and (at ?b) (not (at ?a)))))
  """

  @neg_problem """
  (define (problem three-room-neg)
    (:domain rooms-neg)
    (:objects a b c - room)
    (:init (at a) (link a b) (link b c))
    (:goal (at c)))
  """

  defp neg_session do
    {:ok, %{"handle" => h}} = Ferroplan.session_new(@neg_domain, @neg_problem)
    on_exit(fn -> Ferroplan.session_free(h) end)
    h
  end

  test "negative precondition maps to pre_not with the positive atom scheme" do
    assert {:ok, %{model: %{"GO" => f}} = spec} = ActionModel.from_pddl(@neg_domain, @neg_problem)
    assert %{pre_not: [{"urn:r:B", "urn:p:blocked", "urn:p:true"}]} = f.(["A", "B"])
    refute Map.has_key?(spec, :goal_not)
  end

  test "negative goal maps to goal_not" do
    prob = String.replace(@neg_problem, "(:goal (at c))", "(:goal (and (at c) (not (blocked a))))")
    assert {:ok, %{goal_not: [{"urn:r:A", "urn:p:blocked", "urn:p:true"}]}} =
             ActionModel.from_pddl(@neg_domain, prob)
  end

  test "negation of a non-atom in a goal stays unsupported" do
    prob = String.replace(@neg_problem, "(:goal (at c))", "(:goal (not (and (at c) (at b))))")
    assert {:error, {:unsupported, w}} = ActionModel.from_pddl(@neg_domain, prob)
    assert w =~ "not in goal"
  end

  test "ferroplan route is admitted when nothing is blocked" do
    {:ok, spec} = ActionModel.from_pddl(@neg_domain, @neg_problem)
    assert {:ok, res} = ReplanRouter.execute(:session_replan, neg_session(), %{admission: spec})
    assert res.outcome == :solved
    assert length(res.admission.receipts) == res.plan["length"]
  end

  test "world with the route's room blocked is refused with violated_absent" do
    {:ok, spec} = ActionModel.from_pddl(@neg_domain, @neg_problem)
    blocked = {"urn:r:B", "urn:p:blocked", "urn:p:true"}
    world = %{spec | state: [blocked | spec.state]}

    assert {:error, {:plan_refused, r}} =
             ReplanRouter.execute(:session_replan, neg_session(), %{admission: world})

    assert r["message"] =~ "plan refused at step 0"
    assert r["details"]["violated_absent"] |> Enum.join() =~ "urn:r:B"
    assert r["details"]["violated_absent"] |> Enum.join() =~ "urn:p:blocked"
  end

  test "negative goal violated at the end is refused" do
    {:ok, spec} = ActionModel.from_pddl(@neg_domain, @neg_problem)
    # the plan ends at C; forbid `at c` at the end so the plan cannot satisfy it
    spec = Map.put(spec, :goal_not, [{"urn:r:C", "urn:p:at", "urn:p:true"}])

    assert {:error, {:plan_refused, r}} =
             ReplanRouter.execute(:session_replan, neg_session(), %{admission: spec})

    assert r["details"]["violated_absent"] |> Enum.join() =~ "urn:r:C"
  end
end
