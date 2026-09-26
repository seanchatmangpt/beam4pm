defmodule BeamPM.ReplanRouterEngineTest do
  @moduledoc """
  Chicago-style qualification of `BeamPM.ReplanRouter`'s driver
  (`observe/3`, `execute/4`, `load_policy/3`) against the REAL ferroplan
  wasm engine hosted by `BeamPM.Ferroplan` -- no mocks. A missing wasm
  artifact is a NAMED SKIP (`BeamPM.Ferroplan.wasm_missing_reason/0`), the
  same pattern as `test/beam4pm_ferroplan_test.exs`.
  """

  use ExUnit.Case, async: false

  alias BeamPM.{Ferroplan, PlanLineage, ReplanRouter}

  if not BeamPM.Ferroplan.wasm_built?() do
    @moduletag skip: BeamPM.Ferroplan.wasm_missing_reason()
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

  @preimage %{subject: "s", pack: "p", policy: "q", world: "w"}

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

  setup do
    {:ok, _pid} = Ferroplan.start()
    {:ok, %{"handle" => handle}} = Ferroplan.session_new(@domain, @problem)
    {:ok, sol} = Ferroplan.session_think(handle, 10_000, 64)
    true = sol["solved"]
    state = ReplanRouter.new(plan_id: "rooms-1", preimage: @preimage, run_id: "eng")
    on_exit(fn -> Ferroplan.session_free(handle) end)
    %{handle: handle, plan: sol["plan"], state: state}
  end

  test "observing the plan's first effect makes the stashed suffix reusable", ctx do
    {:ok, obs} =
      ReplanRouter.observe(ctx.handle, [{"(at a)", false}, {"(at b)", true}], %{
        preimage: @preimage,
        conformance: :deviates,
        plan: ctx.plan
      })

    assert obs.unknown_facts == []
    assert obs.goal_met == false
    assert obs.plan_valid == false
    assert obs.suffix_from == 1

    {:suffix_reuse, ev, _st} = ReplanRouter.route(obs, ctx.state)

    assert {:ok, %{outcome: :solved, advanced: 1}} =
             ReplanRouter.execute(:suffix_reuse, ctx.handle, %{evidence: ev})

    assert {:ok, %{"valid" => true}} = Ferroplan.session_valid?(ctx.handle)
  end

  test "an unknown fact is detected before session_observe and routes to strategic_recompile",
       ctx do
    {:ok, obs} =
      ReplanRouter.observe(ctx.handle, [{"(zzz q)", true}, {"(at a)", true}], %{
        preimage: @preimage,
        conformance: :conforms
      })

    assert obs.unknown_facts == ["(zzz q)"]
    {:strategic_recompile, ev, _} = ReplanRouter.route(obs, ctx.state)

    assert {:recompile_required, ^ev} =
             ReplanRouter.execute(:strategic_recompile, ctx.handle, %{evidence: ev})
  end

  test "goal reached through the real session closes", ctx do
    {:ok, obs} =
      ReplanRouter.observe(ctx.handle, [{"(at a)", false}, {"(at c)", true}], %{
        preimage: @preimage
      })

    assert obs.goal_met == true

    assert {:close, %{plan_memory: %BeamPM.Types.PlanMemory{}}, _} =
             ReplanRouter.route(obs, ctx.state)
  end

  test "session_replan replans from the observed state with bounded think", ctx do
    {:ok, obs} =
      ReplanRouter.observe(ctx.handle, [{"(at a)", false}, {"(at b)", true}], %{
        preimage: @preimage,
        conformance: :deviates
      })

    {:session_replan, _ev, st} = ReplanRouter.route(obs, ctx.state)

    assert {:ok, res} =
             ReplanRouter.execute(:session_replan, ctx.handle, %{},
               evals: 5_000_000,
               mem_mb: 99_999
             )

    assert res.outcome == :solved
    assert res.evals == 1_000_000
    assert res.mem_mb == 2048
    assert res.plan["length"] == 1

    {:ok, obs2} =
      ReplanRouter.observe(ctx.handle, [], %{
        preimage: @preimage,
        conformance: :conforms,
        attempt: {:session_replan, res.outcome}
      })

    assert {:continue, _, _} = ReplanRouter.route(obs2, st)

    assert {:ok, %{outcome: :candidate, step: step}} =
             ReplanRouter.execute(:continue, ctx.handle, %{})

    assert step["action"] == "GO"
    assert step["args"] == ["B", "C"]
  end

  test "hddl_replan solves a real HDDL fixture under a Task timeout, and a NoPlan climbs", ctx do
    domain = File.read!("native/ferroplan/domains/solve_x.hddl")
    problem = File.read!("native/ferroplan/domains/solve_x.problem.hddl")

    assert {:ok, %{outcome: :solved, universal_plan: up}} =
             ReplanRouter.execute(:hddl_replan, ctx.handle, %{
               hddl_domain: domain,
               hddl_problem: problem
             })

    assert up["solved"] == true

    assert {:ok, %{outcome: :no_plan}} =
             ReplanRouter.execute(:hddl_replan, ctx.handle, %{
               hddl_domain: "(define (domain broken",
               hddl_problem: problem
             })

    st = %{ctx.state | rung: :hddl_replan}

    assert {:strategic_recompile, ev, st2} =
             ReplanRouter.route(
               %{preimage: @preimage, conformance: :deviates, attempt: {:hddl_replan, :no_plan}},
               st
             )

    assert ev.trigger.plan_id == "rooms-1"
    assert PlanLineage.verify(st2.lineage) == :ok
  end

  test "load_policy uses the real fond_policy op and the policy is then followed", ctx do
    assert {:ok, st} = ReplanRouter.load_policy(ctx.state, @retry_loop)
    assert [%{"state" => "s0", "action" => "flip"}] = st.universal_plan["policy"]

    {:follow_policy, ev, _} =
      ReplanRouter.route(%{preimage: @preimage, conformance: :deviates, policy_state: "s0"}, st)

    assert {:ok, %{outcome: :candidate, action: "flip", authority: "NONE"}} =
             ReplanRouter.execute(:follow_policy, ctx.handle, %{evidence: ev})
  end
end
