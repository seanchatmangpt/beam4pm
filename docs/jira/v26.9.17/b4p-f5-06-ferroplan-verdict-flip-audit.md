---
id: b4p-f5-06-ferroplan-verdict-flip-audit
type: oslc_cm:ChangeRequest
requirement: earl:TestRequirement
dcterms:title: "beam4pm: post-bump verdict-flip audit — re-derive every fixture/test expectation touched by the hardened engine; quarantine pre-wave-6 strong-cyclic evidence"
standing: BLOCKED
branch: chore/ferroplan-verdict-flip-audit
worktree: (beam4pm main checkout)
created: 2026-09-17T21:40:00Z
source: beam4pm ace23e5 bridge-c correction precedent (false-positive solve -> real NoPlan/FP_MODEL) + session-measured preview 2026-09-17 (verify-and-commit fixture solved=true 6-entry policy; a larger FOND pair -> NoPlan under full empty-task-network semantics; scratch runner /tmp/fp-probe vs ferroplan main @ 6cacbda)
depends: b4p-f5-05
---

Read `_CONTEXT.md` first. Verdict flips are **the** propagation mechanism of
engine hardening into beam4pm: the last pin bump already flipped one test
from a false-positive solve to a real `NoPlan`/`FP_MODEL` refusal. The
wave-6 hardening is larger (two strong-cyclic soundness fixes, grounding
prune, translate caps). Nothing may be "re-run and patched to green" — every
flip is either re-derived from the new semantics or escalated.

## Scope

1. Enumerate every beam4pm fixture/test whose recorded expectation includes
   a solve/NoPlan verdict, a policy, or an `FP_*` error code (ferroplan
   tests, facade parity tests, eds/qualification paths that consume engine
   output, `qualification/gym_bridge` capture-derived expectations).
2. Run them against the reconciled pin; for each flip: state which upstream
   change caused it (name the ticket: 57 choice-rewrite, 58 drop-retry,
   60 grounding prune, 65 translate plumbing...), and re-derive the correct
   expectation from the new engine semantics. Where the new verdict is
   `NoPlan` for a fixture believed solvable-by-design, that is a **semantic
   divergence to adjudicate upstream**, not a test to relax — file it in
   ferroplan with the reproducer; the known live case class is goal-set
   semantics (e.g. extended-goal typed-stop acceptance vs pure empty-network
   termination).
3. **Evidence quarantine:** audit existing beam4pm receipts/ERC files and
   qualification artifacts for strong-cyclic verdicts produced by the
   pre-wave-6 engine; mark them superseded-by-engine-fix with pointers to
   the re-runs. No Fortune-5 evidence pack may cite a pre-fix strong-cyclic
   verdict as current.
4. Add a tripwire: a small fixture pair set (one deterministic-solve, one
   retry-loop strong-cyclic, one dead-end NoPlan) run on every future
   submodule bump, asserting recorded verdicts — so the next bump's flips
   are caught by a gate, not by a customer.

## Gates

- Flip audit table committed (fixture | old verdict | new verdict | cause
  ticket | disposition) — empty rows forbidden; "no flip" is a row.
- `mix test` green with re-derived expectations; any upstream divergence
  filed with reproducer (link here).
- Quarantine sweep: zero un-marked pre-wave-6 strong-cyclic verdicts
  reachable from current evidence indexes (grep + list in History).
- Tripwire test added and green.

## History
| ts | standing | branch+SHA | gates+exits | remaining |
|---|---|---|---|---|
| 2026-09-17T21:40:00Z | BLOCKED | — | — | all |
| 2026-09-18T16:55:00Z | PARTIAL_ALIVE | beam4pm branch `chore/ferroplan-verdict-flip-audit @ bda457f` | Scopes 1+3 done pre-bump; scope-2 loop now UNBLOCKED by the e90928d reconciliation. FLIP-LEDGER.md: 26 rows (9 ferroplan tests, 9 facades, 5 pddl_projection, 1 lib doc contract, 2 external pairs; bounds recorded: 98 raw hits, noise classes named). 8 real verdict runs vs 6cacbda via rebuilt /tmp/fp-probe: bridge-c FP_MODEL/NoPlan HOLDS; fixture-a solved/4 HOLDS; solve_x solved/8 HOLDS; verify-and-commit solved/6 HOLDS (preview reproduced); sa2a NoPlan @ 4729ms (goal-set divergence — file upstream, do NOT relax); two-room solved/1 + broken-control false; malformed FP_PARSE. Row 5a (solve_x* File.read! post-bump) RESOLVED-BY-RECONCILIATION: the e90928d merge kept the ppcx fixtures. Quarantine scope 3: 0 artifacts cite pre-wave-6 strong-cyclic verdicts (research/erc 12x ERC-002 conformance only) — gate already satisfied at 22fa4aa. POST-BUMP beam4pm suite at e90928d: 1087/0 — no beam4pm-level flip fired. New flip recorded upstream-side: ferroplan-wasm error-code rename test (re-derived on the reconciliation). REMAINING: sa2a NoPlan goal-set divergence filed in ferroplan; scope-4 tripwire gate | sa2a upstream filing; tripwire |
| 2026-09-18T19:00:00Z | PARTIAL_ALIVE | divergence filed upstream | sa2a goal-set divergence FILED as ferroplan `docs/jira/v26.9.17/fond-htn-67-sa2a-goal-set-semantics-divergence.md` (ruling requested: pure empty-network termination vs extended-goal typed stop; beam4pm expectation explicitly NOT to be relaxed pending the ruling). Post-bump beam4pm suite at e90928d: 1087/0 — no remaining beam4pm-level flips | scope-4 tripwire gate; fond-htn-67 ruling |
