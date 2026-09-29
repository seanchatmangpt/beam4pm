defmodule BeamPM.EnterprisePlanningTest do
  use ExUnit.Case, async: true

  alias BeamPM.EnterprisePlanning

  test "declares the enterprise planning classes without actuation authority" do
    caps = EnterprisePlanning.capabilities()

    assert caps.authority == :candidate_only
    assert caps.actuation == :not_provided

    assert Enum.sort(caps.supported) ==
             Enum.sort([:classical, :numeric, :preferences, :temporal, :htn, :hddl, :fond])

    assert :validate in caps.lifecycle
    assert :explain in caps.lifecycle
    assert :replan in caps.lifecycle
    assert :fork_scenario in caps.lifecycle
    assert :observe in caps.lifecycle
  end

  test "refuses partial-observability and probabilistic classes instead of weakening semantics" do
    base = %{domain: "domain", problem: "problem"}

    for class <- [:pomdp, :contingent_partial_observability, :probabilistic_mdp] do
      assert {:error, {:unsupported_planning_class, ^class}} =
               EnterprisePlanning.solve(Map.put(base, :class, class))
    end
  end

  test "distinguishes unknown classes from known unsupported classes" do
    assert {:error, {:unknown_planning_class, :magic}} =
             EnterprisePlanning.solve(%{class: :magic, domain: "d", problem: "p"})
  end

  test "rejects malformed requests before reaching the engine" do
    assert {:error, {:invalid_planning_request, %{class: :classical}}} =
             EnterprisePlanning.solve(%{class: :classical})
  end
end
