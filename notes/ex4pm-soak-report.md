# ex4pm soak report — lane S5 (2026-10-01)

Wave: ex4pm realtime bridge lanes S1-S5, one canonical checkout ~/beam4pm,
head `fee843a2` (tree dirty: concurrent S1-S4 edits present during runs).
Host: Apple M3 Max, 16 cores, 48 GiB, Elixir 1.19.5 / OTP 28.5.0.2
(stdlib 7.2). Build root `_build-soak5`.

## Verdict

**SOAK FAILED** — the 300s monitored soak itself passed cleanly
(status OK, 1500/1500 ingested, 0 refused, flat memory), but the
invariant suite (`test/beam4pm_ex4pm_soak_correctness_test.exs`) fails
reproducibly on the current tree: concurrent ingest loses buffer rows
("buffered 1196 events for 7984 fresh ingests"). Open defect for S1/S3.

## Lane S5 soak (own run, real numbers)

Command:
`MIX_BUILD_ROOT=_build-soak5 SOAK_SECONDS=300 SOAK_RATE=50 SOAK_CONCURRENCY=8 mix run scripts/ex4pm_soak.exs`

SOAK SUMMARY line:
`SOAK SUMMARY: status=OK sent=1500 fresh=1500 dup=0 refused=0 elapsed_ms=300081 rate_actual=5.0/s peak_mem_mb=108 final_mem_mb=108 buffer_cap_fired=0 crash_dump=false`

- Note on rate: the harness fires `SOAK_RATE` envelopes per batch and the
  batch loop is serial (fire → await → sample, ~10 s per batch), so the
  realized rate is 5.0/s, not the nominal 50/s. Real numbers as measured.
- Report file: `notes/ex4pm-soak-1790886452.md`
- External 5s samples of the soak BEAM pid (RSS / CPU%), full curve in
  `/tmp/s5_samples.csv`, 10s stride below. RSS is VM process RSS (includes
  JIT/loader overhead vs :erlang.memory totals of ~108 MB).

| t_s | rss_kb | cpu% |
|---:|---:|---:|
| 193 | 389296 | 825.7 |
| 198 | 551840 | 0.2 |
| 203 | 522928 | 0.2 |
| 243 | 519600 | 0.2 |
| 293 | 520944 | 3.3 |
| 346 | 522032 | 0.3 |
| 397 | 523776 | 1.4 |
| 447 | 542816 | 2.7 |
| 492 | 531120 | 0.2 |

Throughput curve: flat 50 sent / 50 fresh per 10s interval across all 30
intervals (see `notes/ex4pm-soak-1790886452.md` for the full table);
bridge buffer grew linearly 51 → 1501 (no cap approached at 50k default).

Memory curve (harness, 10s cadence): 102.9 MB → peak 113.8 MB → final
108 MB. Flat. No growth trend.

## Blockers hit during the wave (with repro)

### B1 (FIXED by S5): boot crash — `:read_concurrency` rejected by this OTP build

- Symptom: every `mix run scripts/ex4pm_soak.exs` (and `mix run -e`)
  died at boot: `:ets.new(:beam4pm_ingest_bridge_buffer, ...)` → badarg
  → `CaseClauseError` in `BeamPM.Ingest.Bridge.ensure_started/0`.
- Repro (clean VM, no app boot): `elixir -e ':ets.new(p, [:ordered_set, :named_table, :public, :read_concurrency])'`
  → ArgumentError "invalid options". Any option list containing the bare
  atom `:read_concurrency` fails on this host's OTP 28.5.0.2; the same
  list without it succeeds.
- Fix applied by S5 (scripts/ingest_telemetry.exs):
  1. dropped `:read_concurrency` (performance hint only, no semantics);
  2. hardened `ensure_started/0`/`init/1` against concurrent-init races
     (retrying `ensure_table/1`, and `give_away` of the table to the
     winning server on `{:already_started, pid}`);
  3. stricter error surfacing (raise with reason instead of silent case
     clause miss).
- Result: boot succeeds; soak ran to completion.
- S4 independently found the same defect (notes/ex4pm-bridge-bench.md,
  finding 1) and worked around it in its bench.

### B2 (OPEN, S1/S3 files): concurrent ingest loses buffer rows

- `MIX_BUILD_ROOT=_build-soak5 MIX_ENV=test mix test test/beam4pm_ex4pm_soak_correctness_test.exs`
  → 4 tests, 2 failures, reproduced twice (13:33 and 13:36).
- Failure 1 (dedup): `assert length(buffer_before) == 12` — left 5,
  right 12.
- Failure 2 (8-way soak): `buffered 1196 events for 7984 fresh ingests`
  (first run: 1182/7744).
- Mechanism (hypothesis, unfalsified): the seq counter was moved to
  `:persistent_term` (read-modify-write, not atomic) during the wave;
  concurrent ingest processes collide on the same seq and the losing
  `:ets.insert` overwrites the winner's row. Sequential batches (the
  passing soak) never collide; 8-way concurrent does. Falsifier: run the
  suite with an atomic counter (`:ets.update_counter` under the bridge
  server, or a single writer) — if the failures vanish, mechanism
  confirmed.
- Row-count confound: `erlang` buffer row-count semantics changed
  mid-wave (bookkeeping row vs persistent_term seq); the tests may also
  be asserting on stale row-count semantics — S3 arbitration needed.

### Crash dump record

- Pre-existing dump: `erl_crash.dump` sha256 `2295dce7e13375c0…`
  (16.4 MB, mtime 12:43, before the wave).
- New dump written 13:21 by the B1 failed boots (runs 1-4): sha256
  `fee97b086e256aee…` (1.9 MB). The successful soak (13:23-13:28) wrote
  no dump; `crash_dump=false` in its own report.

## Collected lane artifacts

- S2 (`notes/ex4pm-soak-1790886228.md`): 5s smoke config
  (SOAK_SECONDS=5, rate 20/s), 20/20 fresh, 0 refused, peak 97 MB,
  cap firings 0, no crash dump. S2's 300s run had not landed in
  notes/ at compile time (13:29).
- S4 (`notes/ex4pm-bridge-bench.md`): bridge.ingest flat at 1 µs median
  / 5 µs p99 (1k-10k buffered), 3 µs / 6 µs at the 50k cap vs audit
  baseline ~397 µs median and VM crash at 20k buffered. Also flagged
  the same `:read_concurrency` defect as B1.
- S3: no results artifact found in notes/ or /tmp at compile time;
  S5 ran the suite itself (results under B2). S3's own verdict
  outstanding.

## Authorship gate

`bash scripts/gate_authorship_check.sh` → **FAIL, 55 findings** (48
lines of `REFUSED_UNADMITTED` across test/ and test/fixtures/**, plus
other finding classes). All on files no lane touched this session —
pre-existing backlog, not wave-introduced. Gate never referenced
scripts/ or notes/ this session.

## Environment / replay

- Ports 4210/4211 free at session start; no orphans to kill. Two beam VMs
  observed (a mix compile + an unrelated phx.server); neither held the
  ports nor was killed.
- Replay commands:
  - soak: `MIX_BUILD_ROOT=_build-soak5 SOAK_SECONDS=300 SOAK_RATE=50 SOAK_CONCURRENCY=8 mix run scripts/ex4pm_soak.exs`
  - correctness: `MIX_BUILD_ROOT=_build-soak5 MIX_ENV=test mix test test/beam4pm_ex4pm_soak_correctness_test.exs` (run twice, see B2)
  - gate: `bash scripts/gate_authorship_check.sh`
