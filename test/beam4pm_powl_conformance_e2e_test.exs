defmodule BeamPM.PowlConformanceE2ETest do
  @moduledoc """
  Step 5, closing leg: reads the real, ingest-confirmed OCEL v2 events
  captured by ash_a2a's real end-to-end test
  (`ash_a2a/test/ash_a2a_freedom_gym_ocel_conformance_e2e_test.exs` --
  real HDDL plan -> real A2A dispatch -> real HTTP POST to beam4pm's own
  `BeamPM.OcelIngest.Router`, real 201-confirmed echoes) from
  `qualification/gym_bridge/{reference,deviant}_ocel_events.json`,
  rebuilds a real in-process OCEL log from that real captured data (the
  router itself has no persistence/query surface -- see this file's own
  disclosure and the ash_a2a test's moduledoc), and runs
  `BeamPM.PowlConformance.check_conformance/3` for real, asserting the
  deliberately injected `clean_house`-skip deviation is really detected.

  Skips (does not fail) if the capture files are absent -- they are
  produced by running the ash_a2a-side test first
  (`mix test test/ash_a2a_freedom_gym_ocel_conformance_e2e_test.exs
  --include external_api`, from the ash_a2a repo), which this test does
  not invoke itself (cross-repo `mix test` invocation is out of scope for
  a single ExUnit run).
  """
  use ExUnit.Case, async: false

  alias BeamPM.PowlConformance
  alias BeamPM.Rust4PM

  @capture_dir Path.expand("../qualification/gym_bridge", __DIR__)
  @reference_path Path.join(@capture_dir, "reference_ocel_events.json")
  @deviant_path Path.join(@capture_dir, "deviant_ocel_events.json")

  setup_all do
    case Rust4PM.start() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok
  end

  defp captures_available? do
    File.exists?(@reference_path) and File.exists?(@deviant_path)
  end

  defp load_events!(path) do
    path |> File.read!() |> JSON.decode!() |> Map.fetch!("events")
  end

  # Rebuilds a real in-process OCEL log (ocel_new + real ocel_add_event
  # calls) from the real captured event JSON -- one "meeting" object per
  # distinct meeting_id, one event per captured record, using the
  # record's own real event_time and phase attribute.
  defp ocel_from_captured_events!(events) do
    {:ok, %{"ocel_handle" => h}} = Rust4PM.ocel_new()

    phases = events |> Enum.map(&get_in(&1, ["attributes", "phase"])) |> Enum.uniq()
    for phase <- phases, do: {:ok, _} = Rust4PM.ocel_add_event_type(h, phase)
    {:ok, _} = Rust4PM.ocel_add_object_type(h, "meeting")

    meeting_ids = events |> Enum.map(&get_in(&1, ["attributes", "meeting_id"])) |> Enum.uniq()
    for mid <- meeting_ids, do: {:ok, _} = Rust4PM.ocel_add_object(h, mid, "meeting")

    Enum.each(events, fn event ->
      %{"event_id" => id, "event_time" => time, "attributes" => %{"phase" => phase, "meeting_id" => mid}} =
        event

      {:ok, _} = Rust4PM.ocel_add_event(h, id, phase, time, [[mid, "meeting"]])
    end)

    h
  end

  test "real captured reference + deviant traces -- real POWL conformance detects the real " <>
         "injected clean_house-skip deviation from the real ash_a2a e2e run" do
    unless captures_available?() do
      IO.puts(
        "SKIPPED: #{@reference_path} / #{@deviant_path} not found. Run, from the ash_a2a repo:\n" <>
          "  mix test test/ash_a2a_freedom_gym_ocel_conformance_e2e_test.exs --include external_api\n" <>
          "first to produce the real captured OCEL events this test conforms against."
      )
    else
      reference_events = load_events!(@reference_path)
      deviant_events = load_events!(@deviant_path)

      assert length(reference_events) == 18
      assert length(deviant_events) == 5

      ref_ocel = ocel_from_captured_events!(reference_events)

      deviant_phase_sequence =
        deviant_events
        |> Enum.sort_by(& &1["event_time"])
        |> Enum.map(&get_in(&1, ["attributes", "phase"]))

      # The real captured deviant trace really is missing clean_house --
      # ground truth from the real ash_a2a run, not assumed here.
      assert deviant_phase_sequence == ["open", "trust_god", "help_others", "fellowship", "close"]

      assert {:ok, result} = PowlConformance.check_conformance(ref_ocel, "meeting", deviant_phase_sequence)

      refute result.conforms
      assert result.alignment["cost"] > 0
      assert result.deviations != []

      assert Enum.any?(result.deviations, fn [log_side, model_side] ->
               model_side == "clean_house" and log_side == ">>"
             end)

      assert result.fitness["log_fitness"] < 1.0
      assert result.num_reference_traces == 3

      {:ok, %{"freed" => true}} = Rust4PM.free_ocel(ref_ocel)
    end
  end
end
