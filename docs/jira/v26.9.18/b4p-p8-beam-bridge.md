---
id: b4p-p8-beam-bridge
type: oslc_cm:ChangeRequest
requirement: earl:TestRequirement
dcterms:title: "parity: wire beam4pm to autofde-lab's beam-bridge (stdio JSON-lines port bridge) — one persistent channel proven with a real solve+receipt, vs one-shot CLI"
standing: BLOCKED
---
Worktree: ~/beam4pm-worktrees/wt-p8 (branch parity/beam-bridge). Read _CONTEXT.md.
1. Read the lab's bridge implementation (discover: grep src/autofde_lab for
   beam_bridge/cli entry; find the JSON-lines protocol: request/response
   shapes, framing, error envelopes) and its tests.
2. Boot the bridge for real; drive it from Erlang/Elixir via Port
   (stdio). Protocol contract in hand: write
   lib/beam4pm_autofde_bridge.ex (NEW hand-authored file — needs a
   HANDWRITTEN.md ledger row + docs/reference/beam4pm_hand_authored_source.md
   row) implementing request/recv with timeout, framed JSON-lines, and a
   closed-port -> {:error, :bridge_down} path.
3. Prove: one real `fabric solve` (or catalog+match sequence) through the
   persistent bridge, then the SAME call one-shot via BeamPM.Dfcm CLI
   wrapper — same result, and measure both latencies (bridge should win on
   second+ call: no interpreter restart).
4. Supervision: bridge under a simple GenServer with restart (temporarily
   kill the port process and prove recovery).
Gates: real bridge round-trips (command+exit); latency table bridge vs
one-shot; kill-and-recover witnessed; ledger rows for the new file.

## History
| ts | standing | branch+SHA | gates+exits | remaining |
|---|---|---|---|---|
| 2026-09-18T22:30:00Z | ALIVE | parity/beam-bridge @ 3a0b029 | Persistent Port bridge (GenServer, JSON-lines, FIFO waiters, :bridge_down + restart): 8/0 ×3 runs; bridge plan == one-shot cmca plan (structural equality); latency 7.5-36.7ms steady vs 939ms-2.38s one-shot; kill -9 -> on-demand restart witnessed. FINDING: lab bridge exposes NO fabric ops (persistent channel = ping/cmca_allocate/calculate_salience only). Ledger gate PASS 49/42/0 rendered test 19/19; supervision-tree insert left as one-liner for integrator. Remaining: lab bridge fabric ops; main-checkout commit of dfcm twins | coordinator integration |
