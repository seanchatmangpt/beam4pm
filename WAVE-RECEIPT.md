# WAVE-RECEIPT — v26.9.18 autofde-lab parity wave INTEGRATION (wt-integration, branch parity/integration)

Date: 2026-09-18. Integrator session. Law: ~/.zcode/AGENTS.md (DfCM). Every claim
below is an observed execution in this session on this branch. No push, no writes
to any main checkout.

## Standing

**PARTIAL_ALIVE** for the wave integration as a whole: all gates green in this
worktree (compile, authorship gate, full suite, architecture verifier — exits
below), but the tree is NOT landed (landing is the tree owner's, per wave law),
and the vendored-pack ceiling raise is a worktree-local pack commit until the
owner fast-forwards the pack (exact command below). No decorative ALIVE.

## Base + final SHAs

- Base: `36b0ed9` (main @ merge of ferroplan pin bump b4p-f5-05)
- Branch: `parity/integration` (worktree /Users/sac/beam4pm-worktrees/wt-integration)
- Final head: **`3ac0d8f`** (+ one receipt-only commit when this file lands)
- Vendored pack raise commit: `f2ae5382e` on
  `fix/hand-authored-qualification-ceiling-35-wave-26918` (in wt-integration's
  submodule gitdir; NOT reachable from the main checkout until fetched — see
  landing step 3)
- Union bridge digest: `lib/beam4pm_dfcm.ex` = sha256 `a88af2e5…5d42`, 1017 lines

## Per-branch merge table (all --no-ff, all parents verified)

| # | Branch | Agent head | Merge commit | Content |
|---|---|---|---|---|
| P1 | parity/fabric-solve | `95ab1ac` | `cc7264e` | fabric_match/2, fabric_solve/2 + typed-refusal machinery; dfcm baseline committed; dfcm-abcx.hddl fixture |
| P2 | parity/ocel-validate | `8ba9480` | `8c19add` | ocel_validate/1 + OCPQ Def. 2 parity test |
| P3 | parity/sa2a-card | `d9dba35` | `0d7369e` | sa2a_validate_card/1 + real 1194-skill card fixture; mix.lock ash_a2a 26.9.17 |
| P4 | parity/sa2a-admit | `2b12eef` | `d0c6228` | §64 admit fixtures + receipt; wrapper + test carried from wt-p4 untracked state (shas verified vs receipt: 9f15c69f / 579ab8cb) |
| P5 | parity/sa2a-replay | `9388c60` | `5261ba1` | sa2a_replay/1 + 3-test tamper/canonicalization file; trampoline $HOME fallback |
| P6 | parity/sa2a-chicago | `6130d8a` | `3ba6803` | measurement-only (notes/ + receipt); lab chicago court BUILD_BROKEN @ fe81a552 finding |
| P7 | parity/cmca-allocator | `78ae830` | `e592849` | allocate_options/2 cmca rework (dead CascadeAllocator probe REMOVED — removal wins) + 8 property tests |
| P8 | parity/beam-bridge | `3a0b029` | `846984d` | lib/beam4pm_autofde_bridge.ex GenServer port bridge + 8 real kill/recover tests |
| P10 | parity/graphlaw-triangle | `db397e9` | `c3e99e3` | graphlaw flip-ledger test + 6-file TTL corpus |
| — | receipt filing | — | `24cd950` | P1's root receipt filed to docs/jira/v26.9.18/ (all 9 receipts now live there as WAVE-RECEIPT-pN.md) |
| — | synthesis 1 | — | `86b0363` | union ledger + ceilings + real render |
| — | synthesis 2 | — | `3ac0d8f` | corpus admissions after gate findings |

## Union decision: lib/beam4pm_dfcm.ex (one file, synthesized)

Scaffold = P7's version (baseline `05b4d2e7` + allocate_options rework);
`AshAutofde.CascadeAllocator` probe: zero references (P7's removal wins per
dispatch). Every other wrapper inserted as a verbatim block from its branch;
every @spec, @doc, doctest, and @type preserved. Digest `a88af2e5…5d42`.

Function inventory (owner branch in parens):

- Baseline (P10 = byte-identical `05b4d2e7`): `authority_ceiling/0`,
  `phase_order/0`, `fond_outcomes/0`, `cycle/1`, `observe/3`, `policy/1`,
  `dominates?/2`, `benchmark/0`, private normalize/fence/observation/dominance/
  select/receipt helpers, `fond_policy/1+2`, `autofde_cli_path/0`,
  `autofde_cli_available?/0`, `run_autofde_cli/1`, `catalog/0`,
  `ocel_conformance/2`, `graphlaw_hash/1`, `graphlaw_validate/2`,
  `graphlaw_hooks/2`
- `allocate_options/2` REWORKED (P7): real `autofde cmca allocate` over a
  temp-file candidates transport; uniform fallback ONLY when the CLI is absent;
  typed refusals otherwise; + private `cmca_allocate/2`, `cmca_budget_opts/1`,
  `cmca_plan_to_shape/1`, `uniform_fallback/1`
- `ocel_validate/1` (P2), placed after `ocel_conformance/2` as on its branch
- `sa2a_validate_card/1` + private `run_sa2a_validate/1` (P3)
- `sa2a_admit/2` (P4, extracted from carried-untracked file — branch does NOT
  contain the bridge, confirmed via `git show parity/sa2a-admit --stat`)
- `sa2a_replay/1` (P5)
- `fabric_match/2`, `fabric_solve/2`, types `fabric_solve_opt/fabric_solve_opts`,
  private `fabric_cli/1`, `decode_fabric_stdout/1` (P1)
- No function was edited by two agents; union = pure composition (P7's rework of
  the baseline allocate_options is the only same-function change, and it wins).

Other shared-file decisions:

- `priv/bin/autofde`: P5's 25-line version wins (strict superset: adds
  `$HOME/autofde-lab` fallback; identical elsewhere).
