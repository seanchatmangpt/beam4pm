defmodule BeamPM.PowlConformanceTest do
  @moduledoc """
  Chicago-style, real-engine test of `BeamPM.PowlConformance.check_conformance/3`
  -- no mocks: a real OCEL log built in-test, real `ocel_discover_powl`,
  real `discover_alphappp`, real `align_trace`, real `compute_fitness`, all
  against the real rust4pm wasm engine.
  """
  use ExUnit.Case, async: true

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
          Rust4PM.ocel_add_event(h, "e_#{meeting_id}_#{phase}", phase, ts, [[meeting_id, "meeting"]])
      end)
    end

    assert_ok.({:ok, h})
    h
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
end
