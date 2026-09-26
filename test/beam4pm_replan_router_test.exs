defmodule BeamPM.ReplanRouterTest do
  @moduledoc """
  Chicago-style qualification of the pure `BeamPM.ReplanRouter.route/2`
  ladder and `BeamPM.PlanLineage` hash chain: real structs, real sha256,
  state-based assertions on the returned decision, evidence and state. No
  engine is needed here -- the engine-backed driver is qualified in
  `test/beam4pm_replan_router_engine_test.exs`.
  """

  use ExUnit.Case, async: true

  alias BeamPM.{PlanLineage, ReplanRouter}

  alias BeamPM.Types.{
    DynamicReplanTrigger,
    EventTriggeredPlanning,
    OcelEvent,
    PlanMemory,
    StalePlanRefusal
  }

  @preimage %{subject: "sha-subject", pack: "sha-pack", policy: "sha-policy", world: "sha-world"}

  @universal_plan %{
    "solved" => true,
    "policy" => [
      %{
        "state" => "s0",
        "action" => "flip",
        "outcomes" => [%{"state" => "g"}, %{"state" => "s0"}]
      }
    ]
  }

  defp state(extra \\ []) do
    ReplanRouter.new(
      Keyword.merge([plan_id: "plan-1", preimage: @preimage, run_id: "run-t"], extra)
    )
  end

  defp obs(extra) do
    Map.merge(%{preimage: @preimage, conformance: :deviates, plan_valid: false}, Map.new(extra))
  end

  describe "ordered checks" do
    test "1. a drifted preimage is refused with a StalePlanRefusal naming the drifted keys" do
      drifted = %{@preimage | pack: "sha-pack-2", world: "sha-world-2"}

      {decision, ev, st} = ReplanRouter.route(obs(preimage: drifted, goal_met: true), state())

      assert decision == :refuse_stale
      assert %StalePlanRefusal{plan_id: "plan-1"} = ev.refusal
      assert ev.refusal.admitted_preimage_hash == ReplanRouter.preimage_hash(@preimage)
      assert ev.refusal.observed_preimage_hash == ReplanRouter.preimage_hash(drifted)
      refute ev.refusal.admitted_preimage_hash == ev.refusal.observed_preimage_hash
      assert ev.drifted == [:pack, :world]
      assert st.rung == :none
    end

    test "1. stale check precedes the new-event reset (no episode opened)" do
      drifted = %{@preimage | subject: "other"}
      s0 = state()

      {:refuse_stale, ev, st} =
        ReplanRouter.route(obs(preimage: drifted, event_id: "e1", admitted: true), s0)

      refute Map.has_key?(ev, :episode)
      assert st.episode_id == s0.episode_id
      refute MapSet.member?(st.seen_events, "e1")
    end

    test "preimage keys given as strings are equivalent to atom keys" do
      string_keyed = Map.new(@preimage, fn {k, v} -> {Atom.to_string(k), v} end)

      {decision, _ev, _st} =
        ReplanRouter.route(obs(preimage: string_keyed, goal_met: true), state())

      assert decision == :close
    end

    test "2. goal met closes with a PlanMemory bound to the lineage head" do
      s0 = state()
      {:close, ev, _st} = ReplanRouter.route(obs(goal_met: true, unknown_facts: ["(x)"]), s0)

      assert %PlanMemory{plan_id: "plan-1"} = ev.plan_memory

      assert ev.plan_memory.memory_hash ==
               PlanLineage.digest(%{
                 "evidence_hash" => ev.plan_memory.evidence_hash,
                 "lineage_hash" => PlanLineage.head_hash(s0.lineage),
                 "plan_id" => "plan-1"
               })
    end

    test "3. an unknown fact routes to strategic_recompile with WorldModelInvalid evidence" do
      {decision, ev, st} =
        ReplanRouter.route(obs(unknown_facts: ["(zzz q)", "(aaa)"], conformance: nil), state())

      assert decision == :strategic_recompile
      assert ev.world_model_invalid.kind == "WorldModelInvalid"
      assert ev.world_model_invalid.unknown_facts == ["(aaa)", "(zzz q)"]
      assert %DynamicReplanTrigger{plan_id: "plan-1"} = ev.trigger
      assert st.rung == :strategic_recompile
    end

    test "3. missing conformance re-observes" do
      assert {:reobserve, %{reason: :missing_conformance}, st} =
               ReplanRouter.route(obs(conformance: nil), state())

      assert st.rung == :none
    end

    test "4. conforms and plan valid continues" do
      assert {:continue, _, _} =
               ReplanRouter.route(obs(conformance: :conforms, plan_valid: true), state())
    end

    test "4. conforms but plan invalid does not continue" do
      {decision, _, _} =
        ReplanRouter.route(obs(conformance: :conforms, plan_valid: false), state())

      refute decision == :continue
    end

    test "5. a covering UniversalPlan is followed; an uncovered state is not" do
      s0 = state(universal_plan: @universal_plan)

      assert {:follow_policy, ev, _} =
               ReplanRouter.route(obs(policy_state: "s0", suffix_from: 1), s0)

      assert ev.action == "flip"

      assert {:suffix_reuse, _, _} =
               ReplanRouter.route(obs(policy_state: "s9", suffix_from: 1), s0)
    end

    test "6. a valid later suffix is reused" do
      assert {:suffix_reuse, %{suffix_from: 2}, st} =
               ReplanRouter.route(obs(suffix_from: 2), state())

      assert st.rung == :none
    end
  end

  describe "7. monotone ladder" do
    test "climbs session_replan -> hddl_replan -> strategic_recompile on failed attempts" do
      s0 = state()

      {:session_replan, ev1, s1} = ReplanRouter.route(obs([]), s0)
      assert %DynamicReplanTrigger{} = ev1.trigger
      assert ev1.lineage.parent_plan_id == "plan-1"

      {:hddl_replan, ev2, s2} =
        ReplanRouter.route(obs(attempt: {:session_replan, :exhausted}), s1)

      assert ev2.lineage.parent_plan_id == ev1.lineage.plan_id

      {:strategic_recompile, ev3, s3} =
        ReplanRouter.route(obs(attempt: {:hddl_replan, :no_plan}), s2)

      assert ev3.lineage.parent_plan_id == ev2.lineage.plan_id

      assert s3.rung == :strategic_recompile
      assert length(PlanLineage.links(s3.lineage)) == 4
      assert PlanLineage.verify(s3.lineage) == :ok
    end

    test "hddl timeout also climbs" do
      s1 = %{state() | rung: :hddl_replan}

      assert {:strategic_recompile, _, _} =
               ReplanRouter.route(obs(attempt: {:hddl_replan, :timeout}), s1)
    end

    test "never descends: a stale low-rung failure report does not lower the rung" do
      s = %{state() | rung: :hddl_replan}
      {decision, _, st} = ReplanRouter.route(obs(attempt: {:none, :exhausted}), s)
      assert decision == :hddl_replan
      assert st.rung == :hddl_replan

      {decision2, _, _} = ReplanRouter.route(obs(attempt: {:session_replan, :solved}), s)
      assert decision2 == :hddl_replan
    end

    test "rung is monotone over a random walk of attempts" do
      attempts =
        for r <- ReplanRouter.rungs(), o <- [:solved, :exhausted, :no_plan, :timeout], do: {r, o}

      :rand.seed(:exsss, {1, 2, 3})

      Enum.reduce(1..200, state(), fn _, st ->
        a = Enum.random([nil | attempts])
        {_d, _ev, st2} = ReplanRouter.route(obs(attempt: a), st)
        idx = fn r -> Enum.find_index(ReplanRouter.rungs(), &(&1 == r)) end
        assert idx.(st2.rung) >= idx.(st.rung)
        st2
      end)
    end

    test "a new admitted event resets the rung with EventTriggeredPlanning; a replayed one does not" do
      s = %{state() | rung: :strategic_recompile}

      {decision, ev, st} = ReplanRouter.route(obs(event_id: "e-new", admitted: true), s)
      assert decision == :session_replan
      assert %EventTriggeredPlanning{event_id: "e-new"} = ev.episode
      assert ev.episode.world_state_hash == ReplanRouter.preimage_hash(@preimage)
      refute st.episode_id == s.episode_id

      st = %{st | rung: :hddl_replan}
      {decision2, ev2, _} = ReplanRouter.route(obs(event_id: "e-new", admitted: true), st)
      assert decision2 == :hddl_replan
      refute Map.has_key?(ev2, :episode)
    end

    test "an unadmitted event does not reset" do
      s = %{state() | rung: :hddl_replan}
      {decision, _, _} = ReplanRouter.route(obs(event_id: "e-x", admitted: false), s)
      assert decision == :hddl_replan
    end
  end

  describe "evidence and events" do
    test "exactly one OcelEvent per decision, appended to state, authority NONE" do
      inputs = [
        obs(preimage: %{@preimage | world: "w2"}),
        obs(goal_met: true),
        obs(conformance: nil),
        obs(conformance: :conforms, plan_valid: true),
        obs(suffix_from: 1),
        obs([])
      ]

      {st, decisions} =
        Enum.reduce(inputs, {state(), []}, fn o, {st, acc} ->
          {d, ev, st2} = ReplanRouter.route(o, st)
          assert %OcelEvent{} = ev.ocel_event
          assert ev.ocel_event.event_type == "replan_router.#{d}"
          assert ev.authority == "NONE"
          assert ev.ceiling == "CONSTRUCT"
          assert length(st2.events) == length(st.events) + 1
          assert List.last(st2.events) == ev.ocel_event
          {st2, acc ++ [d]}
        end)

      assert decisions == [
               :refuse_stale,
               :close,
               :reobserve,
               :continue,
               :suffix_reuse,
               :session_replan
             ]

      ids = Enum.map(st.events, & &1.event_id)
      assert ids == Enum.uniq(ids)
      assert Enum.all?(st.events, &(&1.attributes["case_id"] == "run-t"))
    end

    test "every decision is a declared decision" do
      {d, _, _} = ReplanRouter.route(obs([]), state())
      assert d in ReplanRouter.decisions()
    end
  end

  describe "PlanLineage" do
    test "canonical JSON sorts keys at every depth and digests are order independent" do
      a = %{"b" => 1, "a" => %{"z" => [3, %{"y" => nil, "x" => true}], "c" => "s"}}
      b = %{"a" => %{"c" => "s", "z" => [3, %{"x" => true, "y" => nil}]}, "b" => 1}

      assert PlanLineage.canonical_json(a) ==
               ~s({"a":{"c":"s","z":[3,{"x":true,"y":null}]},"b":1})

      assert PlanLineage.digest(a) == PlanLineage.digest(b)

      assert PlanLineage.digest(a) ==
               :crypto.hash(:sha256, ~s({"a":{"c":"s","z":[3,{"x":true,"y":null}]},"b":1}))
               |> Base.encode16(case: :lower)
    end

    test "list order is significant" do
      refute PlanLineage.digest([1, 2]) == PlanLineage.digest([2, 1])
    end

    test "chain links parents and verify detects tampering" do
      {l1, c1} = PlanLineage.derive(PlanLineage.new(), "p1", %{"n" => 1})
      {l2, c2} = PlanLineage.derive(c1, "p2", %{"n" => 2})

      assert l1.parent_plan_id == nil
      assert l2.parent_plan_id == "p1"
      assert PlanLineage.head_hash(c2) == l2.lineage_hash
      assert PlanLineage.verify(c2) == :ok

      [%{link: head} = top | rest] = c2.links

      forged = %{
        c2
        | links: [%{top | link: %{head | lineage_hash: String.duplicate("0", 64)}} | rest]
      }

      assert {:error, {:lineage_broken, 1, "p2"}} = PlanLineage.verify(forged)

      [second, %{} = first] = c2.links

      tampered = %{
        c2
        | links: [second, %{first | payload_digest: PlanLineage.digest(%{"n" => 9})}]
      }

      assert {:error, {:lineage_broken, 0, "p1"}} = PlanLineage.verify(tampered)
    end

    test "same payloads rebuild the same head hash (replay)" do
      build = fn ->
        Enum.reduce(1..5, PlanLineage.new(), fn i, c ->
          {_l, c} = PlanLineage.derive(c, "p#{i}", %{"i" => i})
          c
        end)
      end

      assert PlanLineage.head_hash(build.()) == PlanLineage.head_hash(build.())
    end
  end
end
