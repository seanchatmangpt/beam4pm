---
id: b4p-p10-graphlaw-cross-hash-parity
type: oslc_cm:ChangeRequest
requirement: earl:TestRequirement
dcterms:title: "parity: GraphLaw triangle — same TTL yields the same BLAKE3 graph hash and same validate/hooks verdicts via lab sa2a graphlaw, beam4pm BeamPM.Dfcm (priv/bin/autofde), and beam4pm's in-repo praxis/graphlaw engine"
standing: BLOCKED
---
Worktree: ~/beam4pm-worktrees/wt-p10 (branch parity/graphlaw-triangle). Read _CONTEXT.md.
1. Corpus: beam4pm ontology.ttl (admitted graph), the dfcm fixtures' TTLs
   if any, a synthesized minimal TTL with one SHACL violation, and an N3
   denial case. Hash each with: (a) lab `sa2a graphlaw hash` via
   ~/autofde-lab/.venv directly, (b) BeamPM.Dfcm.graphlaw_hash
   (priv/bin/autofde trampoline — same binary, proves the trampoline adds
   no drift), (c) beam4pm's own in-repo graphlaw engine (discover it:
   grep lib/ for graphlaw/praxis — ash_a2a's vendored praxis wasm is
   upstream; if beam4pm has no in-repo engine, document the triangle as a
   DUO and say where the third corner actually lives).
2. Verdict parity: `sa2a graphlaw validate --shacl` on the violation TTL
   via both paths; `graphlaw hooks` on a base+event TTL pair via both
   paths. Same verdict + same stage codes?
3. Divergence table with attribution (version skew of the wasm artifact is
   the expected cause class — reference P9's pin bump).
4. Tests: pin the triangle (or duo) as a beam4pm test with the corpus
   digests recorded, so future engine bumps trip it (f5-06-style
   flip-ledger for graphlaw).
Gates: real runs (command+exit+digests); parity table; permanent test;
ledger row if lib changed.

## History
| ts | standing | branch+SHA | gates+exits | remaining |
|---|---|---|---|---|
| 2026-09-18T22:30:00Z | ALIVE | parity/graphlaw-triangle @ db397e9 | DUO + engine pin (beam4pm has no in-repo graphlaw engine; third corner ~/praxis @ 31f149dd, artifact byte-verified). Lab CLI vs trampoline: identical BLAKE3 digests + verdict/stage codes on all carryable inputs; canonical-graph property witnessed (21KB dup-prefix variant hashes identically); parity-of-refusal on 1.5MB ontology.ttl (transport ceiling). 1-byte mutation moves digest (ledger trips). Transport ceilings attributed to lab seam: Node E2BIG ~1MiB; sa2a/cli.py:311 ENAMETOOLONG >1KB. BeamPM.GraphlawParityTest 7/0 ×2 pins digests permanently. ENV REPAIR: restored uv cpython exec bit lost in fleet disk-full window (had broken lab venv fleet-wide). Remaining: upstream transport fix; AFDE-2612 hooks literal-decode | lab upstream |
