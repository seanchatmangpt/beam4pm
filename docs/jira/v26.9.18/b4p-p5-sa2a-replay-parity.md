---
id: b4p-p5-sa2a-replay-parity
type: oslc_cm:ChangeRequest
requirement: earl:TestRequirement
dcterms:title: "parity: sa2a replay (§38 cryptographic receipt/plan hash) cross-validated vs BeamPM.ReceiptChain on real receipts"
standing: BLOCKED
---
Worktree: ~/beam4pm-worktrees/wt-p5 (branch parity/sa2a-replay). Read _CONTEXT.md.
1. `autofde sa2a replay --help`. Collect real receipts: beam4pm
   research/erc/ERC-00*.json (12+ exist), qualification receipts, and a
   fabric solve receipt from P1's domain if available.
2. Replay each for real through sa2a replay; also run beam4pm's
   BeamPM.ReceiptChain verification (see its test file for the real API) on
   the same artifacts.
3. Cross-validation: which receipt classes each verifier accepts; hash
   algorithm parity (sha256 vs BLAKE3 vs lab's scheme); divergence table
   with attribution. A tampered-control (flip one byte) must be refused by
   BOTH — prove the negative control.
4. Document (implement only if pure passthrough) a Dfcm.sa2a_replay/1
   wrapper.
Gates: real replay runs (command+exit per receipt class); negative control
witnessed both sides; divergence table; ledger row if wrapper added.

## History
| ts | standing | branch+SHA | gates+exits | remaining |
|---|---|---|---|---|
| 2026-09-18T22:30:00Z | ALIVE core | parity/sa2a-replay @ 9388c60 | 157 real engine_ops chain receipts (6 gap-free chains) ReceiptChain-verified; fabric solve receipt subject-quintet replay ok; 1-byte tamper REFUSED BY BOTH (lab {ok:false} exit 1; ReceiptChain {:chain_broken, 2, :hash_mismatch}); reserialization contrast (lab accepts, ReceiptChain refuses raw-bytes) + fabric subject-scope blind spot (composed replay catches) documented. sa2a_replay/1 added; 3/0; dfcm 16/16; ledger +3. Remaining: 2 pre-existing :enospc-blocked load tests (host disk peak); dfcm digest reconciliation to coordinator | coordinator integration |
