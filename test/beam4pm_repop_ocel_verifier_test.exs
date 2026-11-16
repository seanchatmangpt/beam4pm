defmodule Beam4pm.RepopOcelVerifierTest do
  @moduledoc """
  Court for `BeamPM.RepopOcelVerifier` over a REAL committed fixture pair
  (3-event repop-shaped log + receipt, hashes computed by the pinned
  `:repop_canon_v1` canonical form itself — self-consistent by
  construction, and explicitly UNVERIFIED against repop chain.ts bytes
  until Y2's seal-tier landing and a cross-check court run), with
  non-vacuous mutations: byte-flipped log, chain-broken log, re-parented
  event, count lie, receipt algorithm lie, unsupported algorithm, and
  cross-vocabulary leakage injections in both directions. A drift
  meta-test refuses drift between the pinned vocabulary manifest and the
  live repop checkout (BLOCKED-skipped when the checkout is absent).
  """

  use ExUnit.Case, async: true

  @fixtures_dir Path.expand("fixtures/repop_ocel", __DIR__)
  @log Path.join(@fixtures_dir, "repop-3event.jsonocel")
  @receipt Path.join(@fixtures_dir, "repop-3event.receipt.json")
  @pinned_manifest Path.join(@fixtures_dir, "repop_vocab_manifest.json")
  @repop_path System.get_env("REPOP_PATH") || "/Users/sac/repop"
  @live_vocab Path.join(@repop_path, "packages/worker/src/ocel/vocab.ts")

  alias BeamPM.RepopOcelVerifier

  describe "real fixture verifies" do
    test "repop-3event.jsonocel + receipt admits with an intact chain" do
      assert {:ok, report} = RepopOcelVerifier.verify(@log)
      receipt = decode_receipt(@receipt)

      assert report.event_count == 3
      assert report.event_count == receipt["event_count"]
      assert report.head_hash == receipt["head_hash"]
      assert report.file_digest == receipt["repop_file_digest"]
      assert report.algorithm == :sha256
      assert report.event_types == ["start", "assign", "complete"]
      assert report.object_types -- ["wo", "machine"] == []
    end

    test "fnv1a32 tier verifies the same log under its own chain" do
      # rebuild receipt + chain attributes for the fnv1a32 tier over the
      # same canonical bytes: the framing is shared, only H differs.
      doc = @log |> File.read!() |> Jason.decode!()
      {events, head} =
        Enum.map_reduce(doc["events"], RepopOcelVerifier.genesis_hex(:fnv1a32), fn ev, parent ->
          hash = RepopOcelVerifier.link_digest_hex(parent, RepopOcelVerifier.canon(ev), :fnv1a32)
          ev =
            put_in(ev, ["attributes"], [
              %{"name" => "rep_parent", "value" => parent},
              %{"name" => "rep_hash", "value" => hash}
            ])

          {ev, hash}
        end)

      doc = put_in(doc, ["events"], events)
      json = Jason.encode!(doc)
      {log, receipt} = tmp_pair("fnv")
      File.write!(log, json)
      File.write!(receipt, Jason.encode!(%{
        "algorithm" => "fnv1a32",
        "repop_file_digest" => fnv1a32_hex(json),
        "event_count" => 3,
        "head_hash" => head
      }))

      assert {:ok, report} = RepopOcelVerifier.verify(log, algorithm: :fnv1a32, receipt_path: receipt)
      assert report.algorithm == :fnv1a32
      assert report.head_hash == head
    end

    test "genesis is the well-known empty-input sha256" do
      assert RepopOcelVerifier.genesis_hex(:sha256) ==
               Base.encode16(:crypto.hash(:sha256, ""), case: :lower)
    end
  end

  describe "typed refusals over mutated copies" do
    test "byte-flipped log is refused as file_digest_mismatch" do
      {log, receipt} = tmp_pair("flip")

      original = File.read!(log)
      flipped = String.replace(original, ~s("type": "start"), ~s("type": "stqrt"), global: false)
      assert flipped != original
      File.write!(log, flipped)

      assert {:refused, refusals} = RepopOcelVerifier.verify(log, receipt_path: receipt)
      assert {:file_digest_mismatch, _} = find(refusals, :file_digest_mismatch)
    end

    test "rewriting one event body is refused as ocel_chain_broken" do
      {log, receipt} = tmp_pair("chain")

      doc = @log |> File.read!() |> Jason.decode!()
      [first | rest] = doc["events"]
      # keep the shape valid, move the time: the bound canon form changes,
      # the recorded rep_hash does not follow.
      first = put_in(first, ["time"], "2026-11-08T00:00:00.001Z")
      File.write!(log, Jason.encode!(put_in(doc, ["events"], [first | rest])))

      assert {:refused, refusals} = RepopOcelVerifier.verify(log, receipt_path: receipt)
      assert {:ocel_chain_broken, detail} = find(refusals, :ocel_chain_broken)
      assert detail =~ "hash mismatch"
    end

    test "re-parenting the second event is refused as a parent mismatch" do
      {log, receipt} = tmp_pair("parent")

      doc = @log |> File.read!() |> Jason.decode!()
      doc = update_in(doc, ["events", Access.at(1), "attributes"], fn attrs ->
        Enum.map(attrs, fn
          %{"name" => "rep_parent"} = a -> put_in(a, ["value"], String.duplicate("a", 64))
          a -> a
        end)
      end)
      File.write!(log, Jason.encode!(doc))

      assert {:refused, refusals} = RepopOcelVerifier.verify(log, receipt_path: receipt)
      assert {:ocel_chain_broken, detail} = find(refusals, :ocel_chain_broken)
      assert detail =~ "parent mismatch"
    end

    test "count lie in the receipt is refused as event_count_mismatch" do
      {log, receipt} = tmp_pair("count")
      receipt_map = decode_receipt(receipt)
      File.write!(receipt, Jason.encode!(%{receipt_map | "event_count" => 4}))

      assert {:refused, refusals} = RepopOcelVerifier.verify(log, receipt_path: receipt)
      assert {:event_count_mismatch, _} = find(refusals, :event_count_mismatch)
    end

    test "head_hash lie in the receipt is refused as head_hash_mismatch" do
      {log, receipt} = tmp_pair("head")
      receipt_map = decode_receipt(receipt)
      File.write!(receipt, Jason.encode!(%{receipt_map | "head_hash" => String.duplicate("0", 64)}))

      assert {:refused, refusals} = RepopOcelVerifier.verify(log, receipt_path: receipt)
      assert {:head_hash_mismatch, _} = find(refusals, :head_hash_mismatch)
    end

    test "receipt algorithm lie is refused as algorithm_mismatch" do
      {log, receipt} = tmp_pair("alg")
      receipt_map = decode_receipt(receipt)
      File.write!(receipt, Jason.encode!(%{receipt_map | "algorithm" => "fnv1a32"}))

      assert {:refused, refusals} = RepopOcelVerifier.verify(log, receipt_path: receipt)
      assert {:algorithm_mismatch, _} = find(refusals, :algorithm_mismatch)
    end

    test "blake3 request is a typed unsupported_algorithm refusal, never a downgraded verify" do
      {log, receipt} = tmp_pair("blake3")
      receipt_map = decode_receipt(receipt)
      File.write!(receipt, Jason.encode!(%{receipt_map | "algorithm" => "blake3"}))

      assert {:refused, refusals} = RepopOcelVerifier.verify(log, receipt_path: receipt, algorithm: :blake3)
      assert {:unsupported_algorithm, detail} = find(refusals, :unsupported_algorithm)
      assert detail =~ "blake3"
    end

    test "missing receipt is a typed refusal" do
      assert {:refused, refusals} = RepopOcelVerifier.verify(@log, receipt_path: "/nonexistent.receipt.json")
      assert {:receipt_missing, _} = find(refusals, :receipt_missing)
    end

    test "unparseable log is a typed refusal" do
      {log, receipt} = tmp_pair("badjson")
      File.write!(log, "{not json")
      assert {:refused, refusals} = RepopOcelVerifier.verify(log, receipt_path: receipt)
      assert {:unparseable_log, _} = find(refusals, :unparseable_log)
    end

    test "malformed envelope (missing objects list) is a typed refusal" do
      {log, receipt} = tmp_pair("shape")
      doc = @log |> File.read!() |> Jason.decode!() |> Map.delete("objects")
      File.write!(log, Jason.encode!(doc))
      assert {:refused, refusals} = RepopOcelVerifier.verify(log, receipt_path: receipt)
      assert {:envelope_malformed, _} = find(refusals, :envelope_malformed)
    end
  end

  describe "cross-vocabulary refusals (both directions)" do
    test "repop log carrying a zcode event type is refused" do
      {log, receipt} = tmp_pair("xvocab-zcode")
      doc = @log |> File.read!() |> Jason.decode!()
      doc = put_in(doc, ["events", Access.at(0), "type"], "turn_started")
      File.write!(log, Jason.encode!(doc))

      assert {:refused, refusals} = RepopOcelVerifier.verify(log, receipt_path: receipt)
      assert {:cross_vocabulary_event_type, detail} = find(refusals, :cross_vocabulary_event_type)
      assert detail =~ "turn_started"
    end

    test "repop log carrying a castle event type is refused" do
      {log, receipt} = tmp_pair("xvocab-castle")
      doc = @log |> File.read!() |> Jason.decode!()
      doc = put_in(doc, ["events", Access.at(0), "type"], "system_bootstrapped")
      File.write!(log, Jason.encode!(doc))

      assert {:refused, refusals} = RepopOcelVerifier.verify(log, receipt_path: receipt)
      assert {:cross_vocabulary_event_type, _} = find(refusals, :cross_vocabulary_event_type)
    end

    test "repop log carrying an out-of-repo object type is refused" do
      {log, receipt} = tmp_pair("xvocab-obj")
      doc = @log |> File.read!() |> Jason.decode!()
      doc = put_in(doc, ["objects", Access.at(0), "type"], "session")
      File.write!(log, Jason.encode!(doc))

      assert {:refused, refusals} = RepopOcelVerifier.verify(log, receipt_path: receipt)
      assert {:cross_vocabulary_object_type, _} = find(refusals, :cross_vocabulary_object_type)
    end

    test "repop log carrying an out-of-vocab qualifier is refused" do
      {log, receipt} = tmp_pair("xvocab-qual")
      doc = @log |> File.read!() |> Jason.decode!()
      doc = put_in(doc, ["events", Access.at(0), "relationships", Access.at(0), "qualifier"], "owns")
      File.write!(log, Jason.encode!(doc))

      assert {:refused, refusals} = RepopOcelVerifier.verify(log, receipt_path: receipt)
      assert {:cross_vocabulary_qualifier, _} = find(refusals, :cross_vocabulary_qualifier)
    end

    test "a repop type in a zcode log is refused by the :zcode direction" do
      doc = %{"events" => [%{"type" => "start"}], "objects" => [%{"type" => "wo"}]}
      assert {:refused, refusals} = RepopOcelVerifier.verify_vocabulary(doc, :zcode)
      assert Enum.any?(refusals, fn {code, _} -> code == :cross_vocabulary_event_type end)
      assert Enum.any?(refusals, fn {code, _} -> code == :cross_vocabulary_object_type end)
    end

    test "a repop type in a castle log is refused by the :castle direction" do
      doc = %{"events" => [%{"type" => "execute"}], "objects" => [%{"type" => "machine"}]}
      assert {:refused, refusals} = RepopOcelVerifier.verify_vocabulary(doc, :castle)
      assert Enum.any?(refusals, fn {code, _} -> code == :cross_vocabulary_event_type end)
      assert Enum.any?(refusals, fn {code, _} -> code == :cross_vocabulary_object_type end)
    end

    test "in-vocabulary doc passes verify_vocabulary(:repop)" do
      doc = %{
        "events" => [%{"type" => "start"}, %{"type" => "fail"}],
        "objects" => [%{"type" => "wo"}, %{"type" => "machine"}]
      }

      assert :ok = RepopOcelVerifier.verify_vocabulary(doc, :repop)
    end
  end

  describe "manifest drift meta-test" do
    @tag :repop_drift
    # BLOCKED-skip when the repop checkout is absent: the drift court cannot
    # run without its live referent.
    @tag skip:
           if(File.exists?(@live_vocab),
             do: false,
             else:
               "BLOCKED: live repop vocab.ts not found at #{@live_vocab} (set REPOP_PATH) — " <>
                 "the drift court cannot run without its live referent"
           )
    test "pinned repop vocabulary manifest does not drift from the live checkout" do
      manifest = RepopOcelVerifier.pinned_manifest(manifest_path: @pinned_manifest)
      live_source = File.read!(@live_vocab)

      # every pinned activity must literally appear in the live ACTIVITY_VOCAB
      Enum.each(manifest["registry"]["event_types"], fn t ->
        assert live_source =~ ~s("#{t}"),
               "pinned activity #{inspect(t)} absent from live vocab.ts — manifest drift"
      end)

      # provenance pin must match the live file's bytes
      live_sha = :crypto.hash(:sha256, live_source) |> Base.encode16(case: :lower)
      assert manifest["provenance"]["source_sha256"] == live_sha,
             "pinned provenance sha256 drifts from live vocab.ts"
    end
  end

  # -- helpers ----------------------------------------------------------------

  defp find(refusals, code) do
    Enum.find(refusals, fn {c, _} -> c == code end) ||
      flunk("expected refusal #{inspect(code)}, got #{inspect(refusals)}")
  end

  defp tmp_pair(tag) do
    dir = Path.join(System.tmp_dir!(), "repop-verifier-#{tag}-#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    log = Path.join(dir, "repop-3event.jsonocel")
    receipt = Path.join(dir, "repop-3event.receipt.json")
    File.cp!(@log, log)
    File.cp!(@receipt, receipt)
    {log, receipt}
  end

  defp decode_receipt(path), do: path |> File.read!() |> Jason.decode!()

  # pure-elixir FNV-1a32 (mirror of the verifier's branch) for the fnv fixture
  defp fnv1a32_hex(data) do
    hash =
      data
      |> :binary.bin_to_list()
      |> Enum.reduce(2_166_136_261, fn byte, h ->
        :erlang.band(:erlang.bxor(h, byte), 0xFFFFFFFF) * 16_777_619
      end)
      |> :erlang.band(0xFFFFFFFF)

    <<hash::unsigned-little-integer-size(32)>> |> Base.encode16(case: :lower)
  end
end
