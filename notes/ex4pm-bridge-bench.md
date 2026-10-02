# ex4pm Realtime Capture-Path Benchmark (lane S4)

Bench: `bench/ex4pm_bridge_bench.exs`
Run:

```
MIX_BUILD_ROOT=_build-soak4 MIX_ENV=test mix run --no-start bench/ex4pm_bridge_bench.exs
```

Path under test:
`envelope -> Ex4pm.Stream.Ingest.ingest_envelope/2 (broadcaster opts) ->
BeamPM.Evidence.Ex4pmBridge.broadcaster/1 (EventLog -> OcelEvent mapping +
:telemetry) -> BeamPM.Ingest.Bridge.ingest/1`.

## Machine context

| item | value |
|---|---|
| chip | Apple M3 Max |
| cores | 16 |
| Elixir | 1.19.5 (OTP 28, stdlib 7.2) |
| run date | 2026-10-01 |
| build root | `_build-soak4`, MIX_ENV=test |

## Results (real output, one run, 2026-10-01)

| scenario | n | median µs | p99 µs | memory delta (ets, vs start) |
|---|---|---|---|---|
| a: ingest_envelope alone (no broadcaster, store/miner nil) | 12,000 | 8 | 33 | +0 KiB |
| b: a + no-op broadcaster fun | 12,000 | 8 | 35 | +0 KiB |
| c: full path (broadcaster = Ex4pmBridge.broadcaster/1) | 12,000 | 10 | 38 | +5.8 MiB ets (buffer at ~12.2k events) |
| map: OcelEvent.new/1 alone | 12,000 | <1 | 9 | +0 KiB |
| map: broadcaster on 1-event log (mapping+telemetry+ingest) | 12,000 | 2 | 8 | +5.8 MiB ets |
| probe: ingest_envelope vs real Ex4pm.Evidence.Store | 2,000 | 1,637 | 19,886 | +9.0 MiB ets (4,000 receipts) |
| fixed Bridge.ingest @ 1,000 buffer | 2,000 | 1 | 2 | +4.4 MiB ets |
| fixed Bridge.ingest @ 10,000 buffer | 2,000 | 1 | 5 | +8.4 MiB ets |
| fixed Bridge.ingest @ 50,000 (cap) buffer | 2,000 | 3 | 6 | +26.2 MiB ets (bounded at cap) |

## Bridge.ingest flatness (task 2)

Post-fix `BeamPM.Ingest.Bridge.ingest/1` is flat at 1k / 10k / 50k(cap):
median 1-3 µs, p99 <= 6 µs — well under the <5 µs median target at 1k/10k,
3 µs at cap (still under target; p99 6 µs). Bounded ETS ordered_set with
oldest-drop cap: ets memory grows to ~27.7 MiB at 50k buffered and stops.

## Fixed vs baseline comparison

S1's fix (bounded ETS buffer, `ingest_buffer_cap` default 50_000) landed on
this tree while this lane was starting, so no unfixed-vs-fixed A/B was run
(git-stash A/B is forbidden by lane rules; an attempt to snapshot the old
file mid-edit caught a broken hybrid and was abandoned).

Baseline = prior audit (`notes/ex4pm-realtime-audit.md`):
~397 µs/event at 2k buffered, VM crash at 20k (`literal_alloc`,
`erl_crash.dump` at repo root).

| buffer | audit baseline (unfixed) | measured fixed | improvement |
|---|---|---|---|
| 2k | ~397 µs median | ~1 µs (measured at 1k/10k; no 2k row) | ~400x |
| 10k | unmeasured (crash at 20k) | 1 µs median / 5 µs p99 | n/a (crash vs flat) |
| 50k (cap) | crash before reaching | 3 µs median / 6 µs p99 | n/a |

## Findings

1. DEFECT for lane S1 (its file, not touched by this lane):
   `scripts/ingest_telemetry.exs` `ensure_table/1` passes the bare atom
   `:read_concurrency` to `:ets.new/2`. This OTP 28 build (stdlib 7.2)
   rejects the bare-atom form with badarg (verified in plain `erl`:
   `ets:new(p, [ordered_set, named_table, public, read_concurrency])` ->
   badarg); the tuple form `{:read_concurrency, true}` is accepted.
   Consequence: `BeamPM.Ingest.Bridge.ingest/1` raises "cannot create buffer
   table" on first use on this toolchain. The bench carries a workaround
   (bench pre-creates the `:beam4pm_ingest_bridge_buffer` table with the
   tuple form so `ensure_table/1`'s `:ets.whereis/1` fast path finds it);
   S1 must change the bare atom to the tuple form in `ensure_table/1` (and
   the demo/init paths) or `Bridge` is broken standalone on OTP 28.
2. The realtime path is fast; the bottleneck moved to the evidence store:
   with the real `Ex4pm.Evidence.Store` attached (default opts), a
   1-event envelope costs ~1.6 ms median / ~20 ms p99 at only 4,000
   receipts — `Store.get_by_subject/1` is a `tab2list`+filter over the
   whole table (O(store size) per envelope, ~0.8 µs/receipt and growing).
   Realtime capture with the real Store attached will degrade linearly.
   This is upstream ex4pm 26.10.1 code, flagged for an upstream lane.
3. Mapping is cheap: OcelEvent.new/1 <1 µs; full broadcaster on a 1-event
   log 2 µs median. The bridge mapping is not a bottleneck at 1-event
   envelopes; at larger envelopes the broadcaster maps per event linearly
   (not measured at >1-event logs).

## Replay

```
MIX_BUILD_ROOT=_build-soak4 MIX_ENV=test mix run --no-start bench/ex4pm_bridge_bench.exs
```
