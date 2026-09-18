---
id: b4p-f5-05-ferroplan-pin-three-way-reconciliation
type: oslc_cm:ChangeRequest
requirement: earl:TestRequirement
dcterms:title: "beam4pm: three-way ferroplan pin reconciliation (ppcx facade line vs hardened main vs origin) + submodule bump to a single post-wave-6 commit"
standing: BLOCKED
branch: chore/ferroplan-pin-reconcile
worktree: (beam4pm main checkout — serialize; see _CONTEXT.md concurrent-writer note)
created: 2026-09-17T21:40:00Z
source: observed 2026-09-17: native/ferroplan @ 4b8ff2e (feat/ppcx-hddl-solve-wasm-facade, 25 ahead/1 behind its origin/main, absent from ~/ferroplan's object store); ~/ferroplan main @ 6cacbda 185 ahead of origin; autofde-lab _registry.py pin 282fae4 (384 behind)
depends: b4p-f5-04
---

Read `_CONTEXT.md` first. This is the ticket that turns "ferroplan landed"
into "beam4pm runs the landed engine". The engine is currently pinned to a
**divergent feature line** (`feat/ppcx-hddl-solve-wasm-facade @ 4b8ff2e` —
errc operator compiler, SOLVE(x) HDDL grammar, wasm facade work) that shares
no object with ~/ferroplan's main, where the FOND-HTN hardening lives. Three
pins of the same engine exist across the family; beam4pm must become the
reunion point, not a fourth line.

## Scope

1. Fetch the pushed post-wave-6 `main` (output of b4p-f5-04) into the
   submodule clone; verify `4b8ff2e`'s unique 25 commits (errc/SOLVE(x)/
   facade line) against what main now contains — main's own wasm-ABI commits
   (`fix: session_replan budget/orbit wiring, wire HDDL through wasm ABI`,
   `adapt hddl.rs/wasi_abi.rs to TranslateLimits`) may already overlap.
   Produce a real overlap/unique audit (commits + files), not an assumption.
2. Three-way reconcile: rebase or merge the ppcx line onto the pushed main
   (prefer whichever history RELEASING.md/CONTRIBUTING of ferroplan
   prescribes), resolve, and push the reconciled line to ferroplan origin so
   the reconciliation itself is reviewable there — beam4pm must not carry a
   private engine commit that exists nowhere upstream.
3. Bump `native/ferroplan` to the reconciled commit; rebuild
   `wasm32-wasip1`; commit the submodule pointer bump atomically with any
   beam4pm-side adaptation.
4. Record the reunification in the other pin-holder: file (do not silently
   fix) the autofde-lab `_registry.py` pin drift (`282fae4`, 384 behind) —
   that repo's receipts bind to its pin and its upgrade is its own ticket;
   this ticket only leaves the named pointer.

## Gates

- Overlap audit artifact committed under `docs/jira/v26.9.17/` (append-only
  addendum to this ticket or a linked file) with real `git log`/`diff`
  output.
- Reconciled branch pushed to ferroplan origin; submodule pointer ==
  a commit on that branch; `git submodule status` clean.
- `cargo build -p ferroplan-wasm --target wasm32-wasip1` exit 0 in the
  submodule.
- beam4pm: `mix test test/beam4pm_ferroplan_test.exs
  test/beam4pm_ferroplan_facades_test.exs` exit 0 — the Elixir/Erlang/Gleam
  parity facades all green on the reconciled engine.

## History
| ts | standing | branch+SHA | gates+exits | remaining |
|---|---|---|---|---|
| 2026-09-17T21:40:00Z | BLOCKED | — | — | all |
| 2026-09-18T00:00:00Z | PARTIAL_ALIVE (scope 1+4 PREP only) | `chore/ferroplan-pin-audit` @ wt-f5-pin-audit (base 22fa4aa); gate artifacts linked: `AUDIT.md`, `PIN-DRIFT-filing.md`, `WAVE-RECEIPT.md` (worktree root, committed on this branch) | scope 1: overlap audit ALIVE — real plumbing, both stores local (origin itself refuses 4b8ff2e "upload-pack: not our ref" — divergence witnessed by the remote); 4b8ff2e vs 6cacbda = 13L/174R @ merge-base 3e1d27a; unique-left 10 (2 patch-id-equivalent: d493c19≡47a898c, 29134d7≡658ea7b — scope-1's hypothesized overlap CONFIRMED); overlap files = `crates/ferroplan-wasm/src/wasi_abi.rs` ONLY (ppcx∩d00dcf8=∅); merge-tree dry-run vs 6cacbda AND d00dcf8: 1 file, 2 hunks (doc union + FP_TIMEOUT/FP_WORKER_PANICKED vs FP_HDDL_TIMEOUT/FP_HDDL_WORKER_PANIC — main's names win; beam4pm asserts neither); reconcile recommendation MERGE --no-ff, not rebase (AUDIT.md §4). scope 4: autofde-lab pin FILED not fixed (PIN-DRIFT-filing.md): 282fae4 @ src/autofde_lab/wasm/_registry.py:172, 0/384 vs local main 6cacbda, 199 behind already-pushed origin/main (fast-forward re-pin possible), receipts bound via _model.py:202 source_revision equality. No builds, no engine runs, no pushes, main checkout never written | scope 2 (merge+push; BLOCKED by b4p-f5-04), scope 3 (bump+rebuild+mix test), autofde re-pin (own ticket) |
