# Engine-Ops Receipt Chain Law and L129 Court Verdict

## Chain law (as found in code, `lib/beam4pm_receipt_chain.ex`)

`receipts/engine_ops/*.json` are `beam4pm-brce/v1` consequence receipts,
hash-chained per `chain_id`:

- each opted-in receipt carries `chain_id`, `chain_seq` (1-based, required
  gapless), `prev_receipt_path`, and `prev_receipt_hash` = sha256 hex of the
  immediately-prior receipt file's RAW on-disk bytes at write time
  (`BeamPM.ReceiptChain.hash_file!/1`);
- `receipts/engine_ops/.chain-tips/<sha256(chain_id)>.json` records
  `{index_schema: "beam4pm-chain-tip/v1", chain_id, chain_seq, receipt_path}`
  = the newest receipt of the chain (`BeamPM.ReceiptChain.link_fields/3`,
  index-first write, validated read, scan fallback; scan oracle retained as
  `link_fields_by_scan/2`).

This is a real prev-hash law, not per-op logs: every non-genesis receipt
commits to the prior file's bytes.

## Court

`scripts/verify_receipt_chain_tips.exs` (`MIX_ENV=test mix run
scripts/verify_receipt_chain_tips.exs`) recomputes every chain's tip by the
scan oracle, asserts equality with the committed `.chain-tips` entry, runs
`BeamPM.ReceiptChain.verify/2` for every chain, and runs a tamper negative
(mutate the genesis receipt of a /tmp copy of one chain ->
`{:error, {:chain_broken, seq, :hash_mismatch}}`).

## Verdict (2026-10-13, L129, commit base a6f3a212 corpus)

- 79 committed tip index files, 78 chains with receipts on disk.
- Tip recomputation: 79/79 committed tips equal the scan-oracle recomputation
  from the receipt files on disk. No stale or fabricated tip. Zero
  `:tip_mismatch`.
- Full hash-chain verification (`verify/2`): 8/8 ferroplan chains verify
  end-to-end (lengths 8, 71, 40, 41, 81, 41, 14, 18). 70/78 chains are
  PARTIAL: the tip is a correct pointer, prev-hash links among PRESENT
  receipts are consistent, but receipt files for earlier seqs are ABSENT
  from the corpus (e.g. chain `rust4pm.free_net` has 440 of 546 seqs; 106
  missing). This is corpus incompleteness (files absent on disk), not a
  broken prev-hash: the court cannot distinguish "pruned before commit"
  from "never committed" without git history.
- Tamper negative: PASS — mutating a receipt's bytes in a /tmp copy flips
  verify to `:hash_mismatch`.

Standing: chain law ALIVE (producer = `BeamPM.ReceiptChain.link_fields/3`,
consumed by `BeamPM.Actuation`/`ProcessGovernor`); committed corpus
PARTIAL_ALIVE (tips exact, 8 chains full-verify, 70 chains gap-incomplete).
