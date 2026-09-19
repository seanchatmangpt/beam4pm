# _CONTEXT.md — v26.9.18 autofde-lab parity wave (beam4pm family)

Read this before any ticket in this directory. Observed 2026-09-18.

## Mission

`~/autofde-lab` (master @ fe81a552, venv at .venv) exposes a Typer CLI
(`python -m autofde_lab.cli`, also `autofde`/`autofde-lab` scripts) with five
command groups. beam4pm's `BeamPM.Dfcm` (lib/beam4pm_dfcm.ex, hand-authored
bridge; priv/bin/autofde trampoline; 16/0 dfcm tests) surfaces only PART of
it today: `fabric catalog`, `ocel conformance`, `sa2a graphlaw
hash|validate|hooks`. Parity = every lab capability beam4pm's mission needs
is (a) surfaced through a real beam4pm seam, (b) cross-validated against the
family's own engines (ferroplan wasm, RF1-RF4 oracles, ReceiptChain,
POWLConformance), and (c) ledgered (new hand-written bridge functions are
sanctioned in lib/beam4pm_dfcm.ex — the file already owns this class; add a
HANDWRITTEN ledger row per the 帳 law).

## Lab CLI surface (verified 2026-09-18)

- fabric: catalog | match | solve | cache-stats | cache-hotset |
  dmedi-solve-payoff | serve-mcp
- ocel: validate (Küsters & van der Aalst 2025) | conformance
- sa2a: validate | admit (§64 admission court) | plan | execute | replay
  (§38 cryptographic receipt/plan hash) | graphlaw (hash/validate/hooks —
  already bridged) | chicago (Canonical Chicago DoD Court)
- cmca: allocate (certified multifractal allocation) | salience (Q16.16)
- beam-bridge: BEAM cluster stdio JSON-lines port bridge loop

## Family state feeding this wave

- ferroplan reconciled @ e90928d, tag v0.28.0, pushed; beam4pm submodule
  bump merged (36b0ed9). autofde-lab's wasm registry pin is STALE:
  src/autofde_lab/wasm/_registry.py:172 revision="282fae46..." (199 behind
  pushed ferroplan origin/main; receipts bind via
  src/autofde_lab/_model.py:202 source_revision equality — b4p-f5-05 scope 4).
- ash_a2a main @ baa135d carries the b4p-f5-10 CommandBus fix (dispatch/6,
  resolved_skill opt) — not yet in a hex release.
- beam4pm dfcm fixtures: qualification/fixtures/dfcm/ (abcx-problem.pddl,
  dfcm-fond.pddl, dfcm.hddl); gym captures qualification/gym_bridge/.
- beam4pm ReceiptChain, POWLConformance, RF1-RF4 oracles all build green.

## Wave law

Agents receive a ticket path + private worktree. Search ~/ for answers
before writing (REUSE ladder). ALIVE requires observed execution this
session. New hand-written bridge functions land ONLY in
lib/beam4pm_dfcm.ex (the sanctioned bridge file) with a HANDWRITTEN.md
ledger row; never hand-edit generated facades. No push, no merge to main
checkouts; commit on your branch; write WAVE-RECEIPT.md at your worktree
root; report 比 honestly.
