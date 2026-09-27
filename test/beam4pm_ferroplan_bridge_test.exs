# Lane W2 (v26.9.25 strategic-autonomic-loop wave 2) -- tests for
# BeamPM.Ferroplan.Bridge. Deterministic by contract: same input MUST give
# byte-identical output for doctrine_to_problem/2 and sight_from_events/1.
# The guarded engine-op tests exercise the REAL current state of the
# generated facade (ops not yet re-rendered -> typed fallback) plus a stub
# module for the post-re-render path, per lane map RESOLUTIONS #10.
defmodule BeamPM.Ferroplan.BridgeTest do
  use ExUnit.Case, async: true

  alias BeamPM.Ferroplan.Bridge

  @domain_text """
  (define (domain logistics)
    (:requirements :strips)
    (:predicates (at ?x))
  )
  """

  @doctrine %{
    domain_text: @domain_text,
    objective_clauses: ["(at truck1 depot)", "(exists (?p) (package ?p))"],
    constraints: ["(always (not (colliding)))", "(sometime (delivered p1))"]
  }

  # ------------------------------------------------------------------
  # a. doctrine_to_problem/2
  # ------------------------------------------------------------------

  describe "doctrine_to_problem/2" do
    test "renders the pinned format with domain name extracted from domain_text" do
      problem = Bridge.doctrine_to_problem(@doctrine, "Loop Episode 42")

      assert problem == """
             (define (problem loop_episode_42)
               (:domain logistics)
               (:objects)
               (:init)
               (:goal (and
                 (at truck1 depot)
                 (exists (?p) (package ?p))
               ))
               (:constraints (and
                 (always (not (colliding)))
                 (sometime (delivered p1))
               ))
             )\
             """
    end

    test "is deterministic: same input, byte-identical output" do
      a = Bridge.doctrine_to_problem(@doctrine, "episode-1")
      b = Bridge.doctrine_to_problem(@doctrine, "episode-1")
      assert a == b
      assert byte_size(a) == byte_size(b)
    end

    test "every objective clause is present in the rendered goal" do
      problem = Bridge.doctrine_to_problem(@doctrine, "e")

      Enum.each(@doctrine.objective_clauses, fn clause ->
        assert problem =~ clause
      end)
    end

    test "every constraint is present in the rendered constraints section" do
      problem = Bridge.doctrine_to_problem(@doctrine, "e")
      section = problem |> String.split("(:constraints (and") |> Enum.at(1)

      Enum.each(@doctrine.constraints, fn constraint ->
        assert section =~ "\n    " <> constraint
      end)
    end

    test "dropping a constraint from the input drops it from the render only" do
      reduced = %{@doctrine | constraints: Enum.drop(@doctrine.constraints, 1)}
      problem = Bridge.doctrine_to_problem(reduced, "e")

      assert problem =~ "(sometime (delivered p1))"
      refute problem =~ "(always (not (colliding)))"
    end

    test "empty clauses render bare (and) groups" do
      problem = Bridge.doctrine_to_problem(%{domain_text: @domain_text}, "e")

      assert problem =~ "(:goal (and))"
      assert problem =~ "(:constraints (and))"
    end

    test "raises when domain_text lacks a (define (domain header" do
      assert_raise ArgumentError, ~r/no `\(define \(domain NAME` header/, fn ->
        Bridge.doctrine_to_problem(%{domain_text: "garbage"}, "e")
      end
    end

    test "raises when the normalized problem name is empty" do
      assert_raise ArgumentError, ~r/normalizes to an empty PDDL name/, fn ->
        Bridge.doctrine_to_problem(@doctrine, "   ")
      end
    end

    test "raises when objective_clauses is not a list of binaries" do
      assert_raise ArgumentError, ~r/objective_clauses/, fn ->
        Bridge.doctrine_to_problem(%{domain_text: @domain_text, objective_clauses: [:ok]}, "e")
      end
    end
  end

  # ------------------------------------------------------------------
  # b. sight_from_events/1
  # ------------------------------------------------------------------

  describe "sight_from_events/1" do
    test "projects a generic event as {type, true}" do
      events = [%{type: "OrderFulfilled", attributes: %{}, relationships: []}]
      assert Bridge.sight_from_events(events) == [{"OrderFulfilled", true}]
    end

    test "uses type@object_id when an object_id attribute is present (string or atom key)" do
      string_keyed = [%{type: "Move", attributes: %{"object_id" => "truck1"}}]
      atom_keyed = [%{type: "Move", attributes: %{object_id: "truck1"}}]

      assert Bridge.sight_from_events(string_keyed) == [{"Move@truck1", true}]
      assert Bridge.sight_from_events(atom_keyed) == [{"Move@truck1", true}]
    end

    test "adds discretized facts only for already-boolean attributes" do
      events = [
        %{
          type: "DeviationObserved",
          attributes: %{"severity" => "high", "counted" => 3, "reviewed" => true, "late" => false},
          relationships: [{"case", "c1"}]
        }
      ]

      facts = Bridge.sight_from_events(events)

      assert facts == [
               {"DeviationObserved", true},
               {"late_false", true},
               {"reviewed_true", true}
             ]
    end

    test "is deterministic regardless of attribute map order and byte-identical across calls" do
      events = [
        %{type: "A", attributes: %{"b" => true, "a" => true, "c" => true}},
        %{type: "B", attributes: %{"z" => false, "y" => true}}
      ]

      one = Bridge.sight_from_events(events)
      two = Bridge.sight_from_events(events)

      assert inspect(one) == inspect(two)
      # attribute facts sorted by name inside each event
      assert one == [
               {"A", true},
               {"a_true", true},
               {"b_true", true},
               {"c_true", true},
               {"B", true},
               {"y_true", true},
               {"z_false", true}
             ]
    end

    test "preserves event order and ignores relationships entirely" do
      events = [
        %{type: "First", attributes: %{}, relationships: [%{whatever: 1}]},
        %{type: "Second", attributes: nil, relationships: []}
      ]

      assert Bridge.sight_from_events(events) == [
               {"First", true},
               {"Second", true}
             ]
    end

    test "empty input gives an empty sight" do
      assert Bridge.sight_from_events([]) == []
    end

    test "raises on an event without a binary type" do
      assert_raise ArgumentError, ~r/binary :type/, fn ->
        Bridge.sight_from_events([%{attributes: %{}}])
      end
    end
  end

  # ------------------------------------------------------------------
  # c. replan_signal/3 (pinned telemetry seam)
  # ------------------------------------------------------------------

  @replan_event [:beam4pm, :ferroplan, :replan_triggered]

  describe "replan_signal/3" do
    setup do
      ref = make_ref()
      test_pid = self()

      :ok =
        :telemetry.attach(
          {:bridge_replan_test, ref},
          @replan_event,
          fn event, measurements, metadata, _ ->
            send(test_pid, {:telemetry_fired, event, measurements, metadata})
          end,
          nil
        )

      on_exit(fn -> :telemetry.detach({:bridge_replan_test, ref}) end)
      %{test_ref: ref}
    end

    test "valid plan / met goal results continue WITHOUT emitting telemetry" do
      assert Bridge.replan_signal({:ok, %{"valid" => true}}, :world_invalid) == :continue
      assert Bridge.replan_signal({:ok, %{"goal_met" => true}}, :stale_plan) == :continue
      refute_received {:telemetry_fired, _, _, _}
    end

    test "invalid plan result replans as the given reason and fires the pinned event" do
      result = {:ok, %{"valid" => false}}

      assert Bridge.replan_signal(result, :world_invalid, trigger_hash: "cafe01") ==
               {:replan, :world_invalid}

      assert_received {:telemetry_fired, @replan_event, measurements, metadata}
      assert is_integer(measurements.duration_native)
      assert metadata == %{trigger_hash: "cafe01", reason: :world_invalid}
    end

    test "goal-not-met and error-envelope results replan; all three reasons accepted" do
      for {result, reason} <- [
            {{:ok, %{"goal_met" => false}}, :stale_plan},
            {{:ok, %{"error" => %{"code" => "FP_MODEL"}}}, :deviation},
            {{:error, {:wasmex, :gone}}, :world_invalid},
            {{:ok, %{"valid" => false}}, :deviation}
          ] do
        assert Bridge.replan_signal(result, reason) == {:replan, reason}
        assert_received {:telemetry_fired, @replan_event, _, %{reason: ^reason}}
      end
    end

    test "derived trigger_hash is deterministic sha256 hex over {reason, result}" do
      result = {:ok, %{"valid" => false}}

      Bridge.replan_signal(result, :stale_plan)
      assert_received {:telemetry_fired, _, _, %{trigger_hash: first}}

      Bridge.replan_signal(result, :stale_plan)
      assert_received {:telemetry_fired, _, _, %{trigger_hash: second}}

      assert first == second
      assert Regex.match?(~r/^[0-9a-f]{64}$/, first)

      expected =
        :crypto.hash(:sha256, :erlang.term_to_binary({:stale_plan, result}))
        |> Base.encode16(case: :lower, padding: false)

      assert first == expected
    end

    test "caller-supplied trigger_hash (the pinned W3 formula's output) wins" do
      Bridge.replan_signal({:error, :x}, :deviation, trigger_hash: "deadbeef")
      assert_received {:telemetry_fired, _, _, %{trigger_hash: "deadbeef", reason: :deviation}}
    end

    test "metadata carries EXACTLY the pinned keys (no extras)" do
      Bridge.replan_signal({:error, :x}, :deviation)
      assert_received {:telemetry_fired, _, _, metadata}
      assert MapSet.new(Map.keys(metadata)) == MapSet.new([:trigger_hash, :reason])
    end

    test "refuses reasons outside the pinned vocabulary and unprobeable shapes" do
      assert_raise FunctionClauseError, fn ->
        Bridge.replan_signal({:ok, %{"valid" => false}}, :because_i_said_so)
      end

      assert_raise ArgumentError, ~r/unprobeable engine result shape/, fn ->
        Bridge.replan_signal({:ok, %{"unexpected" => 1}}, :deviation)
      end

      refute_received {:telemetry_fired, _, _, _}
    end
  end

  # ------------------------------------------------------------------
  # d. guarded engine-op call sites (RESOLUTIONS #10)
  # ------------------------------------------------------------------

  describe "guarded engine ops" do
    defmodule StubEngine do
      def fond_policy_validate(domain, problem, plan, opts) do
        {:ok,
         %{
           "stub" => true,
           "domain" => domain,
           "problem" => problem,
           "plan" => plan,
           "opts" => opts
         }}
      end

      def session_install_plan(handle, plan, opts) do
        {:ok, %{"stub_handle" => handle, "stub_plan" => plan, "stub_opts" => opts}}
      end
    end

    test "generated facade lacks the new ops today -> typed fallback, no raise" do
      refute function_exported?(BeamPM.Ferroplan, :fond_policy_validate, 4)
      refute function_exported?(BeamPM.Ferroplan, :session_install_plan, 3)

      assert Bridge.fond_policy_validate("(d)", "(p)", %{"steps" => []}) ==
               {:error, {:engine_op_unavailable, :fond_policy_validate}}

      assert Bridge.session_install_plan(7, %{"steps" => []}) ==
               {:error, {:engine_op_unavailable, :session_install_plan}}
    end

    test "guarded_engine_call/3 dispatches through function_exported? to a stub (post-re-render shape)" do
      plan = %{"steps" => [["move", "truck1", "depot"]]}

      assert Bridge.guarded_engine_call(
               StubEngine,
               :fond_policy_validate,
               ["(d)", "(p)", plan, []]
             ) ==
               {:ok,
                %{
                  "stub" => true,
                  "domain" => "(d)",
                  "problem" => "(p)",
                  "plan" => plan,
                  "opts" => []
                }}

      assert Bridge.guarded_engine_call(StubEngine, :session_install_plan, [7, plan, []]) ==
               {:ok, %{"stub_handle" => 7, "stub_plan" => plan, "stub_opts" => []}}
    end

    test "guarded_engine_call/3 falls back typed when the target lacks the function" do
      assert Bridge.guarded_engine_call(StubEngine, :no_such_op, []) ==
               {:error, {:engine_op_unavailable, :no_such_op}}
    end
  end
end