- `test/beam4pm_dfcm_test.exs`, dfcm fixtures: identical blobs across all
  branches (auto-merged, zero conflict).
- `config/config.exs`: ALL agent port lines dropped (P2 4303/4304, P3 4310/4311,
  P7 4313/4314); my runs used uncommitted `ocel_ingest_port: 4321, a2a_port:
  4322` (still uncommitted, per wave law).
- `mix.lock`: P3's mix-owned ash_a2a 26.9.17 pin kept (matches main checkout's
  uncommitted working state per P3's receipt — expected landing conflict is
  therefore content-identical).
- WAVE-RECEIPT.md collisions: each branch's receipt preserved verbatim at
  `docs/jira/v26.9.18/WAVE-RECEIPT-pN.md`.

## Ledger recount table (honest, gate-mechanical)

| State | admitted | debt | qualification | native_engine_facade | other |
|---|---|---|---|---|---|
| base `36b0ed9` | 47 | 40 | 35 | 5 | 1 manufacturing_input, 6 reference_evidence |
| + 11 wave paths (synthesis 1, `86b0363`) | 58 | 51 | 44 | 7 | unchanged |
| + 6 P10 corpus fixtures after gate findings (synthesis 2, `3ac0d8f`) | **64** | **57** | **50** | **7** | unchanged |

- Dedupe: one `bpm:HandAuthoredSource` individual per path; duplicate-name
  collisions (lib_dfcm / test_dfcm rows from P2/P3/P5) resolved to single rows
  carrying final digests; P4's two rows added from its receipt-supplied text;
  P10's test row new. 64 unique individual names, verified by sort/uniq.
- Digest corrections: `lib/beam4pm_dfcm.ex` re-admitted at union digest
  `a88af2e5…5d42` (P1's 9f305132, P2's 927b39c2, P3's b35fe560, P4's 9f15c69f,
  P5's c1f29849, P7's 72e671f1 are all superseded branch-state digests).
- Ceiling raises (vendored pack `vendor/ggen-marketplace`, commit `f2ae5382e`,
  dated reasons in authorshipKindDoc): `hand_authored_qualification` 35 → 50,
  `native_engine_facade` 6 → 7. Gate 070 verdict now 50/50 and 7/7.
- NEW finding surfaced by integration: the full gate run refused P10's six
  corpus TTLs (REFUSED_UNADMITTED x6 — P10's branch-scoped run never executed
  the full gate). Admitted sha-bound rather than silently exempted.

## Projection provenance (源)

`schema/beam4pm_hand_authored_source.tsv`, `docs/reference/beam4pm_hand_authored_source.md`,
and `test/beam4pm_authorship_gate_test.exs` are GENUINE `ggen sync run` output —
observed this session, twice (once per synthesis). Two disclosed fences crossed
by the tool's own documented remediations:

1. FM-PACK-008 (pack content hash mismatch after the ceiling raise): ggen.lock
   deleted and re-locked per the error's own remediation text. Committed lock
   `36fc3a3d…` hashes the clean raised pack.
