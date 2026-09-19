---
id: b4p-p1-fabric-solve-parity
type: oslc_cm:ChangeRequest
requirement: earl:TestRequirement
dcterms:title: "parity: fabric match + solve (receipt-bearing trajectories) surfaced in BeamPM.Dfcm and cross-validated vs beam4pm's native ferroplan hddl_solve/fond_policy"
standing: BLOCKED
---
Worktree: ~/beam4pm-worktrees/wt-p1 (branch parity/fabric-solve). Read _CONTEXT.md.
1. Discover the real contracts: `priv/bin/autofde fabric match --help` and
   `fabric solve --help` (args, output JSON, receipt shape). Run both for
   real on a domain beam4pm owns fixtures for (qualification/fixtures/dfcm/
   dfcm.hddl + dfcm-fond.pddl; qualification/gym_bridge/ logs).
2. Add BeamPM.Dfcm.fabric_match/2 and fabric_solve/2 (one-shot CLI, same
   style as the existing catalog/ocel_conformance wrappers) + @specs +
   doctests.
3. Cross-validate: solve the SAME fixture through fabric solve AND through
   beam4pm's native BeamPM.Ferroplan.hddl_solve/fond_policy (wasm). Record
   both verdicts + receipts; explain any divergence (engine pin e90928d vs
   lab's registry pin 282fae4 — that drift is P9's ticket; do not fix it
   here, just attribute it).
4. Tests in test/beam4pm_dfcm_test.exs idiom; all green.
Gates: wrappers run for real (command+exit in receipt); cross-validation
table (fixture | fabric verdict | ferroplan verdict | divergence note);
HANDWRITTEN.md row for the new bridge functions.

## History
| ts | standing | branch+SHA | gates+exits | remaining |
|---|---|---|---|---|
| 2026-09-18T22:30:00Z | ALIVE | parity/fabric-solve @ 95ab1ac (base 36b0ed9) | fabric solve HTNDomain on dfcm.hddl: SOLVED, 8 steps, receipt ab8521ed; ferroplan wasm e90928d cross-validates (9 policy entries = 8 primitives + root decompose — same ladder, semantic parity). Honest negative: NO family engine ingests FOND PDDL text (lab SKD-FABRIC-008; ferroplan FP_ADAPTER) — capability gap on record. fabric_match/2 + fabric_solve/2 added (lib sha 9f305132), baseline committed byte-identical sha-verified; gate 50/43; parity tests 22/0. Falsifiers: stdout-noise JSON decode (fixed), parser-recovery false-SOLVED (refused honestly), foreign sha drift (reverted). Remaining: P9 pin; lab match false-positive + stdout hygiene; pack-side ontology sync | coordinator integration |
