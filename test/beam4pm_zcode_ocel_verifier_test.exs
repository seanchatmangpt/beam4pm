defmodule Beam4pm.ZcodeOcelVerifierTest do
  @moduledoc """
  Court for `BeamPM.ZcodeOcelVerifier` over REAL committed fixture files
  (zcode-cli's own `.jsonocel` + `.receipt.json` court evidence, copied
  verbatim), with non-vacuous mutations: a byte-flipped log, a chain-broken
  log, a tampered receipt chain, and cross-vocabulary leakage injections in
  both directions. A drift meta-test refuses drift between the pinned
  vocabulary manifest and the live zcode checkout (skipped — BLOCKED — when
  the zcode checkout is absent).
  """

  use ExUnit.Case, async: true

  @fixtures_dir Path.expand("fixtures/zcode_ocel", __DIR__)
  @turn_log Path.join(@fixtures_dir, "turn-list.jsonocel")
  @turn_receipt Path.join(@fixtures_dir, "turn-list.receipt.json")
  @app_server_log Path.join(@fixtures_dir, "app-server-list.jsonocel")
  @app_server_receipt Path.join(@fixtures_dir, "app-server-list.receipt.json")
  @pinned_manifest Path.join(@fixtures_dir, "zcode_vocab_manifest.json")
  @live_manifest "/Users/sac/zcode-cli/src/ocel-vocab-manifest.ts"

  alias BeamPM.ZcodeOcelVerifier

  describe "real fixtures verify" do
    test "turn-list.jsonocel + receipt admit with an intact chain" do
      assert {:ok, report} = ZcodeOcelVerifier.verify(@turn_log)
      receipt = decode_receipt(@turn_receipt)

      assert report.event_count == 39
      assert report.event_count == receipt["event_count"]
      assert report.head_hash == receipt["head_hash"]
      assert report.receipt_intact == true
      assert report.file_sha256 == receipt["ocel_file_sha256"]
      assert "turn_started" in report.event_types
      assert "turn_completed" in report.event_types
      assert report.object_types -- ["session", "turn", "model_request", "tool_call"] == []
    end

    test "app-server-list.jsonocel + receipt admit with an intact chain" do
      assert {:ok, report} = ZcodeOcelVerifier.verify(@app_server_log)
      receipt = decode_receipt(@app_server_receipt)
      assert report.event_count == receipt["event_count"]
      assert report.head_hash == receipt["head_hash"]
      assert report.file_sha256 == receipt["ocel_file_sha256"]
    end
  end

  describe "typed refusals over mutated copies" do
    test "byte-flipped log is refused as file_digest_mismatch" do
      {log, receipt} = tmp_pair("flip")

      # flip exactly one byte inside an object type name — JSON stays
      # parseable, so the digest check (not the parse) must fire.
      original = File.read!(log)
      flipped = String.replace(original, ~s("name":"item"), ~s("name":"jtem"), global: false)
      assert flipped != original
      File.write!(log, flipped)

      assert {:refused, refusals} = ZcodeOcelVerifier.verify(log, receipt_path: receipt)
      assert {:file_digest_mismatch, _} = Enum.find(refusals, fn {code, _} -> code == :file_digest_mismatch end)
    end

    test "rewriting one event body is refused as ocel_chain_broken" do
      {log, receipt} = tmp_pair("chain")

      doc = @turn_log |> File.read!() |> Jason.decode!()
      [first | rest] = doc["events"]
      # keep the shape valid, move time by one millisecond: the bound canon
      # form changes, the recorded pi_hash does not follow.
      first = Map.put(first, "time", "2026-09-21T22:28:24.032Z")
      File.write!(log, Jason.encode!(put_in(doc["events"], [first | rest])))

      assert {:refused, refusals} = ZcodeOcelVerifier.verify(log, receipt_path: receipt)
      assert {:ocel_chain_broken, detail} = Enum.find(refusals, fn {code, _} -> code == :ocel_chain_broken end)
      assert detail =~ "hash mismatch"
    end

    test "re-parenting the second event is refused as a parent mismatch" do
      {log, receipt} = tmp_pair("parent")

      doc = @turn_log |> File.read!() |> Jason.decode!()
      [e1, e2 | rest] = doc["events"]

      e2 =
        Map.update!(e2, "attributes", fn attrs ->
          Enum.map(attrs, fn
            %{"name" => "pi_parent"} -> %{"name" => "pi_parent", "value" => String.duplicate("f", 64)}
            a -> a
          end)
        end)

      File.write!(log, Jason.encode!(put_in(doc["events"], [e1, e2 | rest])))

      assert {:refused, refusals} = ZcodeOcelVerifier.verify(log, receipt_path: receipt)
      assert {:ocel_chain_broken, detail} = Enum.find(refusals, fn {code, _} -> code == :ocel_chain_broken end)
      assert detail =~ "parent mismatch"
    end

    test "tampered receipt chain standing is refused as receipt_chain_broken" do
      {log, receipt} = tmp_pair("standing")

      receipt_map = receipt |> File.read!() |> Jason.decode!()

      receipt_map =
        update_in(receipt_map, ["chain", Access.at(1), "standing"], fn _ -> "unsupported" end)

      File.write!(receipt, Jason.encode!(receipt_map))

      assert {:refused, refusals} = ZcodeOcelVerifier.verify(log, receipt_path: receipt)
      assert {:receipt_chain_broken, _} = Enum.find(refusals, fn {code, _} -> code == :receipt_chain_broken end)
    end

    test "receipt event_count lie is refused as event_count_mismatch" do
      {log, receipt} = tmp_pair("count")

      receipt_map = receipt |> File.read!() |> Jason.decode!()
      receipt_map = Map.put(receipt_map, "event_count", 38)
      File.write!(receipt, Jason.encode!(receipt_map))

      assert {:refused, refusals} = ZcodeOcelVerifier.verify(log, receipt_path: receipt)
      assert {:event_count_mismatch, _} = Enum.find(refusals, fn {code, _} -> code == :event_count_mismatch end)
    end

    test "missing receipt file is refused as receipt_missing" do
      {log, receipt} = tmp_pair("absent")
      File.rm(receipt)

      assert {:refused, refusals} = ZcodeOcelVerifier.verify(log, receipt_path: receipt)
      assert {:receipt_missing, _} = Enum.find(refusals, fn {code, _} -> code == :receipt_missing end)
    end

    test "structurally malformed envelope is refused as envelope_malformed" do
      path = Path.join(tmp_dir("malformed"), "bad.jsonocel")
      File.write!(path, ~s({"objectTypes": [], "eventTypes": "nope"}))

      assert {:refused, refusals} = ZcodeOcelVerifier.verify(path, receipt_path: path)
      assert {:envelope_malformed, detail} = Enum.find(refusals, fn {code, _} -> code == :envelope_malformed end)
      assert detail =~ "objectTypes/eventTypes/objects/events"
    end

    test "unparseable log is refused as unparseable_log" do
      path = Path.join(tmp_dir("garbage"), "bad.jsonocel")
      File.write!(path, "{not json")

      assert {:refused, refusals} = ZcodeOcelVerifier.verify(path, receipt_path: path)
      assert {:unparseable_log, _} = Enum.find(refusals, fn {code, _} -> code == :unparseable_log end)
    end
  end

  describe "cross-vocabulary leakage" do
    test "a CastleOcel event name in a zcode log is a typed refusal" do
      {log, receipt} = tmp_pair("leak")

      doc = @turn_log |> File.read!() |> Jason.decode!()
      [first | rest] = doc["events"]
      first = Map.put(first, "type", "evidence_admitted")
      File.write!(log, Jason.encode!(put_in(doc, ["events"], [first | rest])))

      assert {:refused, refusals} = ZcodeOcelVerifier.verify(log, receipt_path: receipt)

      assert {:cross_vocabulary_event_type, detail} =
               Enum.find(refusals, fn {code, _} -> code == :cross_vocabulary_event_type end)

      assert detail =~ "evidence_admitted"
    end

    test "an unknown event type in a zcode log is a typed refusal" do
      {log, receipt} = tmp_pair("unknown-type")

      doc = @turn_log |> File.read!() |> Jason.decode!()
      [first | rest] = doc["events"]
      first = Map.put(first, "type", "totally_made_up_event")
      File.write!(log, Jason.encode!(put_in(doc, ["events"], [first | rest])))

      assert {:refused, refusals} = ZcodeOcelVerifier.verify(log, receipt_path: receipt)
      assert {:cross_vocabulary_event_type, detail} = Enum.find(refusals, fn {code, _} -> code == :cross_vocabulary_event_type end)
      assert detail =~ "totally_made_up_event"
    end

    test "castle direction: a zcode type in a CastleOcel doc is a typed refusal" do
      castle_doc = %{
        "events" => [
          %{
            "id" => "e1",
            "type" => "episode_recorded",
            "time" => "2026-10-13T00:00:00.000Z",
            "attributes" => [],
            "relationships" => []
          },
          %{
            "id" => "e2",
            "type" => "turn_started",
            "time" => "2026-10-13T00:00:01.000Z",
            "attributes" => [],
            "relationships" => []
          }
        ],
        "objectTypes" => [%{"name" => "gym_act_episode", "attributes" => []}],
        "eventTypes" => [],
        "objects" => [%{"id" => "o1", "type" => "system", "attributes" => [], "relationships" => []}]
      }

      assert {:refused, refusals} = ZcodeOcelVerifier.verify_vocabulary(castle_doc, :castle)
      assert {:cross_vocabulary_event_type, detail} = Enum.find(refusals, fn {code, _} -> code == :cross_vocabulary_event_type end)
      assert detail =~ "turn_started"

      # and the pure castle doc admits
      pure = put_in(castle_doc, ["events"], [hd(castle_doc["events"])])
      assert :ok = ZcodeOcelVerifier.verify_vocabulary(pure, :castle)
    end

    test "zcode direction: the untouched fixture admits vocabulary" do
      doc = @turn_log |> File.read!() |> Jason.decode!()
      assert :ok = ZcodeOcelVerifier.verify_vocabulary(doc, :zcode)
    end
  end

  describe "pinned manifest" do
    test "manifest is present with provenance and disjoint registries" do
      manifest = Jason.decode!(File.read!(@pinned_manifest))
      assert %{"source_sha256" => source_sha, "source_path" => path, "pinned_at" => _} = manifest["provenance"]
      assert is_binary(source_sha) and byte_size(source_sha) == 64
      assert path =~ "ocel-vocab-manifest.ts"

      assert match?(%{"event_types" => evts, "object_types" => objs} when length(evts) == 35 and length(objs) == 14, manifest["registry"])

      assert MapSet.disjoint?(
               MapSet.new(manifest["registry"]["event_types"]),
               MapSet.new(manifest["castle_event_types"])
             )

      assert MapSet.disjoint?(
               MapSet.new(manifest["registry"]["object_types"]),
               MapSet.new(manifest["castle_object_types"])
             )

      assert map_size(manifest["event_classification"]) == 35
      assert map_size(manifest["object_classification"]) == 14
    end

    @tag :drift
    # BLOCKED-skip when the zcode checkout is absent: the drift court cannot
    # run without its live referent.
    @tag skip: not File.exists?(@live_manifest)
    test "drift meta-test: pinned manifest matches the live zcode manifest" do
      live_sha = :crypto.hash(:sha256, File.read!(@live_manifest)) |> Base.encode16(case: :lower)
      manifest = Jason.decode!(File.read!(@pinned_manifest))

      assert manifest["provenance"]["source_sha256"] == live_sha,
             "zcode ocel-vocab-manifest.ts has drifted from the beam4pm pinned copy — re-pin " <>
               "test/fixtures/zcode_ocel/zcode_vocab_manifest.json from the live manifest"
    end
  end

  describe "receipt-chain port parity (receipt.ts verify)" do
    test "accepts the fixture chain and refuses classic breakages" do
      chain = @turn_receipt |> File.read!() |> Jason.decode!() |> Map.fetch!("chain")
      assert ZcodeOcelVerifier.receipt_chain_intact?(chain)

      # break a hash
      broken = update_in(chain, [Access.at(2), "hash"], fn _ -> String.duplicate("a", 64) end)
      refute ZcodeOcelVerifier.receipt_chain_intact?(broken)

      # break parent linkage
      relinked = update_in(chain, [Access.at(1), "parent_hash"], fn _ -> String.duplicate("b", 64) end)
      refute ZcodeOcelVerifier.receipt_chain_intact?(relinked)

      # pending entry with a non-neutral standing
      bad_pending = update_in(chain, [Access.at(0), "standing"], fn _ -> "alive" end)
      refute ZcodeOcelVerifier.receipt_chain_intact?(bad_pending)

      # outcome pairing a pending with a different action
      bad_pair = update_in(chain, [Access.at(1), "action"], fn _ -> "other" end)
      refute ZcodeOcelVerifier.receipt_chain_intact?(bad_pair)
    end
  end

  # -- helpers ---------------------------------------------------------------

  defp decode_receipt(path), do: path |> File.read!() |> Jason.decode!()

  defp tmp_pair(tag) do
    dir = tmp_dir(tag)
    log = Path.join(dir, "turn-list.jsonocel")
    receipt = Path.join(dir, "turn-list.receipt.json")
    File.cp!(@turn_log, log)
    File.cp!(@turn_receipt, receipt)
    {log, receipt}
  end

  defp tmp_dir(tag) do
    dir = Path.join(System.tmp_dir!(), "beam4pm-zcode-verifier-test-#{tag}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end
end
