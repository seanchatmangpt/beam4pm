---
id: b4p-p7-cmca-allocator-parity
type: oslc_cm:ChangeRequest
requirement: earl:TestRequirement
dcterms:title: "parity: cmca allocate/salience (certified multifractal allocation + Q16.16) wired as BeamPM.Dfcm.allocate_options/2's real path (replacing the uniform fallback when the CLI is available)"
standing: BLOCKED
---
Worktree: ~/beam4pm-worktrees/wt-p7 (branch parity/cmca-allocator). Read _CONTEXT.md.
lib/beam4pm_dfcm.ex allocate_options/2 currently checks
Code.ensure_loaded?(AshAutofde.CascadeAllocator) — never loaded — and
falls back to uniform shares. The certified allocator is the lab's
`cmca allocate` + `cmca salience` (Q16.16 fixed-point).
1. `autofde cmca allocate --help` and `salience --help`; run both for real
   on BeamPM.Dfcm.benchmark()'s A/B/C problem (the module's own doc example)
   and on a 25-branch synthetic budget.
2. Extend BeamPM.Dfcm.allocate_options/2: when the autofde CLI is
   available (autofde_cli_available?()), allocate via `cmca allocate`
   (parse its JSON; map to the existing allocation shape
   branch_id/allocated_fraction/standing); keep the uniform fallback ONLY
   when the CLI is absent (preserving the existing contract + tests).
3. Properties: budget-exactness (fractions sum to 1.0 within Q16.16
   epsilon), determinism (same input -> same allocation), option
   preservation (no surviving candidate gets 0 unless the lab's law says
   so — document what cmca actually guarantees).
4. Tests: real-CLI path + absent-CLI fallback path both green.
Gates: real cmca runs (command+exit); allocation-parity table (cmca vs
old uniform on the same budget); ledger row for the lib change.

## History
| ts | standing | branch+SHA | gates+exits | remaining |
|---|---|---|---|---|
| 2026-09-18T22:30:00Z | ALIVE | parity/cmca-allocator @ 78ae830 | allocate_options/2 now routes through certified cmca allocate when CLI available: A/B/C parity 0.319/0.319/0.362 (salience-aware) vs uniform 1/3; deterministic byte-identical; budget-exact; >8 candidates typed BcinrCardinalityRefusal (upstream CMCA-108; chunking refused — would fabricate past the law); dead CascadeAllocator probe removed. 24/0; gate 19/19; ledger 50/43 ceiling 37, lib sha 72e671f1. Lab CLI inline-JSON ENAMETOOLONG (temp-file transport workaround) = same defect P10 found. Remaining: upstream lab fixes | coordinator integration |
