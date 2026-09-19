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
| 2026-09-18T16:55:00Z | ALIVE | ferroplan `main @ e90928d` (pushed); beam4pm branch `chore/ferroplan-pin-bump @ 53e31a3` | Scopes 1-3 closed. AUDIT (A8): merge-base 3e1d27a; 10 unique ppcx commits (errc compiler x6, strong policy validator x2, wasm error mapping, CI); 2 patch-id-equivalent already on main; file overlap = wasi_abi.rs ONLY; merge-tree dry run predicted 2 hunks. Reconciliation: fetched 4b8ff2e from beam4pm's submodule clone (ferroplan origin refuses "not our ref" — witnessed), merged --no-ff onto post-wave-6 main per the repo's serial frozen-SHA merge law; resolved wasi_abi.rs: doc union (FP_HDDL_ROOT_MISMATCH + timeout/panic codes), code follows main's names (FP_TIMEOUT/FP_WORKER_PANICKED); ppcx distinguishability test re-derived to reconciled names (flip-class row, f5-06); wasm tests 12/12; pushed e90928d. BUMP: beam4pm submodule -> e90928d, wasm rebuilt (`-p ferroplan-wasm` — workspace-wide wasm build fails on pre-existing ferroplan-mcp tokio rt-multi-thread, NOT caused by the merge), ferroplan tests 15/15 + facades 20/0/9-skip, FULL beam4pm suite 1087/0 with all natives rebuilt — ZERO beam4pm assertion flips (merge preserved solve_x* fixtures). Staged on branch pending beam4pm main checkout (concurrent session). REMAINING: merge 53e31a3 to beam4pm main; autofde-lab re-pin (own ticket; PIN-DRIFT-filing.md in wt-f5-pin-audit: actual path src/autofde_lab/wasm/_registry.py:172, 199 behind pushed origin, receipts bound via _model.py:202 source_revision) | beam4pm main merge; autofde-lab re-pin ticket |
| 2026-09-18T19:00:00Z | ALIVE | beam4pm `main @ 36b0ed9` (local; checkout still carries concurrent-session files — push left to tree owner) | Scope 3 CLOSED on main: `merge --no-ff chore/ferroplan-pin-bump` (native/ferroplan -> e90928d) landed clean alongside the dirty tree (merge touched only the submodule pointer). Beam4pm now runs the reconciled post-wave-6 engine on its main line. Remaining from this ticket: only the autofde-lab re-pin (own ticket, filing staged in wt-f5-pin-audit PIN-DRIFT-filing.md) | autofde-lab re-pin |
