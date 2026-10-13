# L129 court: verify the committed receipts/engine_ops corpus's hash chain
# and per-chain tip index against the receipts themselves.
#
# Chain law (lib/beam4pm_receipt_chain.ex, BeamPM.ReceiptChain):
#   - each receipt file carries chain_id, chain_seq (1-based, gapless),
#     prev_receipt_path, prev_receipt_hash = sha256 of the PRIOR receipt's
#     raw on-disk bytes at write time.
#   - .chain-tips/<sha256(chain_id)>.json holds {index_schema, chain_id,
#     chain_seq, receipt_path}: the newest receipt of the chain.
#
# This court:
#   1. recomputes each chain's tip by scan (link_fields_by_scan/2 oracle)
#      and asserts it equals the committed .chain-tips entry;
#   2. runs BeamPM.ReceiptChain.verify/2 for every chain (recomputes every
#      prev_receipt_hash from current disk bytes);
#   3. tamper negative: copies the corpus to a fresh /tmp dir, flips one
#      byte in one receipt, and asserts verify/2 FAILS there.
#
# Run: mix run scripts/verify_receipt_chain_tips.exs
# Exit 0 = all courts pass; nonzero = a court failed.

alias BeamPM.ReceiptChain

dir = Path.absname(System.get_env("RECEIPTS_DIR") || "receipts/engine_ops")
tips_dir = Path.join(dir, ".chain-tips")

unless File.dir?(dir) do
  IO.puts("FAIL: no receipts dir at #{dir}")
  System.halt(2)
end

tip_files = Path.wildcard(Path.join(tips_dir, "*.json"))

IO.puts("receipts dir: #{dir}")
IO.puts("committed tip index files: #{length(tip_files)}")

tip_file_for = fn tip_file, chain_id ->
  tip_file
  |> File.read!()
  |> JSON.decode!()
  |> Map.get("chain_id") == chain_id
end

failures = []

# -- Court 1+2: recompute every chain tip + full hash-chain verification --
{failures, n_chains} =
  Enum.reduce(tip_files, {failures, 0}, fn tip_file, {fails, n} ->
    tip =
      tip_file
      |> File.read!()
      |> JSON.decode!()

    chain_id = tip["chain_id"]
    {fails, n} =
      with %{"chain_id" => ^chain_id, "chain_seq" => seq, "receipt_path" => path} <- tip,
           true <- is_integer(seq) and is_binary(path) do
        # scan oracle: highest chain_seq receipt for this chain_id on disk
        # now. link_fields_by_scan/2 returns the NEXT link (tip.seq + 1), so
        # the committed tip's seq must equal scan.chain_seq - 1, and its
        # receipt_path must equal the scan's prev_receipt_path.
        expected_tip =
          case ReceiptChain.link_fields_by_scan(dir, chain_id) do
            # no receipts on disk for this chain
            %{chain_seq: 1} -> nil
            %{chain_seq: s, prev_receipt_path: p} ->
              %{"chain_seq" => s - 1, "receipt_path" => p}
          end

        cond do
          expected_tip == nil ->
            {[{tip_file, :tip_without_any_receipt_on_disk} | fails], n}

          expected_tip != %{"chain_seq" => seq, "receipt_path" => path} ->
            {[{tip_file, {:tip_mismatch, expected: expected_tip}} | fails], n}

          true ->
            case ReceiptChain.verify(dir, chain_id) do
              {:ok, %{length: len}} ->
                IO.puts("  OK  #{chain_id}: tip seq=#{seq} matches scan; verify length=#{len}")
                {fails, n + 1}

              {:error, {:chain_broken, broke_seq, reason}} ->
                {[{tip_file, {:chain_broken, broke_seq, reason}} | fails], n}
            end
        end
      else
        _ -> {[{tip_file, :malformed_tip_index} | fails], n}
      end

    {fails, n}
  end)

# -- Court 3: tamper negative on a /tmp copy --
tamper_failures =
  case tip_files do
    [] ->
      []

    _ ->
      # take the first chain with length >= 2 so a mid-chain tamper is real.
      # Disk is tight on this host: copy only THAT chain's receipt files into
      # the /tmp dir, not the whole 113 MB corpus.
      {chain_id, paths} =
        Enum.find_value(tip_files, fn tf ->
          t = tf |> File.read!() |> JSON.decode!()
          case ReceiptChain.verify(dir, t["chain_id"]) do
            {:ok, %{length: len, receipt_paths: ps}} when len >= 2 ->
              {t["chain_id"], ps}

            _ ->
              nil
          end
        end) || (IO.puts("FAIL: no chain with length >= 2 for tamper negative") && System.halt(3))

      tmp = Path.join(System.tmp_dir!(), "l129-tip-court-" <> Integer.to_string(:os.system_time()))
      File.mkdir_p!(Path.join(tmp, ".chain-tips"))

      Enum.each(paths, fn p ->
        File.write!(Path.join(tmp, Path.basename(p)), File.read!(p))
      end)

      # sanity: the copied chain verifies before the tamper
      {:ok, _} = ReceiptChain.verify(tmp, chain_id)

      # mutate the genesis receipt's bytes (non-tip, mid-chain)
      genesis = List.first(paths)
      raw = File.read!(genesis)
      File.write!(Path.join(tmp, Path.basename(genesis)), String.replace_prefix(raw, "{", "{\"tampered\":true,"))

      result =
        case ReceiptChain.verify(tmp, chain_id) do
          {:error, {:chain_broken, _seq, :hash_mismatch}} ->
            IO.puts("  OK  tamper negative: mutated #{Path.basename(genesis)} -> hash_mismatch")
            []

          {:error, {:chain_broken, _seq, reason}} ->
            [{Enum.find(tip_files, fn tf -> tip_file_for.(tf, chain_id) end), {:tamper_detected_but_wrong_reason, reason}}]

          {:ok, _} ->
            [{Enum.find(tip_files, fn tf -> tip_file_for.(tf, chain_id) end), :tamper_not_detected}]
        end

      File.rm_rf!(tmp)
      result
  end

failures = failures ++ tamper_failures

if failures == [] do
  IO.puts("PASS: #{n_chains} chains, tips recomputed == committed tips; hash chains intact; tamper detected.")
else
  Enum.each(failures, fn f -> IO.inspect(f, label: "FAIL") end)
  System.halt(1)
end
