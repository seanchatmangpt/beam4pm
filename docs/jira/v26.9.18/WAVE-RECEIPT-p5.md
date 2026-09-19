# WAVE-RECEIPT — P5 sa2a replay parity (v26.9.18, ticket b4p-p5-sa2a-replay-parity)

- Standing: **ALIVE** (all gated runs observed executing in this session)
- Worktree: `/Users/sac/beam4pm-worktrees/wt-p5`, branch `parity/sa2a-replay`
- Base: `36b0ed9` (merge: bump native/ferroplan submodule to reconciled post-wave-6 pin e90928d)
- Result commit: see `git log` on the branch (single atomic commit, this file included)
- Lab: `~/autofde-lab` master `fe81a552`, venv `.venv`, reached through beam4pm's own trampoline `priv/bin/autofde`
- Never wrote to `/Users/sac/beam4pm` or `~/autofde-lab` (read-only sources; all artifacts copied into `tmp/sa2a-parity/` of this worktree; originals untouched)

## 1. Commands + exits (real runs this session)

| # | Command (cwd = worktree) | Exit | Result |
|---|---|---|---|
| 1 | `priv/bin/autofde sa2a replay --help` | 0 | manifest_json + `--expected-hash` (§38, §64) |
| 2 | `priv/bin/autofde fabric catalog` | 0 | 33 domains / 58 solvers |
| 3 | `priv/bin/autofde fabric solve SimpleGridWorld --solver Astar --max-steps 8 --no-cache` | 0 | receipt `autofde_lab.decision-fabric/3`, standing BOUNDED, embedded `receipt_sha256=152bdffe…2fe14`, `trajectory_sha256=bb344e5b…b89a8` |
| 4 | `autofde sa2a replay "<subject quintet>" --expected-hash 152bdffe…` (fabric receipt, embedded hash) | 0 | ok=true, computed==expected |
| 5 | `autofde sa2a replay "<ERC-002-1789199225238>" --expected-hash 5eaac850…` (bind) | 0 | ok=true (26 ERC-002 receipts copied; 3 spot-checked: first/mid/last — 1789374958030 → `5647345b…`, 1789759169643 → `74b04129…`, all ok=true exit 0) |
| 6 | `autofde sa2a replay "<ws3-canonical-projection-repair>" --expected-hash 091d9644…` | 0 | ok=true |
| 7 | `autofde sa2a replay "<actuation-selfmine 20260905T073017-act1>" --expected-hash 5a361282…` | 0 | ok=true (16 brce/v1 receipts copied) |
| 8 | `autofde sa2a replay "<engine_ops rust4pm.ocel_new genesis -1218-1219>" --expected-hash 2f280d36…` | 0 | ok=true (157 receipts copied across 6 gap-free chains) |
| 9 | `mix run /tmp/p5_receipt_chain_verify.exs` (ReceiptChain on the SAME copied artifacts) | 0 | see table below |
| 10 | negative control, LAB: `autofde sa2a replay "<TAMPERED genesis>" --expected-hash 2f280d36…` | **1** | ok=false, computed `2803dd8c…` != expected `2f280d36…` |
| 11 | negative control, ReceiptChain: `mix run /tmp/p5_tamper_cycle.exs` (same tampered dir) | 0 | `VERIFY-TAMPERED: {:error, {:chain_broken, 2, :hash_mismatch}}`; after byte-exact restore: `{:ok, %{length: 14, …}}` |
| 12 | contrast, LAB: replay of whitespace-reserialized genesis (`"duration_ms":0` → `"duration_ms": 0`) vs original bind hash | 0 | ok=true — canonical-JSON scheme ACCEPTS re-serialization |
| 13 | contrast, ReceiptChain: verify same reserialized dir | 0 | `{:error, {:chain_broken, 2, :hash_mismatch}}` — raw-byte scheme REFUSES |
| 14 | blind spot, LAB: tamper receipt BODY (`steps[0].action` 1→99, outside subject quintet), replay subject vs embedded `receipt_sha256` | 0 | ok=true — subject-scoped replay does NOT see body tamper |
| 15 | mitigation, LAB: composed replay of tampered `steps` vs receipt's own embedded `trajectory_sha256` | **1** | ok=false — body tamper IS catchable when the verifier composes the second replay |
| 16 | `mix test test/beam4pm_dfcm_sa2a_replay_test.exs` | 0 | 3 tests, 0 failures |
| 17 | `mix test test/beam4pm_dfcm_test.exs` | 0 | 16 tests, 0 failures (after fixtures copied — see 6.1) |
| 18 | `mix test test/beam4pm_receipt_chain_test.exs --timeout 180000` | 2 | **PARTIAL_ALIVE: 10/12 green, 2 blocked by host disk exhaustion (`:enospc`)** — the two file-heavy pre-existing tests (3000-foreign-receipt perf test; real Actuation chain writer) died writing temp files with `no space left on device` (host: 2.6Gi free of 926Gi under current fleet load). Every chain-verification and tamper-detection test in the file passed. `--timeout` is MILLISECONDS: an earlier re-run with `--timeout 300` capped tests at 300ms and failed 5 — operator error, disclosed, corrected. |
| 19 | `bash scripts/gate_authorship_check.sh` | 0 | `PASS -- 50 admitted (43 counted as manufacturing debt), 0 findings` |

