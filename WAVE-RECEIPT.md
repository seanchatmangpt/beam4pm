# WAVE-RECEIPT — b4p-p7 cmca allocator parity (v26.9.18)

- Agent: P7 | Worktree: /Users/sac/beam4pm-worktrees/wt-p7 | Branch: `parity/cmca-allocator`
- Standing: **ALIVE** (all gates executed and observed in this session)
- Base: main @ `36b0ed9`; base import commit `6cb47b1` (dfcm bridge lineage codex/dfcm-fond-hddl-20260912 @ `d5edfcf`, ledger-bound SHAs `2d51358`/`d8c2f19`)
- Final HEAD: see `git log` below (commit 2 of 2 on this branch)

## Commands + exits (all observed this session)

| Command | Exit | Result |
| --- | --- | --- |
| `priv/bin/autofde cmca allocate --help` | 0 | usage rendered |
| `priv/bin/autofde cmca salience --help` | 0 | usage rendered |
| `cmca salience` A (entropy 8, yield 1, cost 1) | 0 | salience 8.0 |
| `cmca salience` B (same) | 0 | salience 8.0 |
| `cmca salience` C (entropy 10) | 0 | salience 10.0 |
| `cmca allocate /tmp/p7_abc_candidates.json --plan-id dfcm_plan_benchmark` | 0 | 3 ADMITTED, Σ fractions = 1.0 |
| determinism: same allocate command run twice | 0,0 | byte-identical plans (diff clean) |
| `cmca allocate` 25-branch synthetic (`/tmp/p7_25_candidates.json`) | **1** | `BcinrCardinalityRefusal: 25 candidates exceeds the compiled N=8 allocator shape (upstream CMCA-108)` |
| `cmca allocate` 8-branch (boundary) | 0 | 8 ADMITTED, Σ = 1.0 |
| `cmca salience` on all 25 synthetic branches | 25/25 exit 0 | e.g. synth_00 0.2232, synth_12 1.1037, synth_24 0.8012 |
| `mix compile` | 0 | green |
| `mix test test/beam4pm_dfcm_test.exs test/beam4pm_dfcm_cmca_parity_test.exs` | 0 | **24 tests, 0 failures** (16 existing + 8 new) |
| `mix test test/beam4pm_authorship_gate_test.exs` | 0 | 19 tests, 0 failures |

