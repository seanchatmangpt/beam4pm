defmodule BeamPM.DfcmOcelValidateParityTest do
  @moduledoc """
  Chicago-style parity qualification for `BeamPM.Dfcm.ocel_validate/1`
  (v26.9.18 ticket b4p-p2-ocel-validate-parity).

  Every assertion below runs the REAL standalone AutoFDE Typer CLI
  (`priv/bin/autofde ocel validate`, Küsters & van der Aalst (2025) OCPQ
  Definition 2) and/or the REAL `rf3-ocel-oracle` subprocess through
  `BeamPM.RF3Ocel` -- no mocks, no re-implementations.

  The cross-validation table pins the observed accept/refuse boundary of the
  two engines against the same fixtures, INCLUDING the one known, attributed
  divergence on `n14-undeclared-event-type.ocel.json`:

    * the lab validator implements OCPQ Definition 2's structural laws only
      (exactly-one type per entity, no dangling E2O/O2O/change references,
      time-stable `objects`/`type` attributes). Reading `eaval_e(activity)
      in U_etype` it takes `U_etype` as the string universe, so a USED but
      UNDECLARED event type is not one of its laws -- it ACCEPTS the fixture.
    * `BeamPM.RF3Ocel` (via process_mining's real importer + its own
      pipeline-level verification of `raw.undeclared_event_types_used`)
      treats declaration membership as a beam4pm-local admission law -- it
      REFUSES the same fixture.

  Both engines are faithful to their own named spec; the divergence is a law
  coverage difference (implementation layer), recorded here as a permanent
  tripwire: if either verdict flips, this test names it.

  The gym_bridge captures are additionally shown to be OUT of the oracle
  importer's input contract (raw beam4pm capture format, `attributes` as a
  map, no `eventTypes`): the oracle refuses the shape outright, while the lab
  accepts it through its documented capture-format fallback.
  """

  use ExUnit.Case, async: false

  alias BeamPM.Dfcm
  alias BeamPM.RF3Ocel

  @fixture_dir Path.expand("../qualification/fixtures", __DIR__)
  @gym_dir Path.expand("../qualification/gym_bridge", __DIR__)
  @oracle_bin Path.expand("../native/rf3-ocel-oracle/target/release/rf3-ocel-oracle", __DIR__)
  @positive Path.join(@fixture_dir, "positive-self-authored.ocel.json")
  @n05 Path.join(@fixture_dir, "n05-o2o-dangling.ocel.json")
  @n13 Path.join(@fixture_dir, "n13-duplicate-object-id.ocel.json")
  @n14 Path.join(@fixture_dir, "n14-undeclared-event-type.ocel.json")
  @gym_reference Path.join(@gym_dir, "reference_ocel_events.json")
  @gym_deviant Path.join(@gym_dir, "deviant_ocel_events.json")

  defp rf3_opts do
    receipts_dir =
      Path.join([System.tmp_dir!(), "dfcm_ocel_parity_receipts", "run-#{System.unique_integer([:positive])}"])

    [
      oracle_bin: @oracle_bin,
      positive_fixture_path: @positive,
      n13_fixture_path: @n13,
      n14_fixture_path: @n14,
      n05_fixture_path: @n05,
      receipts_dir: receipts_dir
    ]
  end

  defp lab_verdict(path), do: Dfcm.ocel_validate(path)

  # -- the surfaced bridge function -------------------------------------------

  describe "BeamPM.Dfcm.ocel_validate/1 real CLI runs" do
    test "the standalone CLI exposes `ocel validate` against OCPQ Definition 2" do
      assert Dfcm.autofde_cli_available?()

      {out, 0} =
        System.cmd(Dfcm.autofde_cli_path(), ["ocel", "validate", "--help"], stderr_to_stdout: true)

      assert out =~ "Usage:"
      assert out =~ "validate"
      assert out =~ "OCPQ"
    end

    test "accepts the well-formed positive fixture with a stable canonical digest" do
      assert {:ok, verdict} = lab_verdict(@positive)

      assert verdict.ok == true
      assert verdict.validation_error == nil
      assert verdict.event_count == 2
      assert verdict.object_count == 2
      assert verdict.canonical_digest ==
               "0b7130991fd4205184dc366ea7916e081c31cc5805e013ae29a21426699ee598"
    end

    test "refuses n05 dangling O2O by name" do
      assert {:ok, verdict} = lab_verdict(@n05)

      assert verdict.ok == false
      assert verdict.validation_error =~ "DanglingEventObjectLink"
      assert verdict.validation_error =~ "item-99"
    end

    test "refuses n13 duplicate object id by name" do
      assert {:ok, verdict} = lab_verdict(@n13)

      assert verdict.ok == false
      assert verdict.validation_error =~ "DuplicateEntityId"
      assert verdict.validation_error =~ "order-1"
    end

    test "ACCEPTS n14 undeclared event type -- the known, attributed divergence" do
      # OCPQ Definition 2's structural laws do not include declared-type
      # membership (the lab reads U_etype as the string universe), so the lab
      # validator has no law to refuse this fixture with. BeamPM.RF3Ocel DOES
      # refuse it -- see the cross-validation table below.
      assert {:ok, verdict} = lab_verdict(@n14)

      assert verdict.ok == true
      assert verdict.validation_error == nil
    end

    test "accepts both gym_bridge captures through the capture-format fallback" do
      assert {:ok, reference} = lab_verdict(@gym_reference)
      assert reference.ok == true
      assert reference.event_count == 18
      assert reference.object_count == 3

      assert {:ok, deviant} = lab_verdict(@gym_deviant)
      assert deviant.ok == true
      assert deviant.event_count == 5
      assert deviant.object_count == 1
    end

    test "a missing file is a CLI failure, not a validator refusal" do
      assert {:error, {:cli_failed, 1, output}} = lab_verdict("/nonexistent/never.ocel.json")
      assert output =~ "File not found"
    end
  end

  # -- cross-validation vs the family's own oracle -----------------------------

  describe "cross-validation: lab verdict vs BeamPM.RF3Ocel run_opts verdict" do
    test "the accept/refuse boundary table holds, including the n14 divergence" do
      expected = [
        # {fixture, scenario, lab verdict, rf3 verdict, boundary}
        {@positive, :check_positive, :accept, :accept, :match},
        {@n05, :falsify_dangling_o2o, :refuse, :refuse, :match},
        {@n13, :falsify_duplicate_object, :refuse, :refuse, :match},
        {@n14, :falsify_undeclared_type, :accept, :refuse, :divergence}
      ]

      for {fixture, scenario, lab, rf3, boundary} <- expected do
        assert {:ok, verdict} = lab_verdict(fixture)
        lab_verdict_outcome = if verdict.ok, do: :accept, else: :refuse

        rf3_verdict_outcome =
          case RF3Ocel.run(scenario, rf3_opts()) do
            {:ok, _} -> :accept
            {:error, {:refused, _reason}} -> :refuse
            other -> flunk("unexpected RF3Ocel result: #{inspect(other)}")
          end

        assert lab_verdict_outcome == lab,
               "#{Path.basename(fixture)}: lab verdict flipped to #{lab_verdict_outcome}"

        assert rf3_verdict_outcome == rf3,
               "#{Path.basename(fixture)}: RF3Ocel verdict flipped to #{rf3_verdict_outcome}"

        actual_boundary = if lab_verdict_outcome == rf3_verdict_outcome, do: :match, else: :divergence

        assert actual_boundary == boundary,
               "#{Path.basename(fixture)}: boundary flipped to #{actual_boundary}"
      end
    end

    test "n05 refusal is witnessed by the oracle's dropped dangling O2O (raw vs reconstructed)" do
      assert {:error, {:refused, {:assertion_failed, reason}}} =
               RF3Ocel.run(:falsify_dangling_o2o, rf3_opts())

      assert {:dangling_o2o_relationship_silently_dropped_by_process_mining, facts} = reason
      assert facts.raw_o2o_relationship_count == 1
      assert facts.reconstructed_o2o_relationship_count == 0
    end

    test "n13 refusal is witnessed by the oracle's silent dedup (distinct ids vs num_objects)" do
      assert {:error, {:refused, {:assertion_failed, reason}}} =
               RF3Ocel.run(:falsify_duplicate_object, rf3_opts())

      assert {:duplicate_object_id_silently_deduped_by_process_mining, facts} = reason
      assert facts.raw_num_objects == 2
      assert facts.distinct_object_ids == 1
    end

    test "n14 refusal is witnessed by the oracle's undeclared-type disclosure" do
      assert {:error, {:refused, {:assertion_failed, reason}}} =
               RF3Ocel.run(:falsify_undeclared_type, rf3_opts())

      assert {:undeclared_event_type_silently_auto_declared_by_process_mining, facts} = reason

      assert facts.undeclared_event_types_used == ["Teleport Order"]
    end

    test "positive fixture passes the oracle's own shape assertions (full accept agreement)" do
      assert {:ok, out} = RF3Ocel.run(:check_positive, rf3_opts())
      assert out.verified.num_events == 2
      assert out.verified.num_objects == 2
      assert out.verified.e2o_relationship_count == 3
      assert out.verified.o2o_relationship_count == 1
    end

    test "gym_bridge captures are outside the oracle importer's input contract" do
      # The lab accepts the captures via its documented capture-format
      # fallback; process_mining's OCEL 2.0 JSON importer refuses the same
      # documents outright (capture `attributes` is a map; the schema wants a
      # sequence; there is no `eventTypes` section at all). No RF3Ocel
      # scenario admits the capture format -- exercised here for real through
      # :check_positive so the refusal stays witnessed, not asserted.
      for capture <- [@gym_reference, @gym_deviant] do
        opts = rf3_opts() |> Keyword.put(:positive_fixture_path, capture)

        assert {:error, {:refused, {:assertion_failed, {:oracle_reported_not_ok, out}}}} =
                 RF3Ocel.run(:check_positive, opts)

        assert out["ok"] == false
        assert out["error"] == "ocel_json_import_failed"
      end
    end
  end

  doctest BeamPM.Dfcm
end
