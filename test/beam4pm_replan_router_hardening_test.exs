defmodule BeamPM.ReplanRouterHardeningTest do
  @moduledoc """
  Adversarial court for `BeamPM.ReplanRouter` (beam4pm PR #91, v26.9.26
  harden round). Each describe block closes one court finding on a57d4af4
  and keeps it closed as a permanent guard:

    * M1 -- a self-asserted `admitted: true` with a fresh `event_id` reset the
      rung without limit (the monotone ladder could be pinned at the bottom);
    * M2 -- refusal events used wall-clock time even when the observation
      carried a valid `:observed_at` (replay was not byte-identical);
    * L1 -- `policy_digest/1` equates an atom with its string twin, but
      following matched exact terms (a digest-admitted plan was not followed);
    * L2 -- `new/1` raised `FunctionClauseError` / `KeyError` where the
      contract promises `ArgumentError`;
    * L3 -- top-level string keys were dropped silently (a `"goal_met"` key
      in an observation, an `"universal_plan"` option in `new/1`).

  Chicago style: real structs, real sha256, state-based assertions on the
  returned decision, evidence and state. No engine, no test doubles.
  """

  use ExUnit.Case, async: true

  alias BeamPM.{PlanLineage, ReplanRouter}
  alias BeamPM.Types.EventTriggeredPlanning

  @preimage %{subject: "sha-subject", pack: "sha-pack", policy: "sha-policy", world: "sha-world"}
  @t "2026-09-26T12:00:00Z"

  defp state(extra \\ []) do
    ReplanRouter.new(
      Keyword.merge([plan_id: "plan-h", preimage: @preimage, run_id: "run-h"], extra)
    )
  end

  defp obs(extra) do
    Map.merge(%{preimage: @preimage, conformance: :deviates, plan_valid: false}, Map.new(extra))
  end

  defp rung_index(r), do: Enum.find_index(ReplanRouter.rungs(), &(&1 == r))

  describe "M1: event-triggered resets are bounded" do
    test "fresh admitted events reset at most :max_episodes times" do
      s = %{state(max_episodes: 2) | rung: :hddl_replan}

      {d1, ev1, s1} = ReplanRouter.route(obs(event_id: "e1", admitted: true), s)
      assert d1 == :session_replan
      assert %EventTriggeredPlanning{event_id: "e1"} = ev1.episode
      assert s1.episodes == 1

      s1 = %{s1 | rung: :hddl_replan}
      {d2, ev2, s2} = ReplanRouter.route(obs(event_id: "e2", admitted: true), s1)
      assert d2 == :session_replan
      assert %EventTriggeredPlanning{event_id: "e2"} = ev2.episode
      assert s2.episodes == 2

      s2 = %{s2 | rung: :hddl_replan}
      {d3, ev3, s3} = ReplanRouter.route(obs(event_id: "e3", admitted: true), s2)
      assert d3 == :hddl_replan
      refute Map.has_key?(ev3, :episode)

      assert ev3.episode_refused == %{
               reason: :episode_budget_exhausted,
               event_id: "e3",
               episodes: 2,
               max_episodes: 2
             }

      assert s3.episodes == 2
      assert s3.episode_id == s2.episode_id
      assert MapSet.member?(s3.seen_events, "e3")
    end

    test "max_episodes: 0 never resets; the ladder stays monotone" do
      s = %{state(max_episodes: 0) | rung: :strategic_recompile}
      {d, ev, st} = ReplanRouter.route(obs(event_id: "e-new", admitted: true), s)
      assert d == :strategic_recompile
      assert ev.episode_refused.reason == :episode_budget_exhausted
      assert st.rung == :strategic_recompile
    end

    test "a forged stream of fresh admitted events cannot pin the ladder low" do
      # Each forged observation reports the held rung as exhausted AND a
      # never-seen event id. Before the fix every one reset to :none and
      # re-climbed to :session_replan forever.
      final =
        Enum.reduce(1..60, state(), fn i, st ->
          attempt = if st.rung == :none, do: nil, else: {st.rung, :exhausted}

          {_d, _ev, st2} =
            ReplanRouter.route(
              obs(event_id: "forged-#{i}", admitted: true, attempt: attempt),
              st
            )

          st2
        end)

      assert final.rung == :strategic_recompile
      assert final.episodes == 8
      assert final.max_episodes == 8
    end

    test "after the budget is spent the rung never decreases on any event" do
      Enum.reduce(1..40, state(max_episodes: 1), fn i, st ->
        o =
          obs(
            event_id: "e#{rem(i, 7)}",
            admitted: rem(i, 3) != 0,
            attempt: if(st.rung == :none, do: nil, else: {st.rung, :exhausted})
          )

        {_, _, st2} = ReplanRouter.route(o, st)
        if st.episodes >= 1, do: assert(rung_index(st2.rung) >= rung_index(st.rung))
        assert st2.episodes <= 1
        st2
      end)
    end

    test "a duplicate delivery of the budget-refused event stays a replay" do
      s = %{state(max_episodes: 0) | rung: :hddl_replan}
      {_, _, s1} = ReplanRouter.route(obs(event_id: "dup", admitted: true), s)
      {_, ev2, _} = ReplanRouter.route(obs(event_id: "dup", admitted: true), s1)
      refute Map.has_key?(ev2, :episode_refused)
      refute Map.has_key?(ev2, :episode)
    end
  end

  describe "M2: refusal events replay byte-identically" do
    defp policy_plan,
      do: %{"policy" => [%{"state" => "s0", "action" => "flip"}], "solved" => true}

    defp refusal_cases do
      pre = %{@preimage | policy: ReplanRouter.policy_digest(policy_plan())}
      held = ReplanRouter.new(plan_id: "plan-h", preimage: pre, universal_plan: policy_plan())
      mutated = put_in(held.universal_plan["policy"], [%{"state" => "s0", "action" => "x"}])

      [
        {:stale, state(), obs(observed_at: @t, preimage: %{@preimage | world: "drift"}),
         :refuse_stale},
        {:policy, mutated, %{preimage: pre, observed_at: @t}, :refuse_stale},
        {:ambiguous, state(),
         obs(observed_at: @t, preimage: Map.put(@preimage, "world", "sha-world")),
         :refuse_malformed},
        {:malformed_field, state(), obs(observed_at: @t, goal_met: "yes"), :refuse_malformed},
        {:non_atom_keys, state(), obs(observed_at: @t) |> Map.put("goal_met", true),
         :refuse_malformed}
      ]
    end

    test "every refusal takes a valid :observed_at and is byte-identical on replay" do
      for {name, st, o, expected} <- refusal_cases() do
        {d1, ev1, st1} = ReplanRouter.route(o, st)
        {d2, ev2, st2} = ReplanRouter.route(o, st)

        assert d1 == expected, "#{name}: #{inspect(d1)}"
        assert d1 == d2
        assert ev1.ocel_event.event_time == @t, "#{name} used #{ev1.ocel_event.event_time}"
        assert :erlang.term_to_binary(ev1) == :erlang.term_to_binary(ev2), "#{name}"

        assert :erlang.term_to_binary(ReplanRouter.events(st1)) ==
                 :erlang.term_to_binary(ReplanRouter.events(st2))
      end
    end

    test "a refusal never echoes the unvalidated observed event id" do
      o = obs(observed_at: @t, event_id: "e-x", goal_met: "yes")
      {:refuse_malformed, ev, _} = ReplanRouter.route(o, state())
      assert ev.ocel_event.attributes["observed_event_id"] == nil
    end

    test "a malformed :observed_at is itself refused and never becomes event_time" do
      {d, ev, _} = ReplanRouter.route(obs(observed_at: "yesterday"), state())
      assert d == :refuse_malformed
      assert :observed_at in ev.fields
      refute ev.ocel_event.event_time == "yesterday"
    end
  end

  describe "L1: following uses the digest's equivalence" do
    @string_plan %{
      "solved" => true,
      "policy" => [%{"state" => "s0", "action" => "flip"}, %{"state" => "s1", "action" => "go"}]
    }
    @atom_plan %{
      solved: true,
      policy: [%{state: :s0, action: "flip"}, %{state: :s1, action: "go"}]
    }

    defp held(plan) do
      pre = %{@preimage | policy: ReplanRouter.policy_digest(plan)}
      ReplanRouter.new(plan_id: "plan-h", preimage: pre, universal_plan: plan)
    end

    test "an atom-keyed plan and its string twin share one digest" do
      assert ReplanRouter.policy_digest(@atom_plan) == ReplanRouter.policy_digest(@string_plan)
    end

    test "both twins follow both spellings of the state id identically" do
      for plan <- [@string_plan, @atom_plan], ps <- ["s1", :s1] do
        st = held(plan)
        o = %{preimage: st.admitted_preimage, conformance: :deviates, policy_state: ps}
        assert {:follow_policy, ev, _} = ReplanRouter.route(o, st)
        assert ev.action == "go"
      end
    end

    test "a state id the digest distinguishes is not followed" do
      plan = %{"policy" => [%{"state" => "3", "action" => "a"}]}
      st = held(plan)
      o = %{preimage: st.admitted_preimage, conformance: :deviates, policy_state: 3}
      assert {:session_replan, _, _} = ReplanRouter.route(o, st)
      refute PlanLineage.canonical_json(3) == PlanLineage.canonical_json("3")
    end

    test "a plan carrying both key spellings can never be admitted" do
      both = Map.put(@string_plan, :policy, @string_plan["policy"])

      assert_raise ArgumentError, ~r/two keys/, fn ->
        ReplanRouter.policy_digest(both)
      end
    end

    test "a non-scalar or boolean :policy_state is refused as malformed" do
      st = held(@string_plan)

      for ps <- [true, false, %{"s" => 1}, ["s0"], 1.5] do
        o = %{preimage: st.admitted_preimage, conformance: :deviates, policy_state: ps}
        assert {:refuse_malformed, ev, _} = ReplanRouter.route(o, st)
        assert :policy_state in ev.fields
      end
    end
  end

  describe "L2: new/1 raises ArgumentError for every malformed input" do
    test "malformed option containers and values" do
      base = [plan_id: "p", preimage: @preimage]

      bad = [
        42,
        "plan",
        [:plan_id],
        [{"plan_id", "p"}, {:preimage, @preimage}],
        Keyword.put(base, :plan_id, 123),
        Keyword.put(base, :plan_id, ""),
        Keyword.put(base, :plan_id, nil),
        Keyword.put(base, :preimage, "not-a-map"),
        Keyword.put(base, :preimage, nil),
        Keyword.put(base, :universal_plan, "not-a-map"),
        Keyword.put(base, :universal_plan, [%{"state" => "s0"}]),
        Keyword.put(base, :run_id, :run),
        Keyword.put(base, :episode_id, ""),
        Keyword.put(base, :max_episodes, -1),
        Keyword.put(base, :max_episodes, 1.0),
        Keyword.put(base, :foo, 1),
        [plan_id: "p"],
        [preimage: @preimage]
      ]

      for opts <- bad do
        assert_raise ArgumentError, fn -> ReplanRouter.new(opts) end
      end
    end

    test "a well-formed map of options is accepted" do
      st = ReplanRouter.new(%{plan_id: "p", preimage: @preimage, max_episodes: 3})
      assert st.max_episodes == 3
      assert st.current_plan_id == "p"
    end
  end

  describe "L3: string keys are never dropped silently" do
    test "a string-keyed universal_plan option raises instead of being ignored" do
      plan = %{"policy" => []}
      pre = %{@preimage | policy: ReplanRouter.policy_digest(plan)}

      assert_raise ArgumentError, ~r/option keys/, fn ->
        ReplanRouter.new(%{:plan_id => "p", :preimage => pre, "universal_plan" => plan})
      end
    end

    test "an observation with a string \"goal_met\" key is refused, not routed" do
      o = obs([]) |> Map.put("goal_met", true)
      assert {:refuse_malformed, ev, st} = ReplanRouter.route(o, state())
      assert ev.reason == :non_atom_keys
      assert ev.non_atom_keys == ["goal_met"]
      assert st.rung == :none
      assert st.generation == 0
    end

    test "a string \"preimage\" key is refused as non-atom, before any digest compare" do
      o = %{"preimage" => @preimage, conformance: :conforms, plan_valid: true}
      assert {:refuse_malformed, ev, _} = ReplanRouter.route(o, state())
      assert ev.reason == :non_atom_keys
    end
  end

  describe "event recording cost does not grow with history" do
    # Court finding of the v26.9.26 bench (bench/replan_router_bench.exs): the
    # a57d4af4 router appended with `events ++ [event]`, so one :continue on a
    # 4_000-event state cost ~25x the same route on a fresh state. Recording
    # is now O(1); the minimum over repeated timings (robust to host load)
    # must stay within 4x. The quadratic mutant measured 25x.
    defp min_ns(fun) do
      for(_ <- 1..300, do: fun.() |> elem(0)) |> Enum.min()
    end

    test "a route on a 4_000-event state costs about the same as on a fresh one" do
      cont = obs(conformance: :conforms, plan_valid: true, observed_at: @t)

      long =
        Enum.reduce(1..4_000, state(), fn _, st ->
          {_, _, st} = ReplanRouter.route(cont, st)
          st
        end)

      assert length(ReplanRouter.events(long)) == 4_000
      assert hd(long.events_rev).event_id == "run-h-4000-replan_router.continue"

      fresh = state()
      time = fn st -> fn -> :timer.tc(fn -> ReplanRouter.route(cont, st) end, :nanosecond) end end
      _warm = {min_ns(time.(fresh)), min_ns(time.(long))}
      ratio = min_ns(time.(long)) / max(min_ns(time.(fresh)), 1)
      assert ratio < 4.0, "long-history route is #{Float.round(ratio, 2)}x a fresh route"
    end
  end

  describe "reordering and duplicate delivery" do
    test "the same observation delivered twice yields the same decision twice" do
      o = obs(observed_at: @t)
      {d1, _, s1} = ReplanRouter.route(o, state())
      {d2, _, s2} = ReplanRouter.route(o, s1)
      assert d1 == :session_replan
      assert d2 == :session_replan
      assert s2.generation == 2
      assert :ok = PlanLineage.verify(s2.lineage)
    end

    test "reordered attempts cannot skip rungs" do
      s = state()
      {_, _, s1} = ReplanRouter.route(obs(attempt: {:hddl_replan, :exhausted}), s)
      assert s1.rung == :session_replan
      {_, ev, s2} = ReplanRouter.route(obs(attempt: {:hddl_replan, :exhausted}), s1)
      assert s2.rung == :session_replan
      assert ev.attempt_ignored == {:hddl_replan, :exhausted}
    end
  end
end
