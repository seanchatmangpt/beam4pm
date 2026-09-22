# Hand-authored qualification (b4p-p4 sa2a-admit parity wave). Ledger row:
# docs/reference/beam4pm_hand_authored_source.md (via WAVE-RECEIPT.md, parity/sa2a-admit).
defmodule BeamPM.Sa2aAdmitParityTest do
  @moduledoc """
  Cross-validation (consent) qualification for ticket b4p-p4: the autofde-lab
  §64 admission court (`autofde sa2a admit`) vs beam4pm's
  `BeamPM.DeviationAdmission.admit_deviation/4` on equivalent candidate
  assertions.

  The two courts guard DIFFERENT laws, so parity here is CONSENT on the
  accept/refuse boundary for shared cases, never identity:

    * lab §64 court: evidentiary FORM gate (non-empty assertion, non-empty
      evidence payload, no error/unsupported evidence keys) over a free-form
      assertion string. It does NOT check semantic referential integrity --
      forged unknown-type / dangling-ref candidates with clean evidence are
      ADMITTED (observed 2026-09-18, pinned below as a tripwire, not hidden).
      Semantic conformance is the separate `sa2a graphlaw validate` engine.
    * beam4pm court: DEVIATION-CONTRACT gate over a real
      `PowlConformance.check_conformance/3` result. It admits one
      `bpm:ProcessDeviation` individual per real detected deviation,
      refuses `conforms: false` with empty `deviations`
      (`{:error, :no_deviation}`), no-ops on `conforms: true`
      (`{:ok, :conforms}` -- a true negative, not a refusal), and refuses
      contract-violating shapes by function-clause (no matching head).

  Positive-control assertion strings are real admitted `bpm:RecordType`
  facts copied verbatim from `ontology.ttl` (read-only source; samples in
  `qualification/fixtures/sa2a_admit/`). The positive-control deviation
  result maps mirror the real `conformance_result` shape (the exact typed
  contract in `lib/beam4pm_powl_conformance.ex`, with the same
  `[log_side, model_side]` move pairs the real engine emits -- bare
  activity names with `">>"` marking the absent side, so the admitted
  `bpm:deviationActivity` is `">>/clean_house"`, exactly as pinned by
  `test/beam4pm_deviation_admission_test.exs`, which runs the full native
  engine; the rust4pm wasm prerequisite is absent in parity worktrees, so
  this file exercises the admission court itself, not the native discovery
  engine).

  Lab runs go through `BeamPM.Dfcm.sa2a_admit/2` -- the pure one-shot CLI
  passthrough added by this wave -- so every lab verdict below is a REAL
  autofde CLI execution, never a reimplementation.
  """

  use ExUnit.Case, async: true

  alias BeamPM.DeviationAdmission
  alias BeamPM.Dfcm

  @fixtures_dir Path.expand("../qualification/fixtures/sa2a_admit", __DIR__)

  defp fixture!(name), do: File.read!(Path.join(@fixtures_dir, name))

  defp temp_ontology_copy! do
    real_path = Path.join(File.cwd!(), "ontology.ttl")
    tmp_path = Path.join(System.tmp_dir!(), "ontology_sa2a_parity_#{System.unique_integer([:positive])}.ttl")
    File.cp!(real_path, tmp_path)
    tmp_path
  end

  # ---------------------------------------------------------------------------
  # Lab §64 court (real CLI runs via the sa2a_admit bridge)
  # ---------------------------------------------------------------------------

  test "lab court admits a real admitted bpm:RecordType fact with provenance evidence" do
    assert {:ok, receipt} =
             Dfcm.sa2a_admit(fixture!("positive_c1_ocel_event_rt.assertion"),
               candidate_id: "cand-parity-c1",
               query_id: "q-parity",
               source: "beam4pm-ontology",
               evidence: %{ontology: "ontology.ttl", subject: "bpm:ocel_event_rt", class: "bpm:RecordType"}
             )

    assert receipt["ok"] == true
    assert receipt["standing"] == "KNOWN"
    assert receipt["reasons"] == ["CONFORMS_TO_SPEC"]
    assert receipt["admitted_assertion"] =~ "bpm:ocel_event_rt a bpm:RecordType"
    assert is_binary(receipt["receipt_id"])
    assert is_binary(receipt["candidate_hash"])
  end

  @doc """
  TRIPWIRE (b4p-p4 consent table, C3/C4): the lab §64 default court is an
  evidentiary-FORM court. Forged unknown-type and dangling-ref candidates
  carrying clean evidence are ADMITTED -- refusal here would mean the lab
  changed courts, and this file then guards the OLD observed behavior until
  the consent table is re-earned. Semantic referential integrity on the lab
  side belongs to `sa2a graphlaw validate`, not `sa2a admit`.
  """
  test "lab court admits forged unknown-type and dangling-ref candidates with clean evidence" do
    for {id, file} <- [
          {"cand-parity-c3", "negative_c3_unknown_type.assertion"},
          {"cand-parity-c4", "negative_c4_dangling_ref.assertion"}
        ] do
      assert {:ok, receipt} =
               Dfcm.sa2a_admit(fixture!(file),
                 candidate_id: id,
                 query_id: "q-parity",
                 source: "beam4pm-ontology",
                 evidence: %{ontology: "ontology.ttl", note: "clean but forged provenance"}
               )

      assert receipt["ok"] == true
      assert receipt["standing"] == "KNOWN"
    end
  end

  test "lab court refuses empty assertion, missing evidence, and error-bearing evidence" do
    empty = Dfcm.sa2a_admit("", candidate_id: "cand-parity-c5", query_id: "q-parity", evidence: %{"k" => "v"})

    assert {:ok, %{"ok" => false, "standing" => "REFUSED", "reasons" => ["EMPTY_ASSERTION"]}} = empty

    no_evidence =
      Dfcm.sa2a_admit(fixture!("negative_c6_no_provenance.assertion"),
        candidate_id: "cand-parity-c6",
        query_id: "q-parity",
        evidence: %{}
      )

    assert {:ok, %{"ok" => false, "standing" => "REFUSED", "reasons" => ["MISSING_EVIDENCE"]}} = no_evidence

    error_evidence =
      Dfcm.sa2a_admit(fixture!("negative_c7_error_evidence.assertion"),
        candidate_id: "cand-parity-c7",
        query_id: "q-parity",
        evidence: %{"error" => "discovery_engine_failed"}
      )

    assert {:ok, %{"ok" => false, "standing" => "REFUSED", "reasons" => ["UNSUPPORTED_OR_ERROR_EVIDENCE"]}} =
             error_evidence
  end

  test "lab bridge always emits valid evidence JSON -- raw CLI BadParameter unreachable via wrapper" do
    # The raw CLI exits 2 on malformed --evidence JSON (observed directly:
    # `autofde sa2a admit -e 'not-json'` -> exit 2). The wrapper JSON-encodes
    # the :evidence term itself, so that failure mode is unreachable through
    # BeamPM.Dfcm.sa2a_admit/2 -- any term becomes valid JSON. A non-map
    # truthy payload (e.g. a bare string) reaches the lab court as a valid
    # non-empty evidence value and is ADMITTED (pinned here): the lab
    # court's evidence gate is membership-style ("error"/"unsupported"
    # keys/substrings), not a map-shape contract.
    assert {:ok, receipt} =
             Dfcm.sa2a_admit("x", candidate_id: "cand-parity-c9", query_id: "q-parity", evidence: "not-json")

    assert receipt["ok"] == true
    assert receipt["standing"] == "KNOWN"
  end

  # ---------------------------------------------------------------------------
  # beam4pm DeviationAdmission court (real file mutation on a temp ontology)
  # ---------------------------------------------------------------------------

  test "beam4pm court admits a real detected deviation as a bpm:ProcessDeviation individual on disk" do
    result = %{
      conforms: false,
      deviations: [[">>", "clean_house"], ["@", "fellowship"]]
    }

    tmp_ontology = temp_ontology_copy!()
    before_content = File.read!(tmp_ontology)

    assert {:ok, individual_name} =
             DeviationAdmission.admit_deviation(result, "ref-trace-g1", "candidate-trace-deviant-1", tmp_ontology)

    assert String.starts_with?(individual_name, "process_deviation_")

    after_content = File.read!(tmp_ontology)
    assert after_content =~ "bap:#{individual_name} a bpm:ProcessDeviation ;"
    assert after_content =~ ~s(bpm:deviationActivity ">>/clean_house")
    assert after_content =~ "bpm:deviationStatus \"observed\""
    assert String.starts_with?(after_content, String.trim_trailing(before_content))

    File.rm!(tmp_ontology)
  end

  test "beam4pm court refuses conforms:false with empty deviations as a contract violation" do
    tmp_ontology = temp_ontology_copy!()

    assert {:error, :no_deviation} =
             DeviationAdmission.admit_deviation(%{conforms: false, deviations: []}, "r", "c", tmp_ontology)

    File.rm!(tmp_ontology)
  end

  test "beam4pm court no-ops on a conforming result -- a true negative, file untouched" do
    tmp_ontology = temp_ontology_copy!()
    before_content = File.read!(tmp_ontology)

    assert {:ok, :conforms} =
             DeviationAdmission.admit_deviation(%{conforms: true, deviations: []}, "r", "c", tmp_ontology)

    assert File.read!(tmp_ontology) == before_content
    File.rm!(tmp_ontology)
  end

  test "beam4pm court refuses contract-violating shapes by function clause" do
    # %{conforms: false} with NO deviations key matches no function head --
    # the beam4pm refusal mechanism for malformed candidates is a clause
    # failure (lab equivalent: MISSING_EVIDENCE / BadParameter), observed
    # here and pinned in the consent table.
    assert_raise FunctionClauseError, fn ->
      DeviationAdmission.admit_deviation(%{conforms: false}, "r", "c", temp_ontology_copy!())
    end
  end

  test "beam4pm court surfaces real file I/O failure as a typed error" do
    missing_path = Path.join(System.tmp_dir!(), "ontology_sa2a_parity_missing_#{System.unique_integer([:positive])}.ttl")

    assert {:error, {:read_failed, :enoent}} =
             DeviationAdmission.admit_deviation(%{conforms: false, deviations: [[">>", "x"]]}, "r", "c", missing_path)
  end

  # ---------------------------------------------------------------------------
  # Consent table (shared accept/refuse boundary; parity = consent, not identity)
  # ---------------------------------------------------------------------------

  test "consent: both courts refuse the empty/contract-violating candidate class" do
    # lab: EMPTY_ASSERTION refusal
    assert {:ok, %{"ok" => false, "standing" => "REFUSED", "reasons" => ["EMPTY_ASSERTION"]}} =
             Dfcm.sa2a_admit("", candidate_id: "cand-consent-empty", query_id: "q-parity", evidence: %{"k" => "v"})

    # beam4pm: :no_deviation refusal (conforms:false asserted, nothing detected)
    tmp = temp_ontology_copy!()
    assert {:error, :no_deviation} = DeviationAdmission.admit_deviation(%{conforms: false, deviations: []}, "r", "c", tmp)
    File.rm!(tmp)
  end

  test "consent: both courts admit the well-evidenced well-formed candidate class" do
    # lab: KNOWN admission of a real ontology fact
    assert {:ok, %{"ok" => true, "standing" => "KNOWN"}} =
             Dfcm.sa2a_admit(fixture!("positive_c2_conformance_result_rt.assertion"),
               candidate_id: "cand-consent-pos",
               query_id: "q-parity",
               source: "beam4pm-ontology",
               evidence: %{ontology: "ontology.ttl", subject: "bpm:conformance_result_rt"}
             )

    # beam4pm: real admission of a real detected deviation
    tmp = temp_ontology_copy!()

    assert {:ok, name} =
             DeviationAdmission.admit_deviation(%{conforms: false, deviations: [[">>", "clean_house"]]}, "r", "c", tmp)

    assert File.read!(tmp) =~ "bap:#{name} a bpm:ProcessDeviation ;"
    File.rm!(tmp)
  end

  @doc """
  TRIPWIRE for the attributed (non-consenting) pair, C7-vs-E5: an
  error-bearing evidence payload is REFUSED by the lab court, while the
  closest beam4pm case (conforms: true) is an `{:ok, :conforms}` no-op --
  beam4pm reserves admission for deviations and treats conformance as a
  legitimate true negative, never a forged candidate. These verdicts are
  both correct under each court's own law; the divergence is attributed in
  WAVE-RECEIPT.md, and this test pins both observed behaviors.
  """
  test "attributed divergence: error evidence refused by lab vs conforming no-op in beam4pm" do
    assert {:ok, %{"ok" => false, "standing" => "REFUSED"}} =
             Dfcm.sa2a_admit(fixture!("negative_c7_error_evidence.assertion"),
               candidate_id: "cand-consent-c7",
               query_id: "q-parity",
               evidence: %{"unsupported" => "no_admission_provenance"}
             )

    tmp = temp_ontology_copy!()
    before = File.read!(tmp)
    assert {:ok, :conforms} = DeviationAdmission.admit_deviation(%{conforms: true, deviations: []}, "r", "c", tmp)
    assert File.read!(tmp) == before
    File.rm!(tmp)
  end
end
