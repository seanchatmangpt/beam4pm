# AUDIT.md — ferroplan pin three-way reconciliation audit (b4p-f5-05 scope 1)

PREP-only artifact. Branch `chore/ferroplan-pin-audit` (beam4pm @ `22fa4aa`).
All git plumbing; no builds, no engine runs, no submodule bump, no reconciliation
execution. Every number below is a witnessed command exit from the 2026-09-18
session, run in `/Users/sac/beam4pm-worktrees/wt-f5-pin-audit/native/ferroplan`
after both object stores were made local.

## 0. Getting both stores local (evidence, not assumption)

- `git submodule update --init native/ferroplan vendor/ggen-marketplace`
  **EXIT=128** — the ferroplan origin refuses the pin:
  `upload-pack: not our ref 4b8ff2efe086d97b68c3bf3d17c2680a7c6537ab`.
  The divergence is confirmed by the remote itself: `4b8ff2e` exists nowhere
  upstream. Worked around offline: `git fetch
  /Users/sac/beam4pm/native/ferroplan 'refs/heads/*:refs/remotes/beam4pm-main/*'`
  **EXIT=0**, then checkout of the pin **EXIT=0**. ggen-marketplace checked
  out at `7abe147` **EXIT=0**.
- `git fetch /Users/sac/ferroplan 'refs/heads/*:refs/remotes/home-main/*'`
  **EXIT=0** (78 branches, 30 tags). `d00dcf8` reachable **EXIT=0**;
  `6cacbda` reachable **EXIT=0** — the `wt-h57` worktree fetch was NOT needed.

## 1. The three lines, measured

