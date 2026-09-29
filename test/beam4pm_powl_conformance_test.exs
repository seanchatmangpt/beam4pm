defmodule BeamPM.PowlConformanceTest do
  @moduledoc """
  Chicago-style, real-engine test of `BeamPM.PowlConformance.check_conformance/3`
  -- no mocks: a real OCEL log built in-test, real `ocel_discover_powl`,
  real `discover_alphappp`, real `align_trace`, real `compute_fitness`, all
  against the real rust4pm wasm engine.
  """
  use ExUnit.Case, async: false

  alias BeamPM.Ferroplan
  alias BeamPM.PowlConformance
  alias BeamPM.Rust4PM

  setup_all do
    case Rust4PM.start() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok
  end

  # Real 6-phase meeting sequence (Step 3's HDDL-solved FreedomGym plan):
  # open -> trust_god -> clean_house -> help_others -> fellowship -> close.
  @phases ["open", "trust_god", "clean_house", "help_others", "fellowship", "close"]

  @planning_domain """
  (define (domain rooms)
    (:requirements :strips :typing)
    (:types room)
    (:predicates (at ?r - room) (link ?a - room ?b - room))
    (:action go
      :parameters (?a - room ?b - room)
      :precondition (and (at ?a) (link ?a ?b))
      :effect (and (at ?b) (not (at ?a)))))
  )
  """

  @planning_problem """
  (define (problem three-room)
    (:domain rooms)
    (:objects a b c - room)
    (:init (at a) (link a b) (link b c) (link c b))
    (:goal (at b)))
  """

  defp build_reference_ocel! do
    assert_ok = fn {:ok, v} -> v end

    {:ok, %{"ocel_handle" => h}} = Rust4PM.ocel_new()

    for phase <- @phases, do: {:ok, _} = Rust4PM.ocel_add_event_type(h, phase)
    {:ok, _} = Rust4PM.ocel_add_object_type(h, "meeting")

    # 3 reference meetings, each running the full 6-phase sequence in order,
    # at distinct (but internally ordered) timestamps -- real OCEL data, not
    # a fixture file.
    for {meeting_id, base_hour} <- [{"g1", 10}, {"g2", 14}, {"g3", 18}] do
      {:ok, _} = Rust4PM.ocel_add_object(h, meeting_id, "meeting")

      @phases
      |> Enum.with_index()
      |> Enum.each(fn {phase, idx} ->
        ts =
          "2026-01-01T#{String.pad_leading(Integer.to_string(base_hour), 2, "0")}:" <>
            "#{String.pad_leading(Integer.to_string(idx), 2, "0")}:00+00:00"

        {:ok, _} =
          Rust4PM.ocel_add_event(h, "e_#{meeting_id}_#{phase}", phase, ts, [
            [meeting_id, "meeting"]
          ])
      end)
    end

    assert_ok.({:ok, h})
    h
  end

  defp start_ferroplan! do
    case Ferroplan.start() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  defp new_planning_session! do
    start_ferroplan!()
    {:ok, %{"handle" => handle}} = Ferroplan.session_new(@planning_domain, @planning_problem)
    {:ok, %{"solved" => true}} = Ferroplan.session_think(handle, 10_000, 64)
    handle
  end

  test "reference model + a conforming trace -> zero-cost alignment, no deviations" do
    ref_ocel = build_reference_ocel!()

    assert {:ok, result} = PowlConformance.check_conformance(ref_ocel, "meeting", @phases)

    assert result.num_reference_traces == 3
    assert result.reference_powl["root"]

    assert result.alignment["cost"] == 0
    assert result.deviations == []
    assert result.conforms == true

    assert result.fitness["log_fitness"] == 1.0
    assert result.fitness["perfectly_fitting_frac"] == 1.0

    {:ok, %{"freed" => true}} = Rust4PM.free_ocel(ref_ocel)
  end

  test "reference model + a deviant trace (skipped phase) -> real nonzero-cost alignment " <>
         "with a real detected deviation, not just a run" do
    ref_ocel = build_reference_ocel!()

    # Deliberately injected deviation: skip "clean_house" entirely.
    deviant_trace = ["open", "trust_god", "help_others", "fellowship", "close"]

    assert {:ok, result} = PowlConformance.check_conformance(ref_ocel, "meeting", deviant_trace)

    refute result.conforms
    assert result.alignment["cost"] > 0
    assert result.deviations != []

    # The specific injected deviation is really visible in the alignment:
    # a model-only move naming clean_house (a "skip" is a model move with
    # no matching log move, i.e. [">>", "clean_house"]).
    assert Enum.any?(result.deviations, fn [log_side, model_side] ->
             model_side == "clean_house" and log_side == ">>"
           end)

    assert result.fitness["log_fitness"] < 1.0

    {:ok, %{"freed" => true}} = Rust4PM.free_ocel(ref_ocel)
  end

  test "reference model + a deviant trace (reordered phases) -> real detected deviation" do
    ref_ocel = build_reference_ocel!()

    # Deliberately injected deviation: swap trust_god and clean_house.
    deviant_trace = ["open", "clean_house", "trust_god", "help_others", "fellowship", "close"]

    assert {:ok, result} = PowlConformance.check_conformance(ref_ocel, "meeting", deviant_trace)

    refute result.conforms
    assert result.alignment["cost"] > 0
    assert result.deviations != []
    assert result.fitness["log_fitness"] < 1.0

    {:ok, %{"freed" => true}} = Rust4PM.free_ocel(ref_ocel)
  end

  describe "conform_observe_replan/6" do
    if not Ferroplan.wasm_built?() do
      @describetag skip: Ferroplan.wasm_missing_reason()
    end

    test "a POWL deviation is evidence, not authority: a still-valid Ferroplan suffix is reused" do
      ref_ocel = build_reference_ocel!()
      session = new_planning_session!()

      deviant_trace = ["open", "trust_god", "help_others", "fellowship", "close"]

      assert {:ok, result} =
               PowlConformance.conform_observe_replan(
                 ref_ocel,
                 "meeting",
                 deviant_trace,
                 session,
                 [{"(at a)", true}]
               )

      refute result.conformance.conforms
      assert result.conformance_gate == :deviation_evidence_only
      assert result.conformance_evidence.conforms == false
      assert result.conformance_evidence.deviations == result.conformance.deviations
      assert "evidence:" <> _ = result.evidence_digest
      assert result.decision == :reuse_suffix
      assert result.trigger == :none
      assert result.plan_valid == true
      assert is_list(result.suffix)
      assert result.suffix != []
      assert result.previous_suffix == result.suffix
      assert result.plan == nil
      assert result.surprises == []

      {:ok, %{"freed" => true}} = Ferroplan.session_free(session)
      {:ok, %{"freed" => true}} = Rust4PM.free_ocel(ref_ocel)
    end

    test "an observed world change invalidates the suffix and triggers a bounded Ferroplan replan" do
      ref_ocel = build_reference_ocel!()
      session = new_planning_session!()

      assert {:ok, %{"valid" => true}} = Ferroplan.session_valid?(session)
      assert {:ok, previous_suffix} = Ferroplan.session_suffix(session)
      assert previous_suffix != []

      assert {:ok, result} =
               PowlConformance.conform_observe_replan(
                 ref_ocel,
                 "meeting",
                 @phases,
                 session,
                 [{"(at a)", false}, {"(at c)", true}],
                 evals: 10_000,
                 mem_mb: 64
               )

      assert result.conformance.conforms
      assert result.conformance_gate == :conforming
      assert result.decision in [:replanned_full, :replanned_following]
      assert result.trigger == :invalid_plan
      assert result.plan_valid == false
      assert result.previous_suffix == previous_suffix
      assert result.plan["solved"] == true
      assert is_list(result.suffix)
      assert result.suffix != []
      assert result.surprises != []

      assert {:ok, %{"valid" => true}} = Ferroplan.session_valid?(session)

      {:ok, %{"freed" => true}} = Ferroplan.session_free(session)
      {:ok, %{"freed" => true}} = Rust4PM.free_ocel(ref_ocel)
    end

    test "the conformance verdict is consumed: swapping it changes every repair receipt hash" do
      ref_ocel = build_reference_ocel!()
      deviant_trace = ["open", "trust_god", "help_others", "fellowship", "close"]

      run = fn trace, observations, opts ->
        session = new_planning_session!()

        {:ok, result} =
          PowlConformance.conform_observe_replan(
            ref_ocel,
            "meeting",
            trace,
            session,
            observations,
            opts
          )

        {:ok, %{"freed" => true}} = Ferroplan.session_free(session)
        result
      end

      stable = [{"(at a)", true}]
      ok = run.(@phases, stable, [])
      ok2 = run.(@phases, stable, [])
      dev = run.(deviant_trace, stable, [])

      # Same world, same decision and plan -- only the conformance verdict differs.
      assert ok.decision == :reuse_suffix and dev.decision == :reuse_suffix
      assert ok.plan_id == dev.plan_id
      assert ok.evidence_digest == ok2.evidence_digest
      assert ok.event_id == ok2.event_id
      assert ok.plan_memory == ok2.plan_memory
      assert ok.evidence_digest != dev.evidence_digest
      assert ok.event_id != dev.event_id
      assert ok.plan_memory.evidence_hash != dev.plan_memory.evidence_hash

      # The digest is exactly the digest of the recorded conformance evidence.
      assert BeamPM.PowlConformance.conformance_evidence(
               "meeting",
               deviant_trace,
               dev.conformance
             ) ==
               dev.conformance_evidence

      drift = [{"(at a)", false}, {"(at c)", true}]
      d_ok = run.(@phases, drift, event_id: "evt-drift")
      d_dev = run.(deviant_trace, drift, event_id: "evt-drift")
      assert d_ok.trigger == :invalid_plan and d_dev.trigger == :invalid_plan
      assert d_ok.plan_id == d_dev.plan_id

      assert d_ok.dynamic_replan_trigger.trigger_hash !=
               d_dev.dynamic_replan_trigger.trigger_hash

      assert d_ok.plan_lineage.lineage_hash != d_dev.plan_lineage.lineage_hash

      {:ok, %{"freed" => true}} = Rust4PM.free_ocel(ref_ocel)
    end

    test "on_deviation: :refuse_reuse turns a deviation into a bounded replan; conformance still reuses" do
      ref_ocel = build_reference_ocel!()
      deviant_trace = ["open", "clean_house", "trust_god", "help_others", "fellowship", "close"]

      session = new_planning_session!()
      {:ok, previous_suffix} = Ferroplan.session_suffix(session)

      assert {:ok, refused} =
               PowlConformance.conform_observe_replan(
                 ref_ocel,
                 "meeting",
                 deviant_trace,
                 session,
                 [{"(at a)", true}],
                 on_deviation: :refuse_reuse,
                 event_id: "evt-deviation"
               )

      refute refused.conformance.conforms
      assert refused.conformance_gate == :deviation_refused_reuse
      assert refused.decision == :replanned_full
      assert refused.trigger == :evidence_refused_reuse
      assert refused.plan_valid == true
      assert refused.previous_suffix == previous_suffix
      assert refused.plan["solved"] == true
      assert refused.dynamic_replan_trigger.event_id == "evt-deviation"
      assert byte_size(refused.dynamic_replan_trigger.trigger_hash) == 64
      assert refused.authority_ceiling == :select
      {:ok, %{"freed" => true}} = Ferroplan.session_free(session)

      session = new_planning_session!()

      assert {:ok, conforming} =
               PowlConformance.conform_observe_replan(
                 ref_ocel,
                 "meeting",
                 @phases,
                 session,
                 [{"(at a)", true}],
                 on_deviation: :refuse_reuse
               )

      assert conforming.conformance_gate == :conforming
      assert conforming.decision == :reuse_suffix
      assert conforming.dynamic_replan_trigger == nil
      {:ok, %{"freed" => true}} = Ferroplan.session_free(session)

      {:ok, %{"freed" => true}} = Rust4PM.free_ocel(ref_ocel)
    end

    test "an unknown deviation policy is refused before conformance or planning runs" do
      # Handles 0/0 are never live: a typed refusal proves no engine was consulted.
      assert {:error, {:option_refused, :on_deviation, :ignore}} =
               PowlConformance.conform_observe_replan(0, "meeting", @phases, 0, [],
                 on_deviation: :ignore
               )
    end
  end
end
