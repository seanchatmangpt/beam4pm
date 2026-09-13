defmodule BeamPM.EDSTest do
  @moduledoc """
  Chicago-style, real-engine tests of `BeamPM.EDS` and `BeamPM.EDS.PPCXH1` --
  no mocks: real `BeamPM.PowlConformance.check_conformance/3` against a real
  in-test OCEL log, real `BeamPM.DeviationAdmission.admit_deviation/4`
  against a real temp copy of `ontology.ttl`, real receipt files written to
  a real temp `receipts/eds` directory and independently re-verified via
  `BeamPM.ReceiptChain.verify/2`.
  """
  use ExUnit.Case, async: true

  alias BeamPM.EDS
  alias BeamPM.EDS.Claim
  alias BeamPM.EDS.PPCXH1
  alias BeamPM.PowlConformance
  alias BeamPM.Rust4PM

  setup_all do
    case Rust4PM.start() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok
  end

  setup do
    tmp = Path.join(System.tmp_dir!(), "beam4pm_eds_test_#{System.unique_integer([:positive])}")
    receipts_dir = Path.join(tmp, "receipts/eds")
    File.mkdir_p!(receipts_dir)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp, receipts_dir: receipts_dir}
  end

  describe "BeamPM.EDS state ladder" do
    test "legal, in-order transitions succeed and write a real chained receipt each time", %{
      receipts_dir: receipts_dir
    } do
      claim = EDS.new_claim("t1", "h", "a", "f")
      assert claim.state == :proposed
      assert claim.history == []

      assert {:ok, claim} = EDS.transition(claim, :implemented, %{note: "real"}, receipts_dir)
      assert claim.state == :implemented
      assert [%{state: :implemented, receipt_path: p1}] = claim.history
      assert File.exists?(p1)

      assert {:ok, claim} = EDS.transition(claim, :executable, %{}, receipts_dir)
      assert {:ok, claim} = EDS.transition(claim, :observed, %{}, receipts_dir)
      assert {:ok, claim} = EDS.transition(claim, :verified, %{}, receipts_dir)
      assert claim.state == :verified
      assert length(claim.history) == 4

      # Real receipt content, read back from disk -- not just the return value.
      last_receipt = claim.history |> List.last() |> Map.fetch!(:receipt_path) |> File.read!() |> Jason.decode!()
      assert last_receipt["receipt_schema"] == "beam4pm-brce/v1"
      assert last_receipt["eds_claim_id"] == "t1"
      assert last_receipt["eds_from_state"] == "observed"
      assert last_receipt["eds_to_state"] == "verified"
      assert last_receipt["chain_seq"] == 4
      assert is_binary(last_receipt["prev_receipt_hash"])

      # Real, independent replay -- not the same code path that wrote it.
      assert {:ok, _summary} = EDS.verify(claim, receipts_dir)
    end

    test "skipping a state in the ladder is refused, not silently allowed", %{receipts_dir: receipts_dir} do
      claim = EDS.new_claim("t2", "h", "a", "f")
      assert {:error, {:illegal_transition, :proposed, :verified}} =
               EDS.transition(claim, :verified, %{}, receipts_dir)

      assert {:error, {:illegal_transition, :proposed, :observed}} =
               EDS.transition(claim, :observed, %{}, receipts_dir)
    end

    test "a terminal state (falsified) is reachable from any non-terminal state, then refuses further transitions", %{
      receipts_dir: receipts_dir
    } do
      claim = EDS.new_claim("t3", "h", "a", "f")
      assert {:ok, claim} = EDS.transition(claim, :implemented, %{}, receipts_dir)
      assert {:ok, claim} = EDS.transition(claim, :falsified, %{reason: "real falsifier tripped"}, receipts_dir)
      assert claim.state == :falsified

      assert {:error, {:illegal_transition, :falsified, :executable}} =
               EDS.transition(claim, :executable, %{}, receipts_dir)
    end
  end

  describe "BeamPM.EDS.PPCXH1 (the paper's Section 16 example, deviation-feedback half)" do
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

          {:ok, _} = Rust4PM.ocel_add_event(h, "e_#{meeting_id}_#{phase}", phase, ts, [[meeting_id, "meeting"]])
        end)
      end

      h
    end

    test "a real deviating trace drives the claim through the full ladder to :verified, with the deviation genuinely admitted to a real ontology.ttl copy",
         %{tmp: tmp} do
      ref_ocel = build_reference_ocel!()
      deviant_trace = @phases -- ["clean_house"]

      assert {:ok, result} = PowlConformance.check_conformance(ref_ocel, "meeting", deviant_trace)
      assert result.conforms == false
      assert result.deviations != []

      ontology_copy = Path.join(tmp, "ontology.ttl")
      File.write!(ontology_copy, "# minimal real ontology for this test\n")
      before_bytes = File.read!(ontology_copy)

      # PPCXH1.run/4 internally calls EDS.transition/4 with the default
      # receipts_dir ("receipts/eds") -- exercise it against a real temp
      # cwd-relative path by chdir'ing for the duration of this one call,
      # so the test stays hermetic (no writes under the real repo tree).
      result_claim =
        File.cd!(tmp, fn ->
          PPCXH1.run(result, "g1-g2-g3-reference", "deviant-skip-clean-house", ontology_copy)
        end)

      assert {:ok, %Claim{state: :verified} = claim} = result_claim
      assert length(claim.history) == 4

      after_bytes = File.read!(ontology_copy)
      assert after_bytes != before_bytes
      assert String.contains?(after_bytes, "bpm:ProcessDeviation")

      verified_receipt_path = claim.history |> List.last() |> Map.fetch!(:receipt_path)

      verified_receipt =
        tmp |> Path.join(verified_receipt_path) |> File.read!() |> Jason.decode!()

      assert verified_receipt["eds_to_state"] == "verified"
      assert is_binary(verified_receipt["eds_evidence"]["admitted_individual"])
      assert String.starts_with?(verified_receipt["eds_evidence"]["admitted_individual"], "process_deviation_")

      # Real, independent replay of this claim's own receipt chain.
      assert {:ok, _summary} = File.cd!(tmp, fn -> EDS.verify(claim, "receipts/eds") end)
    end

    test "a conforming trace is refused verification and instead lands on :blocked -- no fabricated deviation admission",
         %{tmp: tmp} do
      ref_ocel = build_reference_ocel!()

      assert {:ok, result} = PowlConformance.check_conformance(ref_ocel, "meeting", @phases)
      assert result.conforms == true

      ontology_copy = Path.join(tmp, "ontology.ttl")
      File.write!(ontology_copy, "# minimal real ontology for this test\n")
      before_bytes = File.read!(ontology_copy)

      result_claim =
        File.cd!(tmp, fn ->
          PPCXH1.run(result, "g1-g2-g3-reference", "conforming-trace", ontology_copy)
        end)

      assert {:ok, %Claim{state: :blocked}} = result_claim
      assert File.read!(ontology_copy) == before_bytes
    end
  end
end
