# WAVE-RECEIPT — A8, ticket b4p-f5-05 (PREP: audit + reconcile plan + pin-drift filing)

- date: 2026-09-18, agent A8 of the 10-agent wave
- worktree: `/Users/sac/beam4pm-worktrees/wt-f5-pin-audit`, branch
  `chore/ferroplan-pin-audit` based on beam4pm `main @ 22fa4aa`
- main checkout: NOT written (concurrent-writer serialization respected)

## Standing

**PARTIAL_ALIVE** — for this ticket's PREP scope: the three-way overlap audit
is ALIVE (real git plumbing against both object stores made local in this
session); the reconciliation plan and the pin-drift filing are authored
artifacts (candidate, not executed). Scope 2 (actual merge + push), scope 3
(submodule bump + wasm rebuild + facade gates), and the autofde-lab re-pin
remain with their owning tickets/times.

## Commands + exits (the load-bearing ones)

| # | command (in `native/ferroplan` submodule clone unless noted) | exit |
|---|---|---|
| 1 | `git submodule update --init native/ferroplan vendor/ggen-marketplace` (worktree root) | **128** — `upload-pack: not our ref 4b8ff2e…` (the remote itself proves the pin is nowhere upstream) |
| 2 | `git fetch /Users/sac/beam4pm/native/ferroplan 'refs/heads/*:refs/remotes/beam4pm-main/*'` | 0 — pin now local |
| 3 | `git checkout 4b8ff2e` (submodule) | 0 — `native/ferroplan @ 4b8ff2e` |
| 4 | `git submodule update vendor/ggen-marketplace` | 0 — `vendor/ggen-marketplace @ 7abe147` |
| 5 | `git fetch /Users/sac/ferroplan 'refs/heads/*:refs/remotes/home-main/*'` | 0 — 78 branches, 30 tags |
| 6 | `git rev-parse --verify d00dcf8^{commit}` / `6cacbda^{commit}` | 0 / 0 — wt-h57 fetch NOT needed |
| 7 | `git merge-base 4b8ff2e 6cacbda` | `3e1d27a` |
| 8 | `git rev-list --left-right --count origin/main...4b8ff2e` | `1 25` (25 ahead/1 behind confirmed) |
| 9 | `git rev-list --left-right --count origin/main...6cacbda` | `0 185` (unpushed confirmed) |
| 10 | `git rev-list --left-right --count 6cacbda...d00dcf8`; `git merge-base --is-ancestor 6cacbda d00dcf8` | `1 1`; exit 1 (siblings, fix NOT on main) |
| 11 | `git rev-list --left-right --count 4b8ff2e...6cacbda` | `13 174` |
| 12 | `git log --left-only --cherry-pick --oneline 4b8ff2e...6cacbda` | 11 (1 merge + 10 unique + see #13) |
| 13 | `git cherry 6cacbda 4b8ff2e` / `git cherry -v …` | 10 `+` / 2 `-`; equivalents `d493c19`≡`47a898c`, `29134d7`≡`658ea7b`, patch-id match YES/YES |
| 14 | `git show --name-status` × 10 unique commits | file lists in AUDIT.md §2 |
| 15 | `git diff --name-only 3e1d27a..4b8ff2e` (7) / `3e1d27a..6cacbda` (496) / `6cacbda..d00dcf8` (4); `comm -12` | overlap = `crates/ferroplan-wasm/src/wasi_abi.rs` ONLY; ppcx∩d00dcf8 = ∅ |
| 16 | `git merge-tree --write-tree 6cacbda 4b8ff2e` / `… d00dcf8 4b8ff2e` | exit 1 both; CONFLICT only in `wasi_abi.rs`, 2 hunks (doc union + `FP_TIMEOUT`/`FP_WORKER_PANICKED` vs `FP_HDDL_TIMEOUT`/`FP_HDDL_WORKER_PANIC`) |
| 17 | beam4pm facade FP-code grep (`grep -o 'FP_[A-Z_]*'` over lib/test) | only `FP_PARSE`, `FP_MODEL`, `FP_HDDL_TRANSLATE`, `FP_HDDL_GROUND`, `FP_INVALID_REQUEST` — neither conflicted name asserted |
| 18 | autofde: `grep 282fae4 …/_registry.py`; `git rev-list --left-right --count 282fae4...6cacbda` / `origin/main...282fae4` | pin @ `src/autofde_lab/wasm/_registry.py:172`; `0/384`; `199/0` (pin ancestor of pushed origin/main) |

## Audit tables (full detail: AUDIT.md)

**Unique-LEFT (ppcx, 10):** `703d502` `0e28a38` `e98da74` `3304d92` `caf625d`
`91e7d90` (errc operator compiler + SOLVE(x) grammar/fixture),
`5cb0f95` `84b0114` (strong policy validator), `42dce51` (wasm error mapping —
SUPERSEDED variant: main's 09-17 line is newer and tested), `5f9fc86`
(format-recovery CI workflow).
**Equivalent-LEFT (2):** `d493c19`≡`47a898c`, `29134d7`≡`658ea7b`.
**Unique-RIGHT (174):** hardened main's FOND-HTN waves 1–6 (not replayed;
taken wholesale). **Overlap files (1):**
`crates/ferroplan-wasm/src/wasi_abi.rs`. No `hddl.rs` in the wasm crate on
either tip; TranslateLimits and choice-rewrite files: zero ppcx touch.

## Reconcile recommendation

**MERGE `--no-ff` of `4b8ff2e` into post-wave-6 main, push to ferroplan
origin; do NOT rebase.** Grounds: (1) the repo's own law — RELEASING.md is
silent on branch history, no CONTRIBUTING exists, but `_RUNBOOK.md`
("merges ONLY the frozen SHAs", "integration … serial, sole writer") and
main's shape (33/50 first-parent = annotated merge commits) prescribe it;
(2) merge keeps `4b8ff2e` an ancestor of origin so beam4pm's current pin is
never a private commit, in any ordering of the bump; (3) conflict surface is
1 file / 2 hunks with a pre-audited resolution (main's error-code names win;
beam4pm asserts neither name, so no beam4pm-side adaptation needed);
(4) robust to the b4p-f5-04 dependency. Concrete 7-step sequence in AUDIT.md §4.

## Files changed (this branch)

- `AUDIT.md` (new) — overlap audit + reconcile plan (ticket gate artifact)
- `PIN-DRIFT-filing.md` (new) — autofde-lab `282fae4` drift, filed not fixed
- `WAVE-RECEIPT.md` (new) — this receipt
- `docs/jira/v26.9.17/b4p-f5-05-ferroplan-pin-three-way-reconciliation.md`
  (append-only History row, worktree copy)

## 比 (ratio)

Honest: this ticket delivered **0 manufactured / ~100% hand-authored lines** —
4 markdown evidence artifacts, no product code. There is no pack render for
audit/reconciliation artifacts in the admitted set (failed-edge note: the
calver-ticket-day-pack renders ticket scaffolding, not audit artifacts; no
family express audit-diff Capability was found, so the audit itself is the
1%-ledger class of work for now). No production paths changed; no tests
weakened; no placeholders.

## What the operator did NOT have to write

All of it: the submodule/offline-pin recovery, the cross-fetches, the entire
cherry/patch-id/file-overlap/merge-tree audit, the conflict-hunk extraction,
the reconcile plan, the autofde drift measurements, and the four documents.

## Remaining (not mine; recorded, not executed)

1. **b4p-f5-05 scope 2** — execute the merge per AUDIT.md §4 on post-wave-6
   main and push to ferroplan origin. Blocked by b4p-f5-04 (post-wave-6 main
   push).
2. **b4p-f5-05 scope 3** — bump `native/ferroplan` gitlink to the reconciled
   commit; `cargo build -p ferroplan-wasm --target wasm32-wasip1`; atomic
   beam4pm commit; `mix test test/beam4pm_ferroplan_test.exs
   test/beam4pm_ferroplan_facades_test.exs` exit 0.
3. **autofde-lab re-pin** — its own ticket; handoff in PIN-DRIFT-filing.md §4.
4. Ticket gates NOT touched here (no builds, no pushes): all four gates in
   the ticket remain open; scope-1 gate satisfied by AUDIT.md (linked from
   the ticket History row) once this branch lands.
