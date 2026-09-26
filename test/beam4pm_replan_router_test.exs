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

  # A state whose admitted preimage.policy is the digest of @universal_plan.
  defp policy_state do
    pre = %{@preimage | policy: ReplanRouter.policy_digest(@universal_plan)}

    ReplanRouter.new(plan_id: "plan-1", preimage: pre, universal_plan: @universal_plan)
  end

  defp policy_obs(st, extra),
    do: Map.merge(obs(extra), %{preimage: st.admitted_preimage})

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
      s0 = policy_state()

      assert {:follow_policy, ev, _} =
               ReplanRouter.route(policy_obs(s0, policy_state: "s0", suffix_from: 1), s0)

      assert ev.action == "flip"

      assert {:suffix_reuse, _, _} =
               ReplanRouter.route(policy_obs(s0, policy_state: "s9", suffix_from: 1), s0)
    end

    test "1a. a mutated UniversalPlan is refused, never followed" do
      s0 = policy_state()

      mutated =
        put_in(s0.universal_plan["policy"], [%{"state" => "s0", "action" => "launch_everything"}])

      s1 = %{s0 | universal_plan: mutated}

      {decision, ev, st} = ReplanRouter.route(policy_obs(s1, policy_state: "s0"), s1)

      assert decision == :refuse_stale
      assert ev.reason == :policy_digest_mismatch
      assert ev.drifted == [:policy]
      assert ev.held_policy_digest == ReplanRouter.policy_digest(mutated)
      refute Map.has_key?(ev, :action)
      assert %StalePlanRefusal{} = ev.refusal
      refute ev.refusal.admitted_preimage_hash == ev.refusal.observed_preimage_hash
      assert st.rung == :none

      # the admitted plan on the same preimage is still followed
      assert {:follow_policy, %{action: "flip"}, _} =
               ReplanRouter.route(policy_obs(s0, policy_state: "s0"), s0)
    end

    test "1a. new/1 refuses a UniversalPlan that does not match the admitted policy digest" do
      assert_raise ArgumentError, ~r/admitted preimage.policy/, fn ->
        state(universal_plan: @universal_plan)
      end
    end

    test "1. an empty or partial admitted preimage is refused at construction" do
      for bad <- [%{}, Map.delete(@preimage, :world), %{@preimage | subject: ""}] do
        assert_raise ArgumentError, ~r/admitted preimage/, fn ->
          ReplanRouter.new(plan_id: "p", preimage: bad)
        end
      end
    end

    test "1. an observation without a preimage fails closed" do
      {decision, ev, _} =
        ReplanRouter.route(%{conformance: :conforms, plan_valid: true}, state())

      assert decision == :refuse_stale
      assert ev.drifted == [:subject, :pack, :policy, :world]
    end

    test "1b. malformed observation fields are refused, never coerced" do
      cases = [
        {[goal_met: "false"], [:goal_met]},
        {[admitted: "yes", event_id: "e1"], [:admitted]},
        {[plan_valid: 1, conformance: :conforms], [:plan_valid]},
        {[conformance: :maybe], [:conformance]},
        {[attempt: {:session_replan, :bogus}], [:attempt]},
        {[attempt: :exhausted], [:attempt]},
        {[attempt: {:session_replan, :error}], [:attempt]},
        {[attempt: {:session_replan, :exhausted, :x}], [:attempt]},
        {[observed_at: "yesterday"], [:observed_at]},
        {[observed_at: 1_700_000_000], [:observed_at]},
        {[suffix_from: -1], [:suffix_from]},
        {[unknown_facts: "(x)"], [:unknown_facts]},
        {[event_id: 7, goal_met: "true"], [:goal_met, :event_id]}
      ]

      for {extra, fields} <- cases do
        s0 = state()
        {decision, ev, st} = ReplanRouter.route(obs(extra), s0)
        assert decision == :refuse_malformed, inspect(extra)
        assert Enum.sort(ev.fields) == Enum.sort(fields), inspect(extra)
        assert st.rung == :none
        assert st.seen_events == s0.seen_events
        assert decision in ReplanRouter.decisions()
      end
    end

    test "1b. an :error outcome at the held rung is refused, never climbs" do
      {:session_replan, _, s1} = ReplanRouter.route(obs([]), state())
      assert s1.rung == :session_replan

      {decision, ev, st} = ReplanRouter.route(obs(attempt: {:session_replan, :error}), s1)
      assert decision == :refuse_malformed
      assert ev.fields == [:attempt]
      assert st.rung == :session_replan
      assert st.generation == s1.generation
      assert st.current_plan_id == s1.current_plan_id
    end

    test "1b. a preimage carrying a field under both atom and string keys is refused" do
      s0 = state()

      for {forged, dup} <- [
            {Map.put(@preimage, "subject", "forged"), [:subject]},
            {Map.put(@preimage, "subject", @preimage.subject), [:subject]},
            {Map.merge(@preimage, %{"pack" => "x", "world" => "y"}), [:pack, :world]}
          ] do
        {decision, ev, st} = ReplanRouter.route(obs(preimage: forged), s0)
        assert decision == :refuse_malformed, inspect(forged)
        assert ev.reason == :ambiguous_preimage
        assert ev.fields == [:preimage]
        assert ev.ambiguous_keys == dup
        assert st.rung == :none
      end

      assert_raise ArgumentError, ~r/both atom and string keys/, fn ->
        ReplanRouter.new(plan_id: "p", preimage: Map.put(@preimage, "world", "sha-world"))
      end
    end

    test "6. suffix_from 0 is not a later suffix" do
      {decision, _, _} = ReplanRouter.route(obs(suffix_from: 0), state())
      assert decision == :session_replan
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

    test "a forged attempt for a rung not held cannot skip rungs" do
      s0 = state()

      for forged <- [
            {:hddl_replan, :exhausted},
            {:strategic_recompile, :timeout},
            {:session_replan, :exhausted},
            {:none, :exhausted}
          ] do
        {decision, ev, st} = ReplanRouter.route(obs(attempt: forged), s0)
        assert decision == :session_replan, inspect(forged)
        assert ev.attempt_ignored == forged
        assert st.rung == :session_replan
      end

      # held at session_replan, a report about hddl_replan is still ignored
      {:session_replan, _, s1} = ReplanRouter.route(obs([]), s0)

      assert {:session_replan, %{attempt_ignored: {:hddl_replan, :no_plan}}, _} =
               ReplanRouter.route(obs(attempt: {:hddl_replan, :no_plan}), s1)

      {:hddl_replan, ev2, _} =
        ReplanRouter.route(obs(attempt: {:session_replan, :exhausted}), s1)

      refute Map.has_key?(ev2, :attempt_ignored)
    end

    test "each generation names the plan it replaces and advances current_plan_id" do
      s0 = state()
      assert s0.current_plan_id == "plan-1"

      {:session_replan, ev1, s1} = ReplanRouter.route(obs([]), s0)
      assert ev1.trigger.plan_id == "plan-1"
      assert s1.current_plan_id == ev1.lineage.plan_id
      assert s1.plan_id == "plan-1"

      {:hddl_replan, ev2, s2} =
        ReplanRouter.route(obs(attempt: {:session_replan, :exhausted}), s1)

      assert ev2.trigger.plan_id == ev1.lineage.plan_id
      assert ev2.lineage.parent_plan_id == ev1.lineage.plan_id
      assert s2.current_plan_id == ev2.lineage.plan_id

      {:close, cev, _} = ReplanRouter.route(obs(goal_met: true), s2)
      assert cev.plan_memory.plan_id == s2.current_plan_id
      assert cev.ocel_event.attributes["root_plan_id"] == "plan-1"
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

  describe "execute/4 without an engine" do
    test "every non-engine decision is a noop; none raises" do
      for d <- [:close, :refuse_stale, :refuse_malformed, :reobserve] do
        assert d in ReplanRouter.decisions()

        assert {:ok, %{rung: :none, outcome: :noop, decision: ^d}} =
                 ReplanRouter.execute(d, 0, %{evidence: %{}})
      end
    end

    test "a routed :refuse_malformed can be executed by a driver loop" do
      {decision, ev, _} = ReplanRouter.route(obs(goal_met: "yes"), state())
      assert decision == :refuse_malformed

      assert {:ok, %{outcome: :noop, decision: :refuse_malformed}} =
               ReplanRouter.execute(decision, 0, %{evidence: ev})
    end

    test "hddl_replan with missing or non-binary inputs is a typed refusal" do
      assert {:error, {:missing_inputs, [:hddl_domain, :hddl_problem]}} =
               ReplanRouter.execute(:hddl_replan, 0, %{evidence: %{}})

      assert {:error, {:missing_inputs, [:hddl_problem]}} =
               ReplanRouter.execute(:hddl_replan, 0, %{hddl_domain: "(d)", hddl_problem: 7})
    end
  end

  describe "canonical digests" do
    test "the trigger hash renders the attempt as canonical strings, not inspect/1" do
      s1 = %{state() | rung: :session_replan}
      a = {:session_replan, :exhausted}
      {:hddl_replan, ev, _} = ReplanRouter.route(obs(attempt: a), s1)

      expected =
        PlanLineage.digest(%{
          "attempt" => ["session_replan", "exhausted"],
          "episode_id" => s1.episode_id,
          "event_id" => nil,
          "plan_id" => "plan-1:g1:hddl_replan",
          "replaced_plan_id" => "plan-1",
          "root_plan_id" => "plan-1",
          "rung" => :hddl_replan
        })

      assert ev.trigger.trigger_hash == expected
      assert ev.lineage.plan_id == "plan-1:g1:hddl_replan"

      {:session_replan, ev0, _} = ReplanRouter.route(obs([]), state())

      assert ev0.trigger.trigger_hash ==
               PlanLineage.digest(%{
                 "attempt" => nil,
                 "episode_id" => state().episode_id,
                 "event_id" => nil,
                 "plan_id" => "plan-1:g1:session_replan",
                 "replaced_plan_id" => "plan-1",
                 "root_plan_id" => "plan-1",
                 "rung" => :session_replan
               })
    end

    test "a replay with the same :observed_at yields byte-identical OCEL events" do
      o = obs(observed_at: "2026-09-25T12:00:00Z", event_id: "e1", admitted: true)
      {d1, ev1, st1} = ReplanRouter.route(o, state())
      {d2, ev2, st2} = ReplanRouter.route(o, state())
      assert d1 == d2
      assert ev1.ocel_event.event_time == "2026-09-25T12:00:00Z"
      assert :erlang.term_to_binary(ev1) == :erlang.term_to_binary(ev2)

      assert :erlang.term_to_binary(ReplanRouter.events(st1)) ==
               :erlang.term_to_binary(ReplanRouter.events(st2))
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
          assert length(ReplanRouter.events(st2)) == length(ReplanRouter.events(st)) + 1
          assert List.last(ReplanRouter.events(st2)) == ev.ocel_event
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

      ids = Enum.map(ReplanRouter.events(st), & &1.event_id)
      assert ids == Enum.uniq(ids)
      assert Enum.all?(ReplanRouter.events(st), &(&1.attributes["case_id"] == "run-t"))
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

    test "keys are sorted explicitly even for maps large enough to iterate unsorted" do
      keys = for i <- 0..39, do: "k" <> String.pad_leading(Integer.to_string(i), 2, "0")
      map = Map.new(keys, &{&1, 1})
      # >32 keys: Elixir's own iteration order is not sorted, so this pins the sort
      refute Map.keys(map) == Enum.sort(keys)

      expected = "{" <> Enum.map_join(Enum.sort(keys), ",", &~s("#{&1}":1)) <> "}"
      assert PlanLineage.canonical_json(map) == expected
    end

    test "inputs that would collide are refused, not silently merged" do
      assert_raise ArgumentError, ~r/two keys/, fn ->
        PlanLineage.canonical_json(%{:a => 1, "a" => 2})
      end

      assert_raise ArgumentError, ~r/keys must be strings or atoms/, fn ->
        PlanLineage.digest(%{1 => "x"})
      end

      assert_raise ArgumentError, ~r/tuple/, fn -> PlanLineage.digest({:a, :b}) end
      assert PlanLineage.digest(%{"1" => "x"}) == PlanLineage.digest(%{:"1" => "x"})
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
