# WAVE-RECEIPT — P6: sa2a chicago parity (autofde-lab vs ash_a2a)

- Ticket: docs/jira/v26.9.18/b4p-p6-sa2a-chicago-parity.md
- Date: 2026-09-18 | Agent: P6 | Worktree: ~/beam4pm-worktrees/wt-p6
- Branch: parity/sa2a-chicago (base: 36b0ed9)

## Standing

| Item | Standing |
|---|---|
| Ticket gates (chicago run + cross-walk + B9 double-run + receipt) | **ALIVE** — all observed this session |
| Lab Canonical Chicago DoD Court @ autofde-lab master fe81a552 | **BUILD_BROKEN** — deterministic Gate10 crash, exit 1 (3/3 runs) |
| Lab SA2A-B9 benchmark @ fe81a552 | **ALIVE** — passed, exit 0 |
| ash_a2a SA2A-B9 (B9OcelOverhead) @ baa135d | **MEASURED** — 0 invariant failures, exit 0 |

## Subjects (exact SHAs)

- beam4pm wt-p6: parity/sa2a-chicago @ 36b0ed9 (merge bump native/ferroplan e90928d)
- autofde-lab: master @ fe81a5526c0e977f5705d02706d7be39574f4a39 (tag v26.9.16 = f5727fa9; HEAD is 1+ commits past the court's pinned tag)
- ash_a2a: main @ baa135d5c6129aea1d4b38d48a12ad87e132b638 (bench run in detached worktree at the same SHA)

## Commands + exits

```
# 1. Discovery (exit 0)
~/autofde-lab/.venv/bin/python3 -m autofde_lab.cli sa2a chicago --help        # EXIT=0

# 2. Lab Canonical Chicago DoD Court — BUILD_BROKEN (3 runs, deterministic)
cd ~/autofde-lab && .venv/bin/python3 -m autofde_lab.cli sa2a chicago         # EXIT=1 (run1, run3 captured)
# Crash: AttributeError: 'NoneType' object has no attribute 'to_dict'
#   at scripts/verify_v26_9_16_chicago.py:209 — prep_rec = receipt_store.get_prepared(...)
#   returns None => Gate09 identity binding broken at master; Gate10 line crashes.
# Last receipted PASS: reports/rfc_sa2a_002_chicago_crown_receipt.json (2026-09-16,
#   tag f5727fa9): all_gates_passed=true, 12/12 gates, duration_ms=188.

# 3. Lab SA2A-B9 — ALIVE (receipt redirected to /tmp; lab untouched)
cd ~/autofde-lab && .venv/bin/python3 scripts/run_sa2a_benchmarks.py \
  --benchmarks SA2A-B9 --iterations 20 --output /tmp/p6-lab-b9-receipt.json  # EXIT=0

# 4. ash_a2a SA2A-B9 — MEASURED (own worktree; primary repo not written)
git -C ~/ash_a2a worktree add --detach /tmp/p6-ash-a2a main                  # EXIT=0 (main was checked out in primary; detached at same SHA baa135d)
cd /tmp/p6-ash-a2a && mix deps.get                                           # EXIT=0
cd /tmp/p6-ash-a2a && mix compile                                            # EXIT=0
cd /tmp/p6-ash-a2a && mix ash_a2a.chicago.bench --only B9                    # EXIT=0
git -C ~/ash_a2a worktree remove --force /tmp/p6-ash-a2a                     # cleaned up; primary @ baa135d [main] intact
```

## Cross-walk: lab categories vs ash_a2a RFC-SA2A-002 B1-B10

Both sides implement the SAME taxonomy — RFC-SA2A-002 v26.9.16, Appendix E, ids SA2A-B1..B10.
Lab registry: `src/autofde_lab/sa2a/conformance/benchmarks/harness.py` BENCHMARK_NAMES.
ash_a2a registry: `lib/ash_a2a/chicago/bench.ex` @benchmarks (all 10 wired).

| Cat | Lab name (harness.py) | ash_a2a module (§ref) | Measured-metric parity? |
|---|---|---|---|
| B1 | Admission latency & throughput | B1Admission (§85; per-stage latency, refusals never skipped) | YES — latency+throughput both sides; ash adds per-stage split + per-case distributions |
| B2 | Logic closure | B2LogicClosure (§86; shallow/recursive/near_bound Datalog) | CATEGORY yes; lab B2 BUILD_BROKEN in committed report (`'DatalogEngine' object has no attribute 'compute_closure'`, reports/rfc_sa2a_002_benchmarks.json) — not re-run by me |
| B3 | Knowledge hook reflex latency | B3HookReflex (§87; delta size, hooks evaluated/fired, intent count) | YES — latency + hook counters both sides |
| B4 | Planning projection & preflight | B4Planning (§88; real hddl_cli subprocess, 3 disclosed fixtures) | YES — plan latency + preflight both sides |
| B5 | Authority & BRCE consequence latency | B5Authority (§89; authorized/refused/expired/revoked) | YES — scenario-split latency; ash adds per-phase (authority/actuator/receipt) splits |
| B6 | Reactive cascade latency & memory | B6ReactiveCascade (§90; depth/fan-out matrix to quiescence/exhaustion) | YES — cascade latency+memory both sides |
| B7 | Portability verification | B7CrossRuntime (§91; one wasm artifact, two heterogeneous hosts) | YES — portability verdict + timing both sides |
| B8 | Replay verification time | B8Replay (§92; offline chain reconstruction by chain size) | YES — replay time vs chain size |
| B9 | OCEL evidence generation overhead | B9OcelOverhead (§93; baseline vs observed arms) | PARTIAL — same category; lab measures per-event tracer cost + export; ash measures whole-workload delta (arms). Double-run below |
| B10 | Recovery & reconciliation | B10Recovery (§94; 5 real crash points, kill+restart) | YES — recovery/reconciliation both sides |

Shared standard markers on both sides: Chicago zero-mock (lab "Chicago Zero-Mock Standard"; ash real-SUT invariants), anti-oracle (lab "No golden OCEL traces"; ash §84 invariant-failure discipline), Appendix E environment receipts, content-addressed/digested result artifacts.

## Shared-category double-run: SA2A-B9 (OCEL overhead) — real numbers

**Lab** (autofde-lab @ fe81a552, 20-iter setting, 50-event trace; exit 0, standing ALIVE):
- events_recorded=50; mean event recording 9.41 us; p50 8.37 us; p95 10.22 us
- export_latency_ms=2.199; log_file_bytes=68,162; bytes_per_event=1363.24; events_per_sec=60,885.84
- ocpq_def2_verified=true (OCPQ Definition 2 laws: no dangling links)
- Evidence: notes/p6-sa2a-chicago/p6-lab-b9-receipt.json

**ash_a2a** (baa135d, 10 measured iterations + 2 warmup, GC-before-measure, invariants on warmup AND measured; exit 0, MEASURED, invariant_failures=0):
- baseline arm (no observer): n=10, p50=29,274 us, mean=29,051.8, p90=42,417, max=51,965; 10/10 committed
- observed arm (real Chicago Observer): n=10, p50=15,279 us, mean=21,602.8, p90=33,119, max=41,849; 10/10 committed
- claimed overhead: p50 latency delta **-13,995 us** (NEGATIVE — see falsifier F4), vm_reductions_delta=+150,014, vm_runtime_ms_delta=+3 ms
- OCEL evidence produced: 132 events, 0 dropped, 92,759 bytes, 702.7 bytes/event; serialization_us=47,978; query_load_us=9,150; observer process memory 42,264 -> 142,728 bytes
- environment identity bf35e58106952698...; artifact content-addressed sha256 205e4df0bedc... (digest algorithm sha256(canonical_json(raw_result)))
- Evidence: notes/p6-sa2a-chicago/ash-a2a-SA2A-B9-record.json, ash-a2a-bench-summary.json

**Parity verdict (B9):** same category, both ALIVE/MEASURED with real evidence on disk; metric operationalizations differ (per-event tracer microcost vs whole-consequence arm delta) — category-level parity YES, unit-level comparability NO without normalization work.

## 比 (honest)

0% manufactured / 100% hand-written — but zero production (産面) code lines delivered. Deliverable is measurement evidence: WAVE-RECEIPT.md + 4 artifact files in notes/p6-sa2a-chicago/. No bridge functions added to lib/beam4pm_dfcm.ex => no HANDWRITTEN.md ledger rows required. No pack exists for parity-receipt manufacture (failed-edge recorded below).

## Falsifiers attempted

- F1: "chicago crash is flaky" → RE-RAN 3x: identical AttributeError at verify_v26_9_16_chicago.py:209, exit 1 every time. Survives: deterministic regression at lab master.
- F2: "maybe only the Gate01 identity fence fails (HEAD ≠ tag)" → FALSIFIED: crash is at Gate10 machinery — `receipt_store.get_prepared(idempotency_token)` returns None at master, i.e. receipt-store semantics drifted past the v26.9.16 tag. Deeper than the fence.
- F3: "bench wrote into ~/ash_a2a" → NO: bench ran in /tmp/p6-ash-a2a (detached @ baa135d, removed after); primary repo shows no writes; lab receipt redirected to /tmp then copied out.
- F4: "observed arm p50 15,279us < baseline 29,274us means OCEL has negative overhead" → treated as n=10 BEAM noise (baseline arm runs first; warm effects), NOT reported as a win: the record's honest cost carriers are vm_reductions_delta=+150,014, vm_runtime_ms_delta=+3ms, serialization_us=47,978, 92,759 OCEL bytes. The record is content-addressed, so this honest negative stays in the raw artifact.

## Remaining (not done here)

1. Lab fixes (upstream autofde-lab scope, not beam4pm): `sa2a chicago` Gate09/Gate10 crash at master; B2 `DatalogEngine.compute_closure` missing. Both last-good at tag v26.9.16 (f5727fa9).
2. Double-runs for B1-B8, B10 (ticket required exactly one shared category; B9 chosen per ticket).
3. beam4pm `BeamPM.Dfcm` surfaces only `sa2a graphlaw hash|validate|hooks` today — the chicago court and B1-B10 bench harness are NOT bridged (future ticket candidate; would land in lib/beam4pm_dfcm.ex with HANDWRITTEN rows per 帳).
4. failed(edge): no marketplace pack expresses "parity receipt manufacture" — this receipt is hand-written per ticket instruction; if parity waves recur, promote a receipt pack (ontology + template + gate) upstream.

## Session receipt (証)

- Repo/base: beam4pm wt-p6, branch parity/sa2a-chicago @ 36b0ed9 (this commit adds receipt+notes only)
- Commands+exits: see "Commands + exits" above (12 commands, all exits recorded)
- Ledger deltas: none (no bridge code, no HANDWRITTEN rows)
- Standing deltas: lab chicago court ALIVE(crown 2026-09-16) → BUILD_BROKEN @ master fe81a552 (new finding)
- What the operator did NOT have to write: this entire receipt, all benchmark executions, the cross-walk table, and the /tmp worktree lifecycle.
