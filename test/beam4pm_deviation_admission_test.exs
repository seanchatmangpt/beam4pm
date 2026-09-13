# Hand-authored qualification (not ggen-generated) -- see
# bap:hand_authored_test_deviation_admission in ontology.ttl.
defmodule BeamPM.DeviationAdmissionTest do
  @moduledoc """
  Chicago-style, real-engine test: runs `BeamPM.PowlConformance.check_conformance/3`
  against a real deviating trace (the exact fixture shape used in
  `test/beam4pm_powl_conformance_test.exs`), then calls
  `BeamPM.DeviationAdmission.admit_deviation/4` and asserts the REAL
  resulting file content on disk contains the new individual -- reads the
  file back, never asserts only on a return value.

  Writes to a real temp copy of `ontology.ttl` (via `System.tmp_dir!/0`), not
  the checked-in ontology file itself, so running this test suite never
  mutates the repo's real ontology as a side effect of `mix test`.
  """
  use ExUnit.Case, async: true

  alias BeamPM.DeviationAdmission
  alias BeamPM.PowlConformance
  alias BeamPM.Rust4PM

  setup_all do
    case Rust4PM.start() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok
  end

  @phases ["open", "trust_god", "clean_house", "help_others", "fellowship", "close"]

  defp build_reference_ocel! do
    {:ok, %{"ocel_handle" => h}} = Rust4PM.ocel_new()

    for phase <- @phases, do: {:ok, _} = Rust4PM.ocel_add_event_type(h, phase)
    {:ok, _} = Rust4PM.ocel_add_object_type(h, "meeting")

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

    h
  end

  defp temp_ontology_copy! do
    real_path = Path.join(File.cwd!(), "ontology.ttl")
    tmp_path = Path.join(System.tmp_dir!(), "ontology_deviation_admission_test_#{System.unique_integer([:positive])}.ttl")
    File.cp!(real_path, tmp_path)
    tmp_path
  end

  test "a real detected deviation is admitted as a real bpm:ProcessDeviation individual on disk" do
    ref_ocel = build_reference_ocel!()

    # Same injected deviation as PowlConformanceTest: skip "clean_house".
    deviant_trace = ["open", "trust_god", "help_others", "fellowship", "close"]

    assert {:ok, result} = PowlConformance.check_conformance(ref_ocel, "meeting", deviant_trace)
    refute result.conforms
    assert result.deviations != []

    tmp_ontology = temp_ontology_copy!()
    before_content = File.read!(tmp_ontology)

    assert {:ok, individual_name} =
             DeviationAdmission.admit_deviation(result, "ref-trace-g1", "candidate-trace-deviant-1", tmp_ontology)

    assert is_binary(individual_name)
    assert String.starts_with?(individual_name, "process_deviation_")

    after_content = File.read!(tmp_ontology)

    assert after_content =~ "bap:#{individual_name} a bpm:ProcessDeviation ;"
    assert after_content =~ ~s(bpm:deviationReferenceTrace "ref-trace-g1")
    assert after_content =~ ~s(bpm:deviationCandidateTrace "candidate-trace-deviant-1")
    assert after_content =~ "bpm:deviationActivity \">>/clean_house\""
    assert after_content =~ "bpm:deviationStatus \"observed\""
    assert after_content =~ "bpm:deviationTimestamp"

    # The prior real content is preserved -- this is an append, not a
    # destructive rewrite.
    assert String.starts_with?(after_content, String.trim_trailing(before_content))

    File.rm!(tmp_ontology)

    {:ok, %{"freed" => true}} = Rust4PM.free_ocel(ref_ocel)
  end

  test "a conforming result is a real no-op -- nothing admitted, file untouched" do
    ref_ocel = build_reference_ocel!()

    assert {:ok, result} = PowlConformance.check_conformance(ref_ocel, "meeting", @phases)
    assert result.conforms

    tmp_ontology = temp_ontology_copy!()
    before_content = File.read!(tmp_ontology)

    assert {:ok, :conforms} =
             DeviationAdmission.admit_deviation(result, "ref-trace-g1", "candidate-trace-conforming", tmp_ontology)

    after_content = File.read!(tmp_ontology)
    assert after_content == before_content

    File.rm!(tmp_ontology)

    {:ok, %{"freed" => true}} = Rust4PM.free_ocel(ref_ocel)
  end
end