| claim | command | result |
|---|---|---|
| merge base of ppcx line and hardened main | `git merge-base 4b8ff2e 6cacbda` | `3e1d27a` (NOT origin/main — ppcx forked one commit before origin/main's tip) |
| pin vs its origin/main | `git rev-list --left-right --count origin/main...4b8ff2e` | `1 25` — 25 ahead / 1 behind (ticket claim confirmed) |
| local main vs origin/main | `git rev-list --left-right --count origin/main...6cacbda` | `0 185` — 185 ahead, unpushed (confirmed) |
| FOUND_BUG_2 fix vs main | `git rev-list --left-right --count 6cacbda...d00dcf8` | `1 1`; `git merge-base --is-ancestor 6cacbda d00dcf8` **EXIT=1** — siblings, d00dcf8 NOT on main |
| pin vs hardened main | `git rev-list --left-right --count 4b8ff2e...6cacbda` | `13 174` |

## 2. Commit-level overlap (patch-aware)

`git log --left-only --cherry-pick --oneline 4b8ff2e...6cacbda` → 11 commits
(1 merge + 12 non-merge; `git cherry 6cacbda 4b8ff2e` → **10 `+` / 2 `-`**).

### Unique-LEFT: the 10 genuinely unique ppcx commits

| commit | subject | files |
|---|---|---|
| `703d502` | feat(errc): add canonical seven-step SOLVE(x) HDDL grammar | `domains/solve_x.hddl` (A) |
| `0e28a38` | test(errc): add executable SOLVE(x) HDDL problem fixture | `domains/solve_x.problem.hddl` (A) |
| `e98da74` | feat(errc): compile generic operators into universal planning model | `crates/ferroplan/src/operator_compiler.rs` (A) |
| `3304d92` | feat(errc): export generic operator compiler | `crates/ferroplan/src/lib.rs` (M) |
| `caf625d` | style(errc): rustfmt operator compiler | `crates/ferroplan/src/operator_compiler.rs` (M) |
| `91e7d90` | style(errc): terminate public module with rustfmt newline | `crates/ferroplan/src/lib.rs` (M) |
| `5cb0f95` | feat(fond): add independent strong policy validator | `crates/ferroplan/src/policy_validation.rs` (A) |
| `84b0114` | feat(fond): export policy validation evidence surface | `crates/ferroplan/src/lib.rs` (M) |
| `42dce51` | fix(wasm): close HDDL timeout and worker-panic error mapping | `crates/ferroplan-wasm/src/wasi_abi.rs` (M) — **superseded variant, see §4** |
| `5f9fc86` | ci: manufacture exact rustfmt recovery artifact | `.github/workflows/format-recovery.yml` (A) |

### Unique-LEFT but patch-equivalent on main (2) — verified by patch-id

| ppcx commit | main-side counterpart | patch-id match |
|---|---|---|
| `d493c19` fix(wasm): cover HddlError::Timeout/WorkerPanicked in hddl_error_json | `47a898c` | YES (`ee4a915f9f8a`) |
| `29134d7` fix(wasi-abi): route hddl_solve synchronously, no thread spawn under wasm32-wasip1 | `658ea7b` | YES (`5a80b002640f`) |

These are exactly the overlaps ticket scope 1 hypothesized ("main's own
wasm-ABI commits may already overlap"). They merge as no-ops; nothing to carry.

### Unique-RIGHT (174)

Hardened main's 174 commits not on the ppcx line: the entire FOND-HTN line
(waves 1–6: `ferroplan-hddl` front-end, `solve_hddl`, FOND
strong/strong-cyclic policies, FOUND_BUG_1 guard `651a373`, TranslateLimits
plumbing, IPC sweeps, fuzz harnesses, memory ceilings, 40-thread wasm stress
`aae68be`, docs/changelog/book). Not itemized here — 496 files, zero intent of
being replayed; the reconcile must take main wholesale.

## 3. File-level overlap and merge-conflict forecast

Files touched since merge-base `3e1d27a`:

- ppcx line (`git diff --name-only 3e1d27a..4b8ff2e`): **7 files**
- hardened main (`3e1d27a..6cacbda`): **496 files**
- `d00dcf8` (`6cacbda..d00dcf8`): **4 files** (`planning_runtime.rs`,
  `fond_property_scaleup.rs`, `docs/FOND-HTN.md`, wave-6 ledger)

`comm -12` intersection: **exactly one file** —
`crates/ferroplan-wasm/src/wasi_abi.rs`. ppcx ∩ d00dcf8 = **∅**.

Wasm ABI surface facts (ticket named `wasi_abi.rs`, `hddl.rs`,
TranslateLimits, solver choice-rewrite):

- There is **no separate `hddl.rs` in `crates/ferroplan-wasm/src/` on either
  tip** (only `lib.rs` + `wasi_abi.rs`). `hddl.rs` lives at
  `crates/ferroplan/src/hddl.rs` on both tips and the ppcx line never touched
  it — no conflict possible there.
- TranslateLimits: ppcx side grep hits `ferroplan-hddl/src/translate.rs`,
  `ferroplan/src/hddl.rs`, `ferroplan/src/planning_runtime.rs`; main side adds
  benches/tests. None of these files are in the ppcx 7-file set — no conflict.
- Solver choice-rewrite (FOUND_BUG_2, `d00dcf8`): disjoint from ppcx by file.

Dry-run merges (plumbing only, working tree untouched):

```
git merge-tree --write-tree 6cacbda 4b8ff2e   → EXIT=1, CONFLICT in
  crates/ferroplan-wasm/src/wasi_abi.rs  (tree 1574896), 2 hunks
git merge-tree --write-tree d00dcf8 4b8ff2e   → EXIT=1, same single file
  (tree a782fb9) — post-b4p-f5-04 shape behaves identically
```

The 2 conflict hunks, extracted from the merge-tree blob:

1. **Doc-comment hunk** (module header): main documents
   `FP_HDDL_ROOT_MISMATCH`; ppcx documents `FP_HDDL_TIMEOUT` /
   `FP_HDDL_WORKER_PANIC`. Resolution: union.
2. **`hddl_error_json` arms** (semantic): main = `FP_TIMEOUT` /
   `FP_WORKER_PANICKED`; ppcx = `FP_HDDL_TIMEOUT` / `FP_HDDL_WORKER_PANIC`.
   Main's naming is the newer, ticketed, stress-tested line
   (ppcx `42dce51` 2026-09-11 vs main's `47a898c`/`658ea7b`/`172464e`/
   `aae68be` 2026-09-17). **Main wins.** beam4pm asserts neither name — its
   facades/tests reference only `FP_PARSE`, `FP_MODEL`, `FP_HDDL_TRANSLATE`,
   `FP_HDDL_GROUND`, `FP_INVALID_REQUEST` — so no beam4pm-side adaptation is
   required for this resolution. Port `42dce51`'s unit test
   (`hddl_error_timeout_and_worker_panic_are_distinguishable`) under main's
   code names if main's wasm test set (`172464e`) does not already cover it.

`lib.rs` (touched by both sides but auto-merge-clean): main declares no
`operator_compiler`/`policy_validation` modules — ppcx's additions are pure
adds (verified `git grep 'mod (operator_compiler|policy_validation)' 6cacbda`
→ no match). No semantic module collision.

## 4. Reconciliation plan (recommendation: MERGE, not rebase)

### What the repo prescribes

- `~/ferroplan/RELEASING.md` prescribes nothing about branch history
  (publish order, version bump, notes roll only).
- No `CONTRIBUTING.md` exists in `~/ferroplan`.
- The observed law that does exist: `~/ferroplan/docs/jira/v26.9.17/_RUNBOOK.md`
  — "T20 merges SHAs only — race-free", "Ticket 41 merges ONLY the 16 frozen
  wave-4 SHAs", "Integration remains the coordinator's, post-wave, serial";
  and main's actual shape: 33 of the last 50 first-parent commits are
  annotated `Merge branch '...' (sha) — description (wave-N integration k/16)`
  commits. The ppcx line itself integrated via a merge
  (`4b8ff2e merge: integrate feat/errc-planning-closure into …`).

### Recommendation

**Merge `feat/ppcx-hddl-solve-wasm-facade` (`4b8ff2e`) into post-wave-6 main
with `--no-ff`, resolve the single wasi_abi.rs conflict per §3, push to
ferroplan origin. Do not rebase.**

Why merge wins:

1. **It is the prescribed style.** Frozen-SHA serial merges by a sole writer
   are both the runbook's law and 66% of main's recent first-parent history.
   A rebase would be the novel act here.
2. **No orphaned pin, in any order.** Merging keeps `4b8ff2e` as an ancestor
   of the reconciled tip, so the instant the merge pushes, beam4pm's CURRENT
   gitlink exists upstream — the "no private engine commit" requirement is
   satisfied even if the bump (scope 3) is delayed. A rebase rewrites all 10
   uniques to new SHAs and leaves beam4pm's pin absent from origin until the
   bump lands.
3. **The conflict surface is 1 file / 2 hunks with a pre-audited resolution**
   (§3). Rebase's linearity buys nothing material; the 2 patch-equivalent
   commits enter ancestry as visible no-ops instead of being silently
   dropped by a rebase.
4. **Robust to the b4p-f5-04 dependency.** The merge works against whatever
   post-wave-6 main SHA lands (with `d00dcf8`); no rebase count to recompute.

### Concrete sequence (for the scope 2–3 executor, after b4p-f5-04 lands)

1. Preconditions: b4p-f5-04 landed — post-wave-6 `main` (incl. `d00dcf8`)
   pushed to ferroplan origin; sole-writer checkout writer-free.
2. `git push origin feat/ppcx-hddl-solve-wasm-facade` FIRST, so both merge
   parents are on origin and the reconciliation is reviewable there.
3. From `origin/main`: `git merge --no-ff feat/ppcx-hddl-solve-wasm-facade`,
   family-style subject, e.g.
   `Merge branch 'feat/ppcx-hddl-solve-wasm-facade' (4b8ff2e) — errc operator compiler, SOLVE(x) grammar, strong policy validator, wasm facade (beam4pm pin reconcile)`.
4. Resolve `crates/ferroplan-wasm/src/wasi_abi.rs`: doc hunk = union;
   code hunk = main's `FP_TIMEOUT`/`FP_WORKER_PANICKED`; port `42dce51`'s
   unit test under main's names if not already covered.
5. Eyeball `5f9fc86`'s `.github/workflows/format-recovery.yml` (pure add)
   for applicability before push.
6. Gates (ticket): `cargo fmt --all --check`;
   `cargo clippy --all-targets --all-features -- -D warnings`;
   `cargo build -p ferroplan-wasm --target wasm32-wasip1` (exit 0);
   wasm-facing tests. Then push to ferroplan origin.
7. beam4pm (scope 3): bump `native/ferroplan` gitlink to the merge commit,
   rebuild the wasm artifact, commit the pointer bump atomically with any
   beam4pm-side adaptation (none expected for error codes — §3), then
   `mix test test/beam4pm_ferroplan_test.exs
   test/beam4pm_ferroplan_facades_test.exs`.

Expected verdict movement warning (from `_CONTEXT.md` probe): HDDL fixtures
may flip verdicts on the reconciled engine (e.g. `NoPlan` under empty-task-
network semantics); facade tests must be updated to the engine's real
refusals, never weakened to pass (precedent: beam4pm `ace23e5`).