2. FM-WRITE-005 (refusing silent clobber of the agents' hand-synced renders):
   temporary `force: true` front-matter on the 3 render targets, applied and
   REVERTED around each run — the submodule is clean at `f2ae5382e` with no
   force flags committed.

## Gates (all in wt-integration; commands + exits)

| Gate | Command | Exit | Result |
|---|---|---|---|
| deps | `mix deps.get` | 0 | 96 deps |
| compile | `mix compile` | 0 | clean; only dep-side warning is `Mix.Tasks.Eds.Ledger` redefinition from the ash_a2a 26.9.17 pin (pre-existing with that pin; note P7's probe removal KILLED the old CascadeAllocator warning) |
| authorship gate | `bash scripts/gate_authorship_check.sh` | 0 | **PASS — 64 admitted (57 counted as manufacturing debt), 0 findings** |
| rendered gate test | `mix test test/beam4pm_authorship_gate_test.exs` | 0 | 19 tests, 0 failures |
| full suite | `source scripts/env/rust4pm_reactor_env.sh && AUTOFDE_LAB_ROOT=$HOME/autofde-lab mix test` | 0 | **6 doctests, 1164 tests, 0 failures, 52 skipped** (97.8s). The dispatch's expected VendorCwd flake trio did NOT fire — zero failures total, nothing to triage. Skips are the named-skip classes (absent lab legs, kubectl, prereq-gated) |
| architecture | `mix ash_a2a.verify_architecture` | 0 | 17/17 architecture checks passed |
| natives | cargo builds (see below) | 0 | rf1–rf4 host release, petgraph/tract host release, rust4pm-wasm host + wasm32-wasip1, ferroplan wasm32-wasip1 |

Native artifact proof: `native/ferroplan/target/wasm32-wasip1/release/ferroplan_wasm.wasm`
sha256 `69e9229600dd1daf61b75fb90504023a7f84757ce2bd6b338931d63bd566a4a4` —
byte-identical to P1's receipted artifact (built here with P1's exact
`cargo build --release --target wasm32-wasip1 -p ferroplan-wasm`; a whole-workspace
build fails on winit/tokio@1.53.1 wasm feature gates — use the `-p` form).

Test-minted receipt: `research/erc/ERC-002-1789794942459.json` was minted for
real during the full-suite run (EDS claim verification against tree `3ac0d8f`)
and is committed, per the repo's tracked-receipts convention (12 already tracked).

## 比 (honest)

The integration session delivered zero new product semantics: every bridge
function, test, and fixture was manufactured by the P-agents (their ratios:
P3 reported 22% manufactured via a real render, everyone else 0% — all
hand-written-in-admitted-classes, all ledgered). This session's own bytes are
reconciliation + ledger prose: merges, conflict resolutions, 17 ontology
individuals, 1 pack ceiling commit, receipts. Of the ~200 rendered projection
lines, the proven-by-render share this session is the ggen output above
(manufactured); the ontology facts feeding it are hand-authored manufacturing
input. No ratio was decorated anywhere in the wave; the ledger grew 40 → 57
debt rows and the pack ceilings were raised with dated, reviewed reasons —
the honest direction of travel for a wave whose mandate was parity evidence,
not pack manufacture.

## Remaining (owner actions, exact commands below)

1. LAND: merge parity/integration on the main checkout (untracked-file-safe
   procedure below).
2. PACK CEILING: fast-forward the vendored pack to `f2ae5382e` (or apply the
   equivalent one-hunk change to the main checkout's already-dirty submodule
   working tree) and push the pack branch per the pack's own review law. Until
   then a bare `ggen sync run` on the main checkout refuses at FM-PACK-008 —
   that refusal is the tripwire, not a defect.
3. P8's announced one-liner (insert `BeamPM.AutofdeBridge` into
   `BeamPM.Application`'s supervision tree) deliberately NOT done here:
   `lib/beam4pm_application.ex` is sha-bound by its admission row; the edit
   needs its own re-admission, not a piggyback.
4. ash_a2a 26.9.17 pin collision warning (`Mix.Tasks.Eds.Ledger` redefinition)
   is upstream-shaped: ash_a2a now ships a task that collides with beam4pm's
   own `eds.ledger` task name. Triage upstream or rename locally in a reviewed
   change.
5. Unchanged from agents' receipts: P9's lab wasm registry pin; lab-side fixes
   (chicago Gate09/10, sa2a validate A2A-v0.3 mode, graphlaw transport
   ceilings, fabric subject blind spot, cmca inline-JSON E2BIG); B1–B3 card
   fixes; P5's ReceiptChain 2 :enospc-blocked tests (green here).
6. `docs/jira/v26.9.18/` ticket files still live only as untracked files in
   the main checkout; commit them alongside the landing so the docstring
   references (e.g. sa2a_replay's) resolve.

## Landing procedure (tree owner, main checkout @ /Users/sac/beam4pm)

The main checkout carries a concurrent session's uncommitted tracked edits
(ontology.ttl, tsv, md, gate test, mix.lock, ggen.lock, ferroplan sources,
tests) plus untracked files (lib/beam4pm_dfcm.ex, priv/bin/autofde,
test/beam4pm_dfcm_test.exs, dfcm fixtures, docs/jira/v26.9.18/*, research/*).
The merge will fail on: (a) untracked files colliding with incoming paths,
(b) tracked-file local edits overlapping the merge. Spell:

```bash
cd /Users/sac/beam4pm

# 0. Snapshot the concurrent session's in-flight state WITHOUT losing it:
git stash push --include-untracked -m "pre-parity-integration in-flight (auto-stashed by landing)"
# (review with: git stash show -p 'stash@{0}' — restore afterwards with git stash pop
#  ONLY for files the integration did not supersede; the integration SUPERSEDES
#  the untracked dfcm bridge baseline, its ledger rows, and the mix.lock pin.)

# 1. Land the wave (no-ff, one merge):
git merge --no-ff parity/integration -m "merge: v26.9.18 autofde-lab parity wave integration (9 agent branches, synthesis, ledger recount 64/57)"

# 2. Vendored pack ceiling raise — the pack commit is NOT in the main checkout's
#    submodule gitdir yet; fetch it from the integration worktree:
git -C vendor/ggen-marketplace fetch /Users/sac/beam4pm-worktrees/wt-integration/vendor/ggen-marketplace fix/hand-authored-qualification-ceiling-35-wave-26918
git -C vendor/ggen-marketplace checkout fix/hand-authored-qualification-ceiling-35-wave-26918
#    (the superproject gitlink still records 7abe147 — either commit the bump
#     `git add vendor/ggen-marketplace && git commit -m "bump ggen-marketplace: hand-authored ceilings 35->50, native 6->7"`
#     or leave the gitlink and land the raise via the pack's own upstream review;
#     theformer is what parity/integration was gate-proven against).

# 3. Re-run the gates for real on the landed tree:
mix deps.get && mix compile
AUTOFDE_LAB_ROOT=$HOME/autofde-lab bash scripts/gate_authorship_check.sh
source scripts/env/rust4pm_reactor_env.sh && AUTOFDE_LAB_ROOT=$HOME/autofde-lab mix test

# 4. Restore what remains of the concurrent session (anything the wave did not
#    supersede — the v26.9.17 F5 work, engine ontology refresh, petgraph/tract
#    sha updates) from the stash as NEW reviewed work, not silently:
git stash show --name-only 'stash@{0}'
# ...cherry-pick those paths back, re-run the gate, commit separately.

# 5. Commit the wave's ticket files (still untracked):
git add docs/jira/v26.9.18 && git commit -m "docs(jira): v26.9.18 parity wave tickets + context"
```

If step 1's merge reports CONFLICT (add/add) on any path: stop — that means a
concurrent session created a file the wave also carries; diff against the
parity/integration version and keep the one the receipt digests pin (all
wave digests are in schema/beam4pm_hand_authored_source.tsv, gate-enforced).

## Session receipt (証)

- Repo/base: beam4pm @ 36b0ed9 → branch parity/integration @ 3ac0d8f (13 commits)
- Commands + exits: table above (every gate exit 0; two mid-session failures
  disclosed and repaired narrowly: P5-merge ontology resolution took --theirs
  and dropped P2/P3 rows — caught by individual-count tracing, restored at
  synthesis; whole-workspace ferroplan build failure — repaired with P1's
  `-p ferroplan-wasm` form)
- Standing deltas: wave integration ALIVE-in-worktree / PARTIAL_ALIVE overall
  (unlanded + pack raise unfetched); lab chicago court remains BUILD_BROKEN
  upstream (P6, unchanged)
- Falsifiers attempted: per-branch digest verification against all 9 receipts
  (all matched); duplicate-individual scan (0); merge-parent audit (9/9
  correct); union function inventory grep (all 6 wrappers + rework present);
  artifact sha vs P1 receipt (byte-identical)
- What the operator did NOT have to write: all of it — 9 merges, the union
  synthesis, the ledger reconciliation, both renders, every gate run, and
  this receipt.