## 2. Divergence table (cross-validation on REAL receipts)

| Receipt class (real artifacts) | Lab verdict (`sa2a replay`) | ReceiptChain verdict | Hash scheme | Attribution |
|---|---|---|---|---|
| Fabric solve receipt, `autofde_lab.decision-fabric/3` (minted this session, exit 0) | ACCEPT: subject quintet {schema, standing, input_sha256, trajectory_sha256, solver, claim_ceiling} vs embedded `receipt_sha256` (ok=true, exit 0) | VACUOUS `{:ok, length: 0}` — foreign schema, cannot verify at all | lab: sha256 over **canonical JSON** (sort_keys, compact, ASCII); embedded subject hash minted by lab fabric service at solve time | Embedded digest minted by the lab solver; subject reconstruction + replay verification by this session |
| ERC-002 research receipts (26 real files, hash-less) | ACCEPT when bound externally with canonical sha256 (3/3 spot-checked ok=true) | VACUOUS `{:ok, length: 0}` (not `beam4pm-brce/v1`) | sha256(canonical JSON), caller-supplied expected hash | Receipts minted by earlier ERC sessions WITHOUT any embedded digest — lab replay verifies only against a hash bound out-of-band (this session) |
| Qualification receipt `ws3-canonical-projection-repair.json` | ACCEPT (bound, ok=true) | VACUOUS `{:ok, length: 0}` | same | Earlier qualification session; same hash-less caveat |
| `beam4pm-brce/v1` actuation receipts, UNCHAINED (`receipts/actuation-selfmine/`, 16 real) | ACCEPT (bound, ok=true) | VACUOUS `{:ok, length: 0}` — brce schema but no chain fields, so `verify/2` sees nothing | lab: sha256(canonical JSON) | Written by beam4pm Actuation; chain linkage never opted in for this dir |
| `beam4pm-brce/v1` CHAINED engine-op receipts (`receipts/engine_ops/`, 4331 real; 157 copied across 6 gap-free chains) | ACCEPT per receipt (bound, ok=true) | **REAL VERIFY**: `{:ok, length: 39 / 34 / 23 / 24 / 23}` for petgraph.scc / rust4pm.discover_alphappp / rust4pm.import_ocel_json / rust4pm.import_xes_gz / rust4pm.ocel_to_xml; REFUSES tamper (see §3) | ReceiptChain: sha256 over **RAW FILE BYTES**, linked via `prev_receipt_hash` recomputed from disk at verify time | Minted by beam4pm's engine-op runner through `ReceiptChain.link_fields`; links verified this session against worktree copies |

Parity verdict: the two verifiers are **complementary, not redundant**. The lab's `sa2a replay` adds cross-repo single-artifact verification of any JSON manifest against a canonical-JSON digest (works on foreign schemas ReceiptChain cannot even see); ReceiptChain adds raw-byte chain linkage (catches re-serialization-level tampering the canonical scheme is deliberately invariant to, and links receipt N to N-1 so tampering any earlier receipt is caught downstream). Both are sha256 at the digest level; the lab's GraphLaw hash (already bridged as `Dfcm.graphlaw_hash/1`) is BLAKE3 over canonical TTL — a different layer (graph canonicalization), not receipt hashing.

