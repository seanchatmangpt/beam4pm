defmodule BeamPM.GraphlawBridgeTest do
  @moduledoc """
  `ocel2_conformance_court` for `BeamPM.GraphlawBridge` (Chicago:
  real `:telemetry` dispatch, real ETS-backed `BeamPM.OcelAccumulator`,
  real `BeamPM.Ocel.validate_envelope/2` -- no mocks):

    * a valid graphlaw_ex admit-stop span maps, purely, into an OCEL 2.0
      envelope that passes `BeamPM.Ocel.validate_envelope/2` and ingests
      through `BeamPM.OcelAccumulator.ingest/2` (activity = op, timestamp
      parses as ISO8601, object ref from metadata, `admitted_by` E2O);
    * the flip-twins: the SAME envelope with the activity dropped, with
      the timestamp dropped, and with the `pe:sourceDigest` source
      identity stripped, is each REFUSED by the bridge's ingest
      path with a typed refusal and nothing written;
    * `validate_envelope/2` itself is proven non-vacuous by flipping it
      (the envelope minus its server object is dangling-refused);
    * a REAL `:telemetry.execute/3` of `[:graphlaw_ex, :admit, :stop]`
      lands in the accumulator through the attached handler (telemetry
      dispatch is synchronous, so the assert is a direct observation, not
      a wait).
  """

  use ExUnit.Case, async: false

  alias BeamPM.GraphlawBridge
  alias BeamPM.Ocel
  alias BeamPM.OcelAccumulator
  alias BeamPM.Rust4PM
  alias BeamPM.Types.OcelEvent
  alias BeamPM.Types.OcelObject
  alias BeamPM.Types.OcelRelationship

  # The real graphlaw_ex admit-stop shape (GraphlawEx.Telemetry.admit/3):
  # measurements %{duration: native}, metadata %{op:, server:, source_digest:,
  # outcome:, refusal_code:}.
  @measurements %{duration: 9876}

  # GL28-1 leg (b): the Art. 12 source identity. ENGINE-MINTED, not a
  # test-rolled literal: the fixture law bytes below through the REAL `law`
  # op (construct-ceiling signed lease, the capability smoke court's
  # engine-verifiable fixture) over the real wasm artifact
  # (engine_sha256 34fd4ada7ffe57f3f07de14232f8faacab67ef78a4d9afc3a12e79d78f865d08);
  # response `states` head = blake3: of the RDFC-1.0 canonical N-Quads of
  # the law content (LawState.id). The `canonical` op's content-addressed
  # id agrees on the same input (two real collaborators, one mint). Fixture
  # law bytes: "<https://x/s> <https://x/p> <https://x/o> ." — re-mint with
  # the law op on those bytes and the states head must equal this digest.
  @source_digest "blake3:dc0088be1cab1b4c41922511b036ee65159c8098e33c5f6c8a7a5cad4485a46e"

  @ok_metadata %{
    op: "law_admit",
    server: GraphlawEx,
    outcome: :ok,
    refusal_code: nil,
    source_digest: @source_digest
  }

  @refused_metadata %{
    op: "shacl_validate",
    server: self(),
    outcome: :refused,
    refusal_code: :GL28_REFUSED_X
  }

  setup do
    start_supervised!(OcelAccumulator)
    :ok = OcelAccumulator.reset()

    on_exit(fn ->
      _ = :telemetry.detach(GraphlawBridge)
      :ok
    end)

    :ok
  end

  describe "ocel2_conformance_court" do
    test "a valid admit span maps to an envelope validate_envelope/2 passes" do
      envelope = GraphlawBridge.mapper(@measurements, @ok_metadata)

      # the conformance direction: real OCEL 2.0 referential integrity
      assert :ok = Ocel.validate_envelope(envelope.events, envelope.objects)

      # and it ingests through the real accumulator, as mapped
      assert {:ok, %{events: 1, objects: 1}} = GraphlawBridge.ingest(envelope)
      assert %{events: 1, objects: 1} = OcelAccumulator.counts()

      # the accumulated content (not just the mapped envelope) validates
      assert :ok = Ocel.validate_envelope(OcelAccumulator.events(), OcelAccumulator.objects())
    end

    test "a valid admit span's event carries activity=op, a real timestamp, and the metadata object ref" do
      envelope = GraphlawBridge.mapper(@measurements, @ok_metadata)
      assert [{%OcelEvent{} = event, rels}] = envelope.events
      assert [{%OcelObject{} = server, []}] = envelope.objects

      # activity = op (namespaced by the source engine)
      assert event.event_type == "graphlaw_ex.law_admit"
      assert event.attributes["graphlaw.op"] == "law_admit"

      # timestamp: real ISO8601 the OCEL wire contract accepts
      assert {:ok, %DateTime{}, _offset} = DateTime.from_iso8601(event.event_time)

      # event id is unique per mapped span, prefixed by the op
      assert "graphlaw_admit_law_admit_" <> _suffix = event.event_id

      # object ref FROM the metadata (the executing server), qualified E2O
      assert server.object_type == "graphlaw_ex_server"
      assert server.attributes["graphlaw.server"] == "GraphlawEx"
      assert [%OcelRelationship{qualifier: "admitted_by", object_id: object_id}] = rels
      assert object_id == server.object_id

      # duration carried into attributes
      assert event.attributes["graphlaw.duration_native"] == "9876"

      # Art. 12 source identity (leg b): the engine-minted blake3: digest
      # from the admit opts flows through the telemetry metadata onto the
      # event -- identity of the law CONTENT executed, never wasm_sha256
      # (that routes to the engine object, ENVELOPE-SPEC §2)
      assert event.attributes["pe:sourceDigest"] == @source_digest
    end

    test "a refused admit span maps to a valid envelope carrying the refusal code" do
      envelope = GraphlawBridge.mapper(@measurements, @refused_metadata)

      assert :ok = Ocel.validate_envelope(envelope.events, envelope.objects)

      assert [{%OcelEvent{} = event, _rels}] = envelope.events
      assert event.event_type == "graphlaw_ex.shacl_validate"
      assert event.attributes["graphlaw.outcome"] == ":refused"
      assert event.attributes["graphlaw.refusal_code"] == "GL28_REFUSED_X"

      # pid servers are inspected into a stable string object ref
      assert [{%OcelObject{object_id: "graphlaw_ex.server." <> _pid_ref, object_type: "graphlaw_ex_server"}, []}] =
               envelope.objects
    end

    test "flip-twin: an injected event missing its activity is refused, nothing written" do
      envelope = GraphlawBridge.mapper(@measurements, @ok_metadata)
      [{event, rels}] = envelope.events

      no_activity = %{events: [{%OcelEvent{event | event_type: nil}, rels}], objects: envelope.objects}

      assert {:error, {:missing_field, :event_type}} = GraphlawBridge.ingest(no_activity)
      assert %{events: 0, objects: 0} = OcelAccumulator.counts()
    end

    test "flip-twin: an injected event missing its timestamp is refused, nothing written" do
      envelope = GraphlawBridge.mapper(@measurements, @ok_metadata)
      [{event, rels}] = envelope.events

      no_timestamp = %{events: [{%OcelEvent{event | event_time: nil}, rels}], objects: envelope.objects}

      assert {:error, {:missing_field, :event_time}} = GraphlawBridge.ingest(no_timestamp)
      assert %{events: 0, objects: 0} = OcelAccumulator.counts()
    end

    # GL28-1 leg (b): the Art. 12 court law -- missing pe:sourceDigest ->
    # trace rejected, nothing written. The SAME envelope as the passing
    # ingest above, with ONLY the attribute stripped post-mapper: the
    # refusal must name :source_digest exactly.
    test "flip-twin: an injected event missing its pe:sourceDigest is refused, nothing written" do
      envelope = GraphlawBridge.mapper(@measurements, @ok_metadata)
      [{event, rels}] = envelope.events

      no_digest = %{
        events: [
          {%OcelEvent{event | attributes: Map.delete(event.attributes, "pe:sourceDigest")}, rels}
        ],
        objects: envelope.objects
      }

      assert {:error, {:missing_field, :source_digest}} = GraphlawBridge.ingest(no_digest)
      assert %{events: 0, objects: 0} = OcelAccumulator.counts()
    end

    test "validate_envelope/2 is non-vacuous: the envelope minus its server object dangles" do
      envelope = GraphlawBridge.mapper(@measurements, @ok_metadata)

      assert {:error, {:dangling_relationships, [{:event, event_id, "graphlaw_ex.server.GraphlawEx"}]}} =
               Ocel.validate_envelope(envelope.events, [])

      assert String.starts_with?(event_id, "graphlaw_admit_law_admit_")
    end

    test "attach is idempotent and a real :telemetry.execute lands in the accumulator" do
      assert :ok = GraphlawBridge.attach()
      assert :ok = GraphlawBridge.attach()

      # real telemetry dispatch (synchronous by default): the handler has
      # finished its ingest by the time execute/3 returns. The synthetic
      # metadata carries the source identity exactly as the real span now
      # does when the admit opts pin it (leg b) -- without it the ingest
      # gate refuses the event by design.
      :telemetry.execute([:graphlaw_ex, :admit, :stop], %{duration: 4242}, %{
        op: "law_admit",
        server: GraphlawEx,
        source_digest: @source_digest,
        outcome: :refused,
        refusal_code: :GL28_REFUSED_X
      })

      assert %{events: 1, objects: 1} = OcelAccumulator.counts()

      assert [%OcelEvent{event_type: "graphlaw_ex.law_admit", attributes: attrs}] =
               Enum.map(OcelAccumulator.events(), fn {e, _} -> e end)

      assert attrs["graphlaw.refusal_code"] == "GL28_REFUSED_X"
      assert attrs["graphlaw.duration_native"] == "4242"

      # and the live-ingested content validates as OCEL 2.0
      assert :ok = Ocel.validate_envelope(OcelAccumulator.events(), OcelAccumulator.objects())

      assert :ok = GraphlawBridge.detach()
      assert {:error, :not_found} = GraphlawBridge.detach()
    end

    # Loud-skip law (named reason, never a fake): when NEITHER conformance
    # capability is available -- no compiled rf3-conformance-oracle binary at
    # native/rf3-conformance-oracle AND no rust4pm wasm engine artifact for
    # the Elixir engine-handle path -- there is no real oracle to decide, so
    # this test loud-skips rather than fabricating a verdict.
    if GraphlawBridge.conformance_oracle_bin() == nil and not Rust4PM.wasm_built?() do
      @tag skip:
             "no conformance oracle available: no binary at native/rf3-conformance-oracle and " <>
               Rust4PM.wasm_missing_reason()
    end

    test "conform/1 runs the bridged synthetic admit span through the RF3 oracle and returns a verdict struct" do
      # bridge a real synthetic admit span: mapper -> real accumulator ingest
      envelope = GraphlawBridge.mapper(@measurements, @ok_metadata)
      assert {:ok, %{events: 1, objects: 1}} = GraphlawBridge.ingest(envelope)

      receipts_dir =
        Path.join([
          System.tmp_dir!(),
          "graphlaw_bridge_conformance",
          "run-#{System.unique_integer([:positive])}"
        ])

      run_id = "conform-court-#{System.unique_integer([:positive])}"

      assert {:ok, %GraphlawBridge.Conformance{} = verdict} =
               GraphlawBridge.conform(receipts_dir: receipts_dir, run_id: run_id)

      # the verdict struct: whichever real oracle decided, it decided
      # :conformant over the single bridged admit span, and said which oracle
      assert verdict.outcome == :conformant
      assert verdict.oracle in [:native_rf3_binary, :elixir_engine_handle]
      assert verdict.counts == %{events: 1, objects: 1}
      assert is_binary(verdict.receipt_path) and File.exists?(verdict.receipt_path)

      case verdict.oracle do
        :native_rf3_binary ->
          # the real binary's real stats over the serialized accumulated log
          assert verdict.verified.num_events == 1
          assert verdict.verified.num_objects == 1

        :elixir_engine_handle ->
          # the real engine built (and freed) a handle over the accumulated log
          assert verdict.verified.engine_handle_built == true
      end

      # exactly one real receipt on disk, readable, schema-carrying
      receipt = verdict.receipt_path |> File.read!() |> JSON.decode!()
      assert receipt["receipt_schema"] == "beam4pm-graphlaw-bridge-conformance/v1"
      assert receipt["run_id"] == run_id
      assert receipt["outcome"] == "conformant"
      assert receipt["counts"] == %{"events" => 1, "objects" => 1}
      assert receipt["replay"]["oracle_bin"] == GraphlawBridge.conformance_oracle_bin()
    end

    # -----------------------------------------------------------------
    # GL28-1 leg c: the REAL-engine witness court. The engine artifact is
    # the sibling graphlaw checkout's graphlaw_ex app (PRIV_WASM overrides).
    # A missing artifact is a LOUD skip with the named reason -- never a
    # fake pass -- and GRAPHLAW_REQUIRE_ENGINE=1 flips the skip into a hard
    # failure (the test runs and flunks at its head). Real collaborators
    # only: the supervised GraphlawEx host over the real wasm module, the
    # real :telemetry dispatch, the real ETS accumulator, the real oracle.
    # -----------------------------------------------------------------
    @wasm_path System.get_env("PRIV_WASM") ||
                 Path.expand("../../graphlaw/graphlaw_ex/priv/graphlaw/graphlaw.wasm", __DIR__)

    unless File.regular?(@wasm_path) or System.get_env("GRAPHLAW_REQUIRE_ENGINE") == "1" do
      @tag skip:
             "graphlaw_ex engine artifact missing at #{@wasm_path} -- loud skip, not a fake pass " <>
               "(GRAPHLAW_REQUIRE_ENGINE=1 turns this skip into a failure)"
    end

    @tag timeout: 300_000
    test "the real GraphlawEx engine's admit telemetry bridges into a conformant OCEL receipt carrying the engine digest" do
      unless File.regular?(@wasm_path) do
        flunk(
          "graphlaw_ex engine artifact missing at #{@wasm_path} -- GRAPHLAW_REQUIRE_ENGINE=1 forbids the skip"
        )
      end

      # the REAL engine over the real artifact bytes, no mocks
      start_supervised!({GraphlawEx, wasm_path: @wasm_path, expected_sha256: :unpinned})
      :ok = GraphlawBridge.attach()

      assert {:ok, %{"ok" => true}} =
               GraphlawEx.admit(GraphlawEx, JSON.encode!(%{"op" => "capabilities"}),
                 source_digest: @source_digest
               )

      # telemetry dispatch is synchronous: direct observation, never a wait
      assert %{events: 1, objects: 1} = OcelAccumulator.counts()

      assert [%OcelEvent{event_type: "graphlaw_ex.admit", attributes: attrs}] =
               Enum.map(OcelAccumulator.events(), fn {e, _} -> e end)

      assert attrs["graphlaw.op"] == "admit"
      assert attrs["graphlaw.outcome"] == ":ok"
      assert attrs["graphlaw.refusal_code"] == nil

      # a REAL engine duration: parses as an integer > 0 and is neither of
      # the synthetic fixture constants used by the mapper courts above
      assert {duration, ""} = Integer.parse(attrs["graphlaw.duration_native"])
      assert duration > 0
      refute duration in [9876, 4242]

      assert [%OcelObject{object_id: "graphlaw_ex.server.GraphlawEx", object_type: "graphlaw_ex_server"}] =
               Enum.map(OcelAccumulator.objects(), fn {o, _} -> o end)

      # the live-ingested real-engine content is referentially closed OCEL 2.0
      assert :ok = Ocel.validate_envelope(OcelAccumulator.events(), OcelAccumulator.objects())

      # the engine's real load receipt: the digest of the exact artifact bytes
      assert {:ok, %{wasm_sha256: digest}} = GraphlawEx.Host.info(GraphlawEx)

      receipts_dir =
        Path.join([
          System.tmp_dir!(),
          "graphlaw_bridge_conformance",
          "run-#{System.unique_integer([:positive])}"
        ])

      run_id = "graphlaw-engine-witness-#{System.unique_integer([:positive])}"

      assert {:ok,
              %GraphlawBridge.Conformance{outcome: :conformant, counts: %{events: 1, objects: 1}} =
                verdict} =
               GraphlawBridge.conform(
                 receipts_dir: receipts_dir,
                 run_id: run_id,
                 receipt_extras: %{
                   "engine_sha256" => digest,
                   "wasm_path" => @wasm_path,
                   "emission" => %{
                     "source" => "real_graphlaw_ex_engine",
                     "op" => "admit",
                     "outcome" => ":ok",
                     "refusal_code" => nil,
                     "duration_native" => duration
                   }
                 }
               )

      # the on-disk receipt carries the caller-supplied engine extras at the
      # top level (the :receipt_extras merge)
      receipt = verdict.receipt_path |> File.read!() |> JSON.decode!()
      assert receipt["engine_sha256"] == digest
      assert receipt["wasm_path"] == @wasm_path
      assert receipt["emission"]["duration_native"] == duration
    end

    unless File.regular?(@wasm_path) or System.get_env("GRAPHLAW_REQUIRE_ENGINE") == "1" do
      @tag skip:
             "graphlaw_ex engine artifact missing at #{@wasm_path} -- loud skip, not a fake pass " <>
               "(GRAPHLAW_REQUIRE_ENGINE=1 turns this skip into a failure)"
    end

    @tag timeout: 300_000
    test "anti-vacuity: with the bridge detached a real engine admit writes nothing" do
      unless File.regular?(@wasm_path) do
        flunk(
          "graphlaw_ex engine artifact missing at #{@wasm_path} -- GRAPHLAW_REQUIRE_ENGINE=1 forbids the skip"
        )
      end

      start_supervised!({GraphlawEx, wasm_path: @wasm_path, expected_sha256: :unpinned})
      :ok = GraphlawBridge.attach()

      assert {:ok, %{"ok" => true}} =
               GraphlawEx.admit(GraphlawEx, JSON.encode!(%{"op" => "capabilities"}),
                 source_digest: @source_digest
               )
      assert %{events: 1, objects: 1} = OcelAccumulator.counts()

      # the flip: no handler attached -> no OCEL. The bridge is the only
      # source of accumulated events; the engine alone writes nothing.
      :ok = GraphlawBridge.detach()

      assert {:ok, %{"ok" => true}} =
               GraphlawEx.admit(GraphlawEx, JSON.encode!(%{"op" => "capabilities"}),
                 source_digest: @source_digest
               )
      assert %{events: 1, objects: 1} = OcelAccumulator.counts()
    end
  end
end
