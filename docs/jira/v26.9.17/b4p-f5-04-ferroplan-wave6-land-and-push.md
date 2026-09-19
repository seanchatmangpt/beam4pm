---
id: b4p-f5-04-ferroplan-wave6-land-and-push
type: oslc_cm:ChangeRequest
requirement: earl:TestRequirement
dcterms:title: "ferroplan: finish + merge wave-6 (esp. FOUND_BUG_2 hotfix d00dcf8) and push the 185-commit FOND-HTN line to origin/main"
standing: BLOCKED
branch: (ferroplan) fix/sc-choice-rewrite @ d00dcf8 + remaining wave-6 branches, then main
worktree: ~/ferroplan-worktrees/wt-h57..wt-h66
created: 2026-09-17T21:40:00Z
source: ~/ferroplan docs/jira/v26.9.17/fond-htn-57..66 (live History rows observed 2026-09-17) + CHANGELOG [Unreleased]
depends: none (upstream-first)
---

Read `_CONTEXT.md` first. beam4pm's `fond_policy/4` and `hddl_solve/4`
currently run an engine whose strong-cyclic solver has **two known
property-discovered soundness bugs in its lineage**: FOUND_BUG_1's fix is on
ferroplan main (unpushed), FOUND_BUG_2's fix (`d00dcf8`, ALIVE with all
gates green in wt-h57) is **not even on main**. Until this ticket lands, no
strong-cyclic verdict produced through beam4pm is admissible as Fortune-5
evidence.

## Scope (work lives in ~/ferroplan)

1. Merge `fix/sc-choice-rewrite @ d00dcf8` (ticket 57, FOUND_BUG_2: rewrite
   strong-cyclic choices to advancing actions at fixpoint close; 5000-
   instance sweep 0 mismatches, carve-out removed) into main `--no-ff`.
2. Drive the remaining wave-6 tickets to close per their own scopes —
   58 (drop-retry re-decompose oracle mismatch), 59 (iterative drop),
   60 (grounding prune for >1M-instance groundings), 61 (differential fuzz
   VALID draws through both engines), 62 (final sweep), 65
   (TranslateLimits plumbing), 66 (minimal koala harvest) — 63 (docs) and
   64 (ledger) already ALIVE/done at observation time.
3. Cut the release the unreleased cycle has been building toward (version
   gate per RELEASING.md; CHANGELOG "Finished-hardening" block already
   drafted by 63).
4. **Push `main` to `origin/main`** — 185 unpushed commits today. A Fortune-5
   supply-chain audit cannot pin "a branch on someone's laptop."

## Gates

- ferroplan: each wave-6 ticket's own gate lines exit 0 (see each ticket);
   in particular 57's `cargo test -p ferroplan --lib planning_runtime &&
   cargo test -p ferroplan --test fond_property_scaleup` with **0 ignored**
   beyond documented load-tolerance.
- ferroplan: 62's final sweep over every target on main (incl. wasm,
   externals, bench tripwires) — report attached to this ticket.
- ferroplan: `git push origin main`; `git rev-list --count
  origin/main..main` == 0; tag exists for the release.
- beam4pm (readiness signal only; the actual bump is b4p-f5-05): note the
  pushed SHA here — it is the input to the reconciliation ticket.

## History
| ts | standing | branch+SHA | gates+exits | remaining |
|---|---|---|---|---|
| 2026-09-17T21:40:00Z | BLOCKED | — | — | all |
| 2026-09-18T16:55:00Z | ALIVE | ferroplan `main @ 4cd7f44 -> e90928d`, tag `v0.28.0`, pushed (rev-list 0) | ALL scope items closed by wave + coordinator integration. Wave-6 merged --no-ff onto land branch (2cb7b5c): 57@d00dcf8, 58@b06b907, 59@b854f70, 60-wip b03ea19, 61@f979c53+848201b, 65@6757249, 63@cd4a7a9, 64@78e220f; every ticket gate re-run exit 0; 776 passed/0 failed/47 documented ignores; 62 sweep 817 passed / 6 EXTERNAL_ABSENT (/tmp wiped) / 0 unexpected; KEY FINDING: 8 ledger verdict flips (6 SOLVED->NOSOLUTION = 57 removes false solves; 2 NOSOLUTION->SOLVED = 58 re-offer), pre-wave-6 ledger preserved. Release prep: 0.28.0 + pins + re-lock. Coordinator cut-time gates: clippy --all-targets -D warnings GREEN after mechanical lint fixes (abf234c: ?-lint, expect_err, field_reassign initializers, const assert, doc lists, unused imports; all touched targets re-run green); cargo bench --no-run green; fmt normalized. Integrated: merge --no-ff to main (17e38bb), tagged v0.28.0, pushed; union-resolved 5 ticket-doc stash conflicts (+15 rows); History-union commit 4cd7f44. REMAINING: crates.io publish (publish.sh) needs operator credentials; oracle harness rebuild for 61 re-harvest + 60's 16-domain rerun + 66 artifacts (EXTERNAL_ABSENT). | crates.io publish; EXTERNAL_ABSENT sweep items |
