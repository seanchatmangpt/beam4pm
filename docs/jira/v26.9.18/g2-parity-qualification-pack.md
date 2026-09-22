---
id: g2-parity-qualification-pack
dcterms:title: "pack facts that render cross-engine parity qualification tests (retire the P2/P5/P10 hand-written class)"
standing: BLOCKED
---
Worktree: ~/ggen-marketplace-wt/g2 (branch pack/parity-qualification). Proof
scratch: /Users/sac/beam4pm-worktrees/wt-g2-proof. Read _G-CONTEXT.md.
Author bpm:ParityCheck vocabulary (left/right engine commands, corpus,
digest pins, tamper falsifier, consent law) + template rendering parity
test files in the shape P2/P5/P10 hand-wrote. PROOF: render ONE new parity
check from facts only (ferroplan hddl_solve vs lab fabric solve verdict
parity on qualification/fixtures/dfcm/) that runs green in the proof
worktree; gate refuses a parity check whose corpus files don't exist.
Pack version bump + dated description.

## History
| ts | standing | branch+SHA | gates+exits | remaining |
|---|---|---|---|---|
| 2026-09-19T00:30:00Z | ALIVE | marketplace pack/parity-qualification @ b17801f8e | bpm:ParityCheck family + test template + gates 100/110/120; pack 0.1.20. Proof: rendered parity test (268 lines, dry-run exactly-one-output) ferroplan hddl_solve vs lab fabric solve — 4/0 ×3 seeds vs real engines, deterministic pins; tamper falsifier witnessed pre-pinning; corpus gate refuses at graph (FM-PACK-013) AND disk level. 比: retired class = 213-282 hand lines/check; future check = 78 lines admission, 0 test code; one-time pack cost ~590 lines. Remaining: 2-3 more command kinds retire actual P2/P5/P10 files | cutover at integration |
