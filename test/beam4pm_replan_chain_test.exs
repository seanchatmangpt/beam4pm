# Hand-authored (not ggen-generated). Lane W3
# (docs/jira/v26.9.25/_LANES-strategic-loop.md) — replan-chain tests for
# BeamPM.ReplanTrigger, BeamPM.StalePlanGate, BeamPM.PlanJournal over the
# generated Ash ETS resources (exercised directly per lane map resolution 8:
# the Ash domain module is generator-owned, REFUSED_GENERATOR_OWNED).
defmodule BeamPM.ReplanChainTest do
  use ExUnit.Case, async: false

  alias BeamPM.Ash.Resources.EventTriggeredPlanning
  alias BeamPM.Ash.Resources.DynamicReplanTrigger
  alias BeamPM.Ash.Resources.PlanLineage
  alias BeamPM.Ash.Resources.PlanMemory
  alias BeamPM.PlanJournal
  alias BeamPM.ReplanTrigger
  alias BeamPM.StalePlanGate

  @observed_at "2026-09-25T00:00:00Z"
  @ref_trace "ref-trace-fixed"
  @cand_trace "cand-trace-fixed"
  @deviation_move "act_a/>>"

  defp sha256_hex(binary) do
    :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)
  end

  # Independent recomputation of the two pinned formulas (NOT calling the
  # module under test) so the exact-hash assertions are real gates:
  defp expected_individual_name do
    "process_deviation_" <>
      binary_part(
        sha256_hex(@ref_trace <> @cand_trace <> @deviation_move <> @observed_at),
        0,
        16
      )
  end

  defp expected_trigger_hash do
    sha256_hex(expected_individual_name() <> @observed_at)
  end

  defp deviation_result do
    %{conforms: false, deviations: [[String.split(@deviation_move, "/") |> hd(), ">>"]]}
  end

  defp base_opts do
    [
      plan_id: "plan-alpha",
      event_id: "evt-fixed",
      reference_trace_id: @ref_trace,
      candidate_trace_id: @cand_trace,
      observed_at: @observed_at
    ]
  end

  describe "BeamPM.ReplanTrigger.from_conformance/2" do
    test "conforms:false creates a DynamicReplanTrigger with the exact pinned trigger_hash" do
      {:ok, trigger} = ReplanTrigger.from_conformance(deviation_result(), base_opts())

      assert %DynamicReplanTrigger{} = trigger
      assert trigger.plan_id == "plan-alpha"
      assert trigger.event_id == "evt-fixed"
      assert trigger.trigger_hash == expected_trigger_hash()
      assert Regex.match?(~r/^[0-9a-f]{64}$/, trigger.trigger_hash)

      # Read-back through the real Ash ETS resource (same direct style as
      # test/beam4pm_ash_resources_test.exs:10281-10283).
      assert Enum.any?(Ash.read!(DynamicReplanTrigger), &(&1.id == trigger.id))
    end

    test "conforms:true is a {:ok, :conformant} no-op and creates nothing" do
      before = Ash.read!(DynamicReplanTrigger)

      assert ReplanTrigger.from_conformance(%{conforms: true, deviations: []}, base_opts()) ==
               {:ok, :conformant}

      assert Ash.read!(DynamicReplanTrigger) == before
    end

    test "conforms:false with empty deviations refuses {:error, :no_deviation}" do
      assert ReplanTrigger.from_conformance(%{conforms: false, deviations: []}, base_opts()) ==
               {:error, :no_deviation}
    end

    test "explicit :deviation_individual_name opt wins over derivation" do
      explicit_name = "process_deviation_explicitw3"

      {:ok, trigger} =
        ReplanTrigger.from_conformance(deviation_result(),
          plan_id: "plan-alpha",
          event_id: "evt-fixed",
          deviation_individual_name: explicit_name,
          observed_at: @observed_at
        )

      assert trigger.trigger_hash == sha256_hex(explicit_name <> @observed_at)
    end

    test "missing required opts refuse typed" do
      assert ReplanTrigger.from_conformance(deviation_result(), event_id: "evt") ==
               {:error, {:missing_opt, :plan_id}}

      assert ReplanTrigger.from_conformance(deviation_result(),
               plan_id: "p",
               event_id: "e"
             ) ==
               {:error, {:missing_opt, :reference_trace_id}}
    end

    test "malformed conformance result refuses typed" do
      assert ReplanTrigger.from_conformance(%{conforms: false}, base_opts()) ==
               {:error, :malformed_conformance_result}

      assert ReplanTrigger.from_conformance("not a map", base_opts()) ==
               {:error, :malformed_conformance_result}
    end

    test "emits [:beam4pm, :ferroplan, :replan_triggered] with pinned metadata" do
      handler_id = "beam4pm-replan-chain-test"

      :ok =
        :telemetry.attach(handler_id, [:beam4pm, :ferroplan, :replan_triggered], fn _event,
                                                                                      _measurements,
                                                                                      metadata,
                                                                                      _config ->
          send(self(), {:replan_telemetry, metadata})
        end, nil)

      try do
        {:ok, trigger} = ReplanTrigger.from_conformance(deviation_result(), base_opts())
        hash = trigger.trigger_hash
        assert_received {:replan_telemetry, %{trigger_hash: ^hash, reason: :deviation}}
      after
        :telemetry.detach(handler_id)
      end
    end
  end

  describe "BeamPM.ReplanTrigger.episode/2" do
    test "mints a unique episode_id and persists an EventTriggeredPlanning row" do
      {:ok, ep1} = ReplanTrigger.episode("evt-world-1", "worldhash-" <> String.duplicate("a1", 4))
      {:ok, ep2} = ReplanTrigger.episode("evt-world-2", "worldhash-" <> String.duplicate("b2", 4))

      assert %EventTriggeredPlanning{} = ep1
      assert ep1.event_id == "evt-world-1"
      assert ep1.world_state_hash == "worldhash-a1a1a1a1"
      assert is_binary(ep1.episode_id) and byte_size(ep1.episode_id) > 0
      assert ep1.episode_id != ep2.episode_id, "episode ids must be unique"

      # Stated minting law: UUIDv7 via :uniq when loadable, else crypto hex.
      uuid7? =
        Code.ensure_loaded?(Uniq.UUID) and function_exported?(Uniq.UUID, :uuid7, 0)

      cond do
        uuid7? ->
          assert String.length(ep1.episode_id) == 36

        :else ->
          assert Regex.match?(~r/^[0-9a-f]{32}$/, ep1.episode_id)
      end

      assert Enum.any?(Ash.read!(EventTriggeredPlanning), &(&1.id == ep1.id))
      assert Enum.any?(Ash.read!(EventTriggeredPlanning), &(&1.id == ep2.id))
    end

    test "mint_episode_id/0 never repeats across a bounded burst" do
      ids = for _ <- 1..100, do: ReplanTrigger.mint_episode_id()
      assert Enum.uniq(ids) == ids
    end
  end

  describe "BeamPM.StalePlanGate.check/2" do
    @h1 String.duplicate("ab", 32)
    @h2 String.duplicate("cd", 32)

    test "equal well-formed hashes are {:ok, :fresh}" do
      assert StalePlanGate.check(@h1, @h1) == {:ok, :fresh}
    end

    test "unequal well-formed hashes refuse with the pinned evidence shape" do
      assert StalePlanGate.check(@h1, @h2) ==
               {:error,
                {:stale_plan_refusal,
                 %{admitted_preimage_hash: @h1, observed_preimage_hash: @h2}}}
    end

    test "malformed input refuses typed :malformed_hash" do
      too_short = String.duplicate("ab", 31)
      non_hex = String.duplicate("zz", 32)
      uppercase = String.upcase(@h1)

      assert StalePlanGate.check(too_short, @h1) ==
               {:error, {:stale_plan_refusal, :malformed_hash}}

      assert StalePlanGate.check(@h1, non_hex) ==
               {:error, {:stale_plan_refusal, :malformed_hash}}

      assert StalePlanGate.check(uppercase, uppercase) ==
               {:error, {:stale_plan_refusal, :malformed_hash}}

      assert StalePlanGate.check(123, @h1) ==
               {:error, {:stale_plan_refusal, :malformed_hash}}

      assert StalePlanGate.check(nil, nil) ==
               {:error, {:stale_plan_refusal, :malformed_hash}}
    end
  end

  describe "BeamPM.PlanJournal" do
    test "record_lineage/2 links parent to child with the exact pinned lineage_hash" do
      {:ok, row} = PlanJournal.record_lineage("plan-v1", "plan-v2")

      assert %PlanLineage{} = row
      assert row.plan_id == "plan-v2"
      assert row.parent_plan_id == "plan-v1"
      assert row.lineage_hash == PlanJournal.lineage_hash("plan-v1", "plan-v2")
      assert row.lineage_hash == sha256_hex("plan-v1->plan-v2")

      read_back = Enum.find(Ash.read!(PlanLineage), &(&1.id == row.id))
      assert read_back.parent_plan_id == "plan-v1"
      assert read_back.plan_id == "plan-v2"
    end

    test "archive/2 stores superseded plan evidence with the exact pinned memory_hash" do
      evidence = sha256_hex("plan-v1-body")

      {:ok, row} = PlanJournal.archive("plan-v1", evidence)

      assert %PlanMemory{} = row
      assert row.plan_id == "plan-v1"
      assert row.evidence_hash == evidence
      assert row.memory_hash == PlanJournal.memory_hash("plan-v1", evidence)
      assert row.memory_hash == sha256_hex("plan-v1:" <> evidence)

      read_back = Enum.find(Ash.read!(PlanMemory), &(&1.id == row.id))
      assert read_back.plan_id == "plan-v1"
      assert read_back.evidence_hash == evidence
    end

    test "lineage + memory roundtrip through the Ash ETS resources" do
      {:ok, lineage} = PlanJournal.record_lineage("roundtrip-parent", "roundtrip-child")
      {:ok, memory} = PlanJournal.archive("roundtrip-parent", "evidence-xyz")

      lineage_rows = Ash.read!(PlanLineage)
      memory_rows = Ash.read!(PlanMemory)

      assert Enum.any?(lineage_rows, fn r ->
               r.id == lineage.id and r.parent_plan_id == "roundtrip-parent" and
                 r.plan_id == "roundtrip-child"
             end)

      assert Enum.any?(memory_rows, fn r ->
               r.id == memory.id and r.memory_hash == memory.memory_hash
             end)
    end

    test "empty or non-binary refs refuse typed" do
      assert PlanJournal.record_lineage("", "plan-b") ==
               {:error, {:invalid_argument, :old_plan_ref}}

      assert PlanJournal.record_lineage(nil, "plan-b") ==
               {:error, {:invalid_argument, :old_plan_ref}}

      assert PlanJournal.archive("plan-a", "") ==
               {:error, {:invalid_argument, :evidence_hash}}
    end
  end
end
