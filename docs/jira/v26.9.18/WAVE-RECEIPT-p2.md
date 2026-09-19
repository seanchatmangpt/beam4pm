# WAVE-RECEIPT — wt-p2 / parity/ocel-validate (b4p-p2-ocel-validate-parity)

Date: 2026-09-18. Agent: P2, v26.9.18 autofde-lab parity wave.
Ticket: docs/jira/v26.9.18/b4p-p2-ocel-validate-parity.md + _CONTEXT.md.

## Standing

**ALIVE** — every claimed verdict below was observed by real execution in this
session: 6 real `autofde ocel validate` CLI runs (stdout captured), 6 real
`rf3-ocel-oracle` subprocess runs (stdout+stderr captured), and green ExUnit
runs exercising both engines through the real seams. No fabricated evidence,
no acceptance mocks.

## SHAs

- Branch `parity/ocel-validate`, base 36b0ed9 (main @ merge of ferroplan pin bump):
  - `b09469e` feat(dfcm): BeamPM.Dfcm.ocel_validate/1 + parity qualification + baseline bridge files
  - `b985c0a` docs(admission): HandAuthoredSource lockstep ledger (ontology.ttl + TSV + md + gate render)
  - final commit: this receipt (third commit on the branch)
- Worktree: /Users/sac/beam4pm-worktrees/wt-p2 (never wrote /Users/sac/beam4pm or ~/autofde-lab)

## Commands + exits

| Command (cwd wt-p2) | Exit | Result |
| --- | --- | --- |
| `AUTOFDE_LAB_ROOT=~/autofde-lab ./priv/bin/autofde ocel validate --help` | 0 | Usage + "OCPQ Definition 2" |
| `./priv/bin/autofde ocel validate qualification/fixtures/positive-self-authored.ocel.json` | 0 | ok:true, digest 0b713099…, 2 ev / 2 obj |
| `… n05-o2o-dangling.ocel.json` | 0 | ok:false — DanglingEventObjectLink 'item-99' |
| `… n13-duplicate-object-id.ocel.json` | 0 | ok:false — DuplicateEntityId 'order-1' |
| `… n14-undeclared-event-type.ocel.json` | 0 | ok:true (lab ACCEPT — see divergence D1) |
| `… gym_bridge/{reference,deviant}_ocel_events.json` | 0 | ok:true (18/3 and 5/1 objects via capture-format fallback) |
| `echo '{"op":"ocel_stats",…}' \| native/rf3-ocel-oracle/target/release/rf3-ocel-oracle` × 6 | 0 | positive ok:true; n05 o2o 1→0; n13 dedup 2→1; n14 undeclared ["Teleport Order"]; gym ×2 `ocel_json_import_failed` |
| `mix deps.get` | 0 | |
| `cargo build --release` (native/rf3-ocel-oracle) | 0 | oracle binary produced |
| `cargo build --release --target wasm32-wasip1` (native/rust4pm-wasm) | 0 | |
| `mix compile` | 0 | 1 pre-existing warning (AshAutofde.CascadeAllocator optional dep) |
| `AUTOFDE_LAB_ROOT=~/autofde-lab mix test test/beam4pm_dfcm_ocel_validate_parity_test.exs` | 0 | **13 tests, 0 failures** |
| `AUTOFDE_LAB_ROOT=~/autofde-lab mix test test/beam4pm_dfcm_test.exs` | 0 | **16 tests, 0 failures** |
| same two files in one run | 0 | **29 tests, 0 failures** |
| `bash scripts/gate_authorship_check.sh` | 0 | **PASS — 50 admitted (43 debt), 0 findings** |
| `mix test test/beam4pm_authorship_gate_test.exs` | 0 | **19 tests, 0 failures** |

## Cross-validation table (lab `ocel validate` vs `BeamPM.RF3Ocel` run_opts verdict)

| Fixture | Lab verdict (OCPQ Def. 2) | RF3Ocel verdict (oracle + pipeline verify) | Boundary | Attribution |
| --- | --- | --- | --- | --- |
| positive-self-authored.ocel.json | accept (ok:true) | accept (`:check_positive` → {:ok}; 2/2 ev/obj, e2o 3, o2o 1) | MATCH | — |
| n05-o2o-dangling.ocel.json | refuse (DanglingEventObjectLink) | refuse (`:falsify_dangling_o2o` → {:error, {:refused,…}}; raw o2o 1 → reconstructed 0) | MATCH | both refuse, different witnesses (structural law vs raw-vs-reconstructed disclosure) |
| n13-duplicate-object-id.ocel.json | refuse (DuplicateEntityId) | refuse (`:falsify_duplicate_object` → refused; distinct ids 1 ≠ num_objects 2) | MATCH | both refuse, different witnesses |
| n14-undeclared-event-type.ocel.json | **accept** | **refuse** (`:falsify_undeclared_type` → refused; undeclared_event_types_used = ["Teleport Order"]) | **DIVERGENCE (D1)** | **Law coverage, not a defect on either side.** The lab implements OCPQ Definition 2's structural laws (one type per entity, no dangling E2O/O2O/change refs, time-stable objects/type) and reads `U_etype` as the string universe — declared-type membership is not one of its laws. RF3Ocel adds beam4pm-local declaration membership as a pipeline-level admission law over the oracle's disclosed facts. Spec version vs implementation: neither implementation misreads its own named spec; the specs differ. Pinned as a permanent tripwire in the parity test. |
| gym_bridge/reference_ocel_events.json | accept (capture-format fallback) | out of input contract (`ocel_json_import_failed`: "invalid type: map, expected a sequence") — **DIVERGENCE (D2)** | DIVERGENCE | Input schema coverage: lab's `_load_ocel_log` tolerates the raw beam4pm capture format; process_mining's OCEL 2.0 JSON importer requires the schema shape. No RF3Ocel scenario admits captures; refusal exercised for real via `:check_positive`. |
| gym_bridge/deviant_ocel_events.json | accept | same as above | DIVERGENCE (D2) | same attribution |

