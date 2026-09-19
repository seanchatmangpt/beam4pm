defmodule BeamPM.DfcmSa2aReplayTest do
  use ExUnit.Case, async: true

  # Chicago qualification for BeamPM.Dfcm.sa2a_replay/1 (§38 parity, ticket
  # b4p-p5-sa2a-replay-parity): the wrapper is a PURE PASSTHROUGH to the
  # standalone AutoFDE `sa2a replay` command, so these tests verify the real
  # CLI subprocess verdicts end to end -- positive, tamper-refusal, and the
  # canonicalization boundary documented against BeamPM.ReceiptChain
  # (sha256 over canonical JSON, never raw file bytes).

  alias BeamPM.Dfcm

  # The lab's sa2a replay hashes exactly this canonical form (src/autofde_lab/
  # sa2a/cli.py: json.dumps(data, sort_keys=True, separators=(",", ":"))
  # .encode("utf-8") -> sha256 hexdigest). Computing the expected digest here
  # with :crypto keeps the test's expectation independent of the subprocess
  # under test: if either side drifted from the canonical form, the verdicts
  # below could not all hold at once.
  defp canonical_sha256(manifest_json) do
    body =
      manifest_json
      |> JSON.decode!()
      |> Enum.sort_by(fn {key, _} -> key end)
      |> Enum.map_join(",", fn {key, value} ->
        JSON.encode!(key) <> ":" <> JSON.encode!(value)
      end)

    :crypto.hash(:sha256, "{" <> body <> "}") |> Base.encode16(case: :lower)
  end

  @manifest ~s({"claim": "b4p-p5-sa2a-replay-parity", "seq": 1})

  test "wrapper passes a verifying manifest through to the lab's own {:ok, verdict}" do
    assert Dfcm.autofde_cli_available?()

    expected = canonical_sha256(@manifest)

    assert {:ok, %{"ok" => true, "verified" => true} = verdict} =
             Dfcm.sa2a_replay(%{manifest_json: @manifest, expected_hash: expected})

    assert verdict["computed_hash"] == expected
    assert verdict["expected_hash"] == expected
  end

  test "REAL FALSIFIER: a 1-byte tampered manifest is refused with the lab's own verdict" do
    expected = canonical_sha256(@manifest)
    # ONE byte: seq 1 -> 2 (same length, different content, different hash)
    tampered = String.replace(@manifest, "\"seq\": 1", "\"seq\": 2")
    assert tampered != @manifest

    assert {:error, {:replay_refused, %{"ok" => false, "verified" => false} = verdict}} =
             Dfcm.sa2a_replay(%{manifest_json: tampered, expected_hash: expected})

    assert verdict["computed_hash"] != expected
    assert verdict["expected_hash"] == expected
  end

  test "canonicalization boundary: whitespace-only re-serialization still verifies" do
    # Raw bytes differ from @manifest, JSON semantics do not -- the lab's
    # canonical-JSON hash accepts what a raw-byte hash (ReceiptChain) would
    # refuse. Witnessed on real receipts in the wave receipt; pinned here as
    # the documented divergence between the two verifiers.
    reserialized = "{\n  \"seq\": 1,\n  \"claim\": \"b4p-p5-sa2a-replay-parity\"\n}\n"
    expected = canonical_sha256(@manifest)

    assert {:ok, %{"ok" => true, "verified" => true}} =
             Dfcm.sa2a_replay(%{manifest_json: reserialized, expected_hash: expected})
  end
end