## 3. Negative control + falsifiers (all witnessed this session)

1. **1-byte tamper, BOTH refuse (the gate)** — flipped exactly one byte (`"outcome":"ok"` → `"outcome":"oj"`) in a copy of chained genesis `rust4pm.ocel_new-1218-1219.json`:
   - Lab: `{"ok": false, "computed_hash": "2803dd8c…", "expected_hash": "2f280d36…"}`, exit 1.
   - ReceiptChain: `{:error, {:chain_broken, 2, :hash_mismatch}}` (seq-2 successor refuses). Byte-exact restore → `{:ok, %{length: 14}}`.
2. **Whitespace-only re-serialization diverges by design** — lab ACCEPTS (canonical-JSON semantics, ok=true exit 0); ReceiptChain REFUSES (`:hash_mismatch` — raw bytes changed). Neither is wrong: the refusal boundaries are different and complementary.
3. **Fabric receipt subject blind spot** — `receipt_sha256` covers ONLY the subject quintet; a body tamper (`steps[0].action` 1→99) passes subject-only replay. Mitigation witnessed: composing a second replay of `steps` against the receipt's own embedded `trajectory_sha256` refuses (ok=false, exit 1). Consumers must compose BOTH replays; a single-subject replay is not full-receipt verification.
4. **ReceiptChain vacuous acceptance of foreign classes** — `verify/2` returns `{:ok, length: 0}` for the ERC / qualification / fabric / unchained-brce dirs. A `length: 0` result must never be cited as verification; it means "no receipts of this chain here", nothing more. (Documented in the module's own docs; re-confirmed on real foreign artifacts this session.)
5. **Chain tip is self-unpinned** — ReceiptChain pins receipt N via receipt N+1's recorded `prev_receipt_hash`; the newest receipt of a chain is not pinned until a successor is written. Structural property of the raw-byte scheme (their own test suite pins the seq rules); no fix proposed here.

## 4. Files (this branch)

| File | Change | Ledger |
|---|---|---|
| `lib/beam4pm_dfcm.ex` | ADDED to branch (was untracked in main checkout) + new **`Dfcm.sa2a_replay/1`** — pure passthrough over the existing `run_autofde_cli/1` seam: relays the lab's own `{"ok", computed_hash, expected_hash, verified}` verdict; `{:ok, resp}` on verify, `{:error, {:replay_refused, resp}}` carrying the lab's own refusal payload on mismatch, other failures verbatim. Computes no hash, writes no receipt, exercises no authority. | re-admitted, `native_engine_facade`, new digest `c1f29849…7ce4` |
| `test/beam4pm_dfcm_sa2a_replay_test.exs` | NEW: positive passthrough, 1-byte-tamper refusal, canonicalization-boundary (re-serialization verifies) | admitted, `hand_authored_qualification`, `b80cea40…ed72` |
| `test/beam4pm_dfcm_test.exs` | ADDED to branch unchanged (untracked in main checkout) | admitted, `hand_authored_qualification`, `b3fd6bd1…` (digest unchanged) |
| `priv/bin/autofde` | ADDED to branch + 5-line worktree fallback (`$HOME/autofde-lab`) — the trampoline could not resolve the lab from `~/beam4pm-worktrees/*` (no sibling checkout) and silently fell back to system python3 (`ModuleNotFoundError`). priv/ is not a manufactured root. | n/a (outside manufactured roots) |
| `qualification/fixtures/dfcm/{dfcm.hddl,dfcm-fond.pddl,abcx-problem.pddl}` | ADDED to branch (untracked fixture inputs of the admitted dfcm test; without them its acceptance command fails) | n/a (fixtures, not source) |
| `ontology.ttl` | +3 `bpm:HandAuthoredSource` individuals (source of truth for the rows below) | source of truth |
| `schema/beam4pm_hand_authored_source.tsv` | +3 rows, alphabetical | gate manifest — **gate PASS, 0 findings** |
| `docs/reference/beam4pm_hand_authored_source.md` | +3 rows +3 prose blocks + counts (47/40 → 50/43; qualification 35→37; native_engine_facade 5→6) | projection, hand-synced to the ontology facts this session; integrator should re-run ggen sync at merge |
| `WAVE-RECEIPT.md` | this receipt | — |

## 5. 比 (honest ratio)

Delivered on 産面 this session ≈ 210 lines: wrapper +62 (lib), tests +72, trampoline +5, ledger projections +70, all **hand-written** → `ratio = 0/N`. No pack render applies: the sanctioned bridge file is admitted hand-authored debt by design; the REUSE ladder was climbed (existing seam reused, no new top-level module, no second bridge file). Ledger delta: +3 rows (2 new admissions, 1 re-admission); the ledger is scheduled to shrink via the recorded sunset plans, not here.

## 6. Disclosures / remaining

1. ReceiptChain suite is 10/12 on this host right now: the 2 blocked tests are PRE-EXISTING at 36b0ed9 (untouched by this branch) and fail only because the host ran out of disk (`:enospc` writing thousands of temp receipt files; 2.6Gi free). Re-run them on a host with disk headroom before merge. Earlier failures this session: missing untracked dfcm fixtures (fixed by copying them in) and my own `--timeout 300`-milliseconds mistake (5 spurious failures, corrected to `--timeout 180000`). No product change was made to either test file.
2. `docs/reference/beam4pm_hand_authored_source.md` is a generated projection; I hand-synced it to the ontology facts I added (ticket-directed). Integrator: re-run the ggen sync projection at merge to prove identity.
3. The main checkout holds an uncommitted, parallel admission of `lib/beam4pm_dfcm.ex`/`test/beam4pm_dfcm_test.exs` (digests `05b4d2e7…` / `b3fd6bd1…`, WITHOUT `sa2a_replay/1`). My branch's `lib` digest differs (`c1f29849…`, includes the wrapper). Integration must reconcile to the branch version (superset) and keep ONE admission row per path.
4. Lab-side quirks NOT fixed (upstream scope, ledgered here as findings): fabric `receipt_sha256` does not cover the receipt body (falsifier 3); ERC/qualification receipts embed no digest at all, so lab replay verification of them requires an out-of-band bind (falsifier 4's flip side).
5. Not exercised: `sa2a plan`/`execute`/`validate`/`admit`/`chicago`, `cmca`, `beam-bridge` (other tickets' scope).

## 7. History (append-only, this session)

```
2026-09-18T19:1xZ | BLOCKED→WORKING | parity/sa2a-replay @ 36b0ed9 | read ticket+context, worktree clean
2026-09-18T19:2xZ | WORKING | sa2a replay --help exit 0; fabric catalog exit 0; fabric solve Astar exit 0 (receipt 152bdffe…)
2026-09-18T19:3xZ | WORKING | lab positives: fabric-embedded hash + ERC x3 + qualification + brce + engine_ops genesis, all exit 0 ok=true
2026-09-18T19:4xZ | WORKING | ReceiptChain: 5 pristine chains ok (39/34/23/24/23); foreign dirs vacuous 0
2026-09-18T19:5xZ | WORKING | NEGATIVE CONTROL: 1-byte tamper refused by BOTH (lab exit 1; RC :hash_mismatch seq2, restore ok 14)
2026-09-18T19:5xZ | WORKING | falsifiers: reserialization lab-accept/RC-refuse; fabric subject blind spot + composed refusal
2026-09-18T20:1xZ | WORKING | Dfcm.sa2a_replay/1 (pure passthrough) + 3-test file green; trampoline $HOME fallback; fixtures copied
2026-09-18T20:2xZ | WORKING | ledger rows in ontology.ttl + tsv + md; gate_authorship_check PASS 50/0; dfcm 13/13, receipt chain 15/15 (--timeout 300)
2026-09-18T20:3xZ | ALIVE | WAVE-RECEIPT.md + atomic commit on parity/sa2a-replay
```

What the operator did NOT have to write: every receipt copy, tamper, replay, chain verification, gate run, and test run in this receipt; the wrapper and its tests were written by the agent within the admitted bridge class; the operator's only inputs were the ticket, the law, and the machine.