## Files (all absolute)

- /Users/sac/beam4pm-worktrees/wt-p2/lib/beam4pm_dfcm.ex — added `ocel_validate/1` (@spec + doctest; refusal = `{:ok, %{ok: false,…}}`, CLI failure = `{:error,_}`; atom-keyed projection)
- /Users/sac/beam4pm-worktrees/wt-p2/test/beam4pm_dfcm_ocel_validate_parity_test.exs — NEW, 13 tests (real CLI runs, boundary table, per-fixture oracle witnesses, doctest)
- /Users/sac/beam4pm-worktrees/wt-p2/ontology.ttl — 3 bpm:HandAuthoredSource facts (lib dfcm re-admission sha 927b39c2…, test dfcm b3fd6bd1…, parity test 9fa90cce…; all admittedAtCommit b09469e)
- /Users/sac/beam4pm-worktrees/wt-p2/schema/beam4pm_hand_authored_source.tsv — 3 lockstep rows
- /Users/sac/beam4pm-worktrees/wt-p2/docs/reference/beam4pm_hand_authored_source.md — 47→50 / 40→43; qualification ceiling 35→38; native_engine_facade 5→6 (at ceiling); 3 detail blocks
- /Users/sac/beam4pm-worktrees/wt-p2/test/beam4pm_authorship_gate_test.exs — render update 50/43 + 3 paths both lists
- Baseline carried onto the branch from the operator's untracked dfcm working state (session_01UiCeLuzgcK2BLocBKxXw39 lineage): /Users/sac/beam4pm-worktrees/wt-p2/priv/bin/autofde, test/beam4pm_dfcm_test.exs, qualification/fixtures/dfcm/{abcx-problem.pddl,dfcm-fond.pddl,dfcm.hddl}; config/config.exs got worktree-local `ocel_ingest_port: 4303, a2a_port: 4304` per dispatch.

## 比 (honest)

My session's delta on 産面: 0 lines manufactured from packs/generators; ~257
hand-written lines (bridge function + doctest ≈ 47; parity test ≈ 210) plus
mandated admission bookkeeping. **ratio = 0/257 — reported as 0%, not
decorated.** Lawful because the wave law (_CONTEXT.md) sanctions hand-written
bridge functions ONLY in lib/beam4pm_dfcm.ex with a HANDWRITTEN ledger row;
all three files are ledgered with sunset plans (paydown = render from
ontology facts once pack support exists). The *semantics* of
`ocel_validate/1` are manufactured by autofde-lab's real validator — the
Elixir side is a 14-logic-line delegation-only seam. Baseline lines carried
(copied, not authored here): ~512 (bridge + 16-test file) + trampoline +
3 fixture files.

## Falsifiers attempted

1. "The two engines agree on all four falsifier fixtures" — FALSIFIED by n14
   (real runs above); preserved as attributed divergence D1 + tripwire test,
   not silently pruned.
2. "The gym captures are OCEL 2.0-JSON-shaped for the oracle" — FALSIFIED
   (`ocel_json_import_failed` observed); recorded as D2.
3. "The trampoline resolves the lab from a worktree" — FALSIFIED
   (ModuleNotFoundError via system python); worktree runs need
   `AUTOFDE_LAB_ROOT=/Users/sac/autofde-lab` (the trampoline's relative
   fallback only works in a checkout adjacent to ~/autofde-lab, i.e. the
   main checkout / integration). Documented; no trampoline edit.
4. "The gate accepts the new files without admission" — falsified by design
   (REFUSED_UNADMITTED class); admission ledger written, gate now PASSes
   50/43 with 0 findings, sha-bound to disk.
5. RF3Ocel refusal-reason shape asserted as `{tag, facts}` — FALSIFIED
   (actual `{:assertion_failed, {tag, facts}}`); test corrected to the real
   contract, then green.

## History (transitions this session; ticket file itself is outside my write fence)

1. BLOCKED → setup: copied operator's untracked dfcm baseline into wt-p2
   (pattern confirmed from sibling wt-p5), ports 4303/4304, deps.get, both
   native builds green.
2. → real runs: 6 lab CLI runs + 6 oracle subprocess runs observed (tables
   above).
3. → 製: ocel_validate/1 + parity test; first run 13 tests / 4 failures
   (reason-shape falsifier #5); repair narrow; final 13/0, 16/0, 29/0.
4. → admission: ontology + TSV + md + gate render; gate PASS 50/43;
   gate tests 19/0.
5. → commits b09469e, b985c0a, receipt commit; standing ALIVE.

## Remaining (not done here, honestly)

- D1 reconciliation (lab OCPQ Def. 2 vs RF3Ocel declaration membership) is an
  upstream spec decision — candidate pack fact; both verdicts pinned by tests.
- TSV/md/gate-render were applied in lockstep by hand (the ggen renderer for
  the HandAuthoredSource manifest is not runnable in this worktree) — flagged
  for the ontology-sync pass; ontology.ttl is the source of truth.
- Worktree-local config ports (4303/4304) are wt-p2-specific; integrator may
  drop or renumber on merge.
- No push, no merge (wave law): integration via rider, one --no-ff, mix-test-gated.

## What the operator did NOT have to write

The entire bridge extension + qualification + admission set (≈257 lines +
ledger), all fixture runs, the oracle builds, and this receipt. Operator
keystrokes this session: zero.