Test env: `AUTOFDE_LAB_ROOT=/Users/sac/autofde-lab` (trampoline resolves the lab venv from it; post-merge from main checkout the default `../autofde-lab` resolution applies). Ports pinned to 4313/4314 via `config/config.exs` (`:ocel_ingest_port`/`:a2a_port`) — verified no in-tree defaults collide (defaults 4210/4211, first run hit a sibling's listener).

## Allocation-parity table — cmca vs old uniform, same benchmark budget (A/B/C)

| branch | cmca allocated_fraction | uniform fallback (old) | cmca ticks | cmca standing |
| --- | --- | --- | --- | --- |
| A | 0.318969 | 0.333333 | 3189 | ADMITTED |
| B | 0.318969 | 0.333333 | 3189 | ADMITTED |
| C | 0.362062 | 0.333333 | 3620 | ADMITTED |
| Σ | 1.000000 | 1.000000 | | |

cmca plan entropy 1.096780293274867, total_option_value_preserved 8.72412414259789. C (salience 10) strictly outsizes A=B (salience 8) under the compiled lens policy; uniform was blind to salience. 25-branch: cmca lawfully refuses (N=8), uniform would have printed 25 × 0.04.

## cmca law as documented (read of `~/autofde-lab/src/autofde_lab/cmca/{cascade,bcinr_bridge,contracts,cli}.py` + observed runs)

- **Determinism**: canonical `candidate_hash` sort + branchless Q16.16 fixed-point measure (vendored Rust `bcinr-cmca`, pinned `2ae60cf0`; wasm-first transport) → identical input = byte-identical plan.
- **Budget exactness**: active shares renormalized so Σ allocated_fraction = 1.0; Q16.16 quantum ε = 1/65536 ≈ 1.5259e-05 used as tolerance.
- **Zero-allocation law**: allocated_fraction = 0.0 ONLY when the raw measured share < pruning threshold (default 0.01); such candidates are REPORTED with standing `PRUNED` (0 ticks/memory/depth), never silently dropped. If ALL shares fall below the threshold, anti-starvation keeps exactly the top-measured candidate at full renormalized mass. No surviving candidate gets 0.0 outside this law.
- **Cardinality law**: compiled shape N = 8 (upstream CMCA-108); > 8 real candidates = typed `BcinrCardinalityRefusal`, CLI exit 1 — never truncation.

## Property results (new `test/beam4pm_dfcm_cmca_parity_test.exs`, all green)

1. Real-CLI path: benchmark allocates through cmca, allocator provenance `"cmca"`, authority_ceiling `:select`.
2. Budget-exactness: Σ fractions = 1.0 within 1/65536 for 1/2/3/5/8-branch budgets.
3. Budget mapping: plan_id/total_ticks/memory_bytes flow to the CLI.
4. Determinism: two calls → identical maps.
5. Zero-allocation law: fraction 0.0 ⇔ standing PRUNED; ADMITTED ⇒ fraction > 0.
6. Cardinality law: 25-branch → refused map, `{:cmca_allocate_failed, {:cli_failed, 1, output}}`, output carries `BcinrCardinalityRefusal`.
7. Parity: cmca C > A, C > B, A = B on the benchmark; Σ equals uniform mass 1.0.
8. Absent-CLI fallback: uniform equal shares (1/3), standing ADMITTED, `:select` ceiling.

## Files (this branch)

- `lib/beam4pm_dfcm.ex` — allocate_options/2 real cmca path (temp-file candidates transport — see falsifier F2; JSON plan mapped to branch_id/allocated_fraction/standing + ticks/memory/depth/lane; uniform fallback ONLY when CLI absent; refusals surfaced as typed refused maps). Dead `AshAutofde.CascadeAllocator` probe (never loaded) removed.
- `test/beam4pm_dfcm_cmca_parity_test.exs` — NEW, 8 property tests.
- `qualification/fixtures/dfcm/{abcx-problem.pddl,dfcm-fond.pddl,dfcm.hddl}` — fixtures required by the existing dfcm test (untracked in main; copied verbatim from the bridge lineage).
- `config/config.exs` — wave port pair 4313/4314.
- `docs/reference/beam4pm_hand_authored_source.md` + `schema/beam4pm_hand_authored_source.tsv` — ledger: base-import admissions (lib `05b4d2e7…→72e671f1…` after extension, test `b3fd6bd1…`), NEW admission `test/beam4pm_dfcm_cmca_parity_test.exs` (`24a1763a…`), counts 47/40 → 50/43, `hand_authored_qualification` ceiling 36 → 37 (dated reason recorded).
- `test/beam4pm_authorship_gate_test.exs` — gate expectations synced (50/43 + paths), per main's working-copy convention; gate re-run PASS.

## 比

Delivered 産面 lines this wave: ~170 lib + ~150 test + ledger/gate/config edits — **all hand-written in the sanctioned bridge/admission classes** (比 0% manufactured, honestly). The allocation MEASURE itself is 100% delegated to the certified lab engine: zero allocator mathematics reimplemented in BEAM. Ledger grows monotonically (+1 file) with the paydown plan stated in each sunset clause.

## Falsifiers attempted

- F1: "CLI refusal might silently degrade to uniform shares" — killed: cardinality test asserts refused shape + `BcinrCardinalityRefusal` evidence and empty allocations.
- F2: "Inline JSON argument works for cmca allocate" — FALSIFIED: macOS `OSError 63` (ENAMETOOLONG) inside the lab CLI's `Path(candidates_json).exists()` for JSON > one path component, exit 1. Bridge uses the CLI's file-path transport. **Lab defect to report upstream (not fixed here; no write authority on ~/autofde-lab).**
- F3: "Renormalized sums may drift beyond a Q16.16 quantum" — killed for 1–8 branches: max observed |Σ−1.0| ~1e-16.
- F4: "stderr loss hides typed refusals" — killed: cmca exec merges stderr so the refusal traceback travels inside the typed reason (run_autofde_cli left for the other seams unchanged).
- F5: gate re-run after ledger edits — PASS, 0 findings.

## Remaining / handoff

- Ticket History rows: NOT appended — ticket files live under /Users/sac/beam4pm (main checkout), which this agent is forbidden to write; coordinator should copy receipt lines into the ticket.
- Lab-side fixes suggested upstream: ENAMETOOLONG crash on inline JSON; consider surfacing BcinrCardinalityRefusal as `{"ok": false, "error": ...}` JSON instead of a rich traceback.
- `cmca salience` remains receipt-level evidence only (no BEAM bridge function) — not in ticket scope.
- Split of >8-branch budgets across ≤8 chunks is deliberately NOT implemented: chunking would fabricate allocation semantics the N=8 law refuses.
- Integration note: my branch commits the previously-untracked bridge files; main's working copy carries identical base content (sha-verified) plus its own uncommitted ledger deltas (incl. petgraph/tract sha updates NOT carried here — they belong to other sessions).
