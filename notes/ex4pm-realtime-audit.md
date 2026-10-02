# ex4pm realtime integration — adversarial audit (Lane L5)

Repos: ~/beam4pm, ~/ash_ex4pm, ~/ex4pm (read-only). All repros run with
`MIX_BUILD_ROOT=_build-lane5`, `mix run --no-start`, real processes/ETS,
no mocks. Date 2026-10-01.

## Findings

### BLOCKER 1 — unbounded :persistent_term buffer; VM crash demonstrated

`BeamPM.Ingest.Bridge.ingest/1` (scripts/ingest_telemetry.exs:113-118)
prepends to a `:persistent_term` list that is rebuilt on every ingest.
No cap, no flush, no backpressure. With the realtime ex4pm path now
feeding it forever (plus `attach_all/0` at boot for 79 engine ops), a
long-running node grows it without bound.

Real run: ingesting 20,000 OcelEvents crashed the whole VM:

```
malformed_ingest: {:raised, FunctionClauseError, ...}
literal_alloc: Cannot allocate 792424 bytes of memory (of type "literal").
Crash dump is being written to: erl_crash.dump...done
```

Even bounded at 2k events: 794 ms total, ~397 us per ingest (O(n) copy
per write; cost grows linearly). Every `events/0` is also O(n) reverse.

Fix direction: bounded ring buffer or periodic flush to
`BeamPM.OcelAccumulator` (which is a real GenServer+ETS and already
exists), not an ever-growing global literal.

### MAJOR 2 — broadcast dedup depends on Ex4pm.Evidence.Store being up

ex4pm's broadcaster fires only on fresh ingest; "fresh" is decided by
`find_duplicate/2` against `Ex4pm.Evidence.Store`. If the `:ex4pm`
application is not started (e.g. `mix run --no-start`, gate scripts),
`resolve_pid(Store)` is nil, dedup is skipped, and the broadcaster
fires on every call: the same envelope lands twice in the bridge
buffer.

Real output (~/beam4pm, store not started, same envelope twice):

```
== A: store NOT running ==
whereis Store: nil
ingest1_fresh: :ingested
ingest2_same_envelope: :ingested
bridge events after 2 identical ingests: 2
```

With the store started, second ingest returns `:duplicate_ignored` and
the buffer delta is 0 (verified). Deployment risk: anything that runs
without starting `:ex4pm` silently double-counts.

### MAJOR 3 — L3 test files fail the authorship gate

`bash scripts/gate_authorship_check.sh` (MIX_BUILD_ROOT=_build-lane5)
currently FAILs with 53 findings; among them this wave's L3 files:

```
REFUSED_UNADMITTED: test/beam4pm_ash_ex4pm_emission_test.exs
REFUSED_UNADMITTED: test/beam4pm_ex4pm_realtime_bridge_test.exs
REFUSED_UNADMITTED: test/beam4pm_ex4pm_runtime_test.exs
```

`scripts/ex4pm_bridge.exs` itself is NOT flagged (scripts/ placement is
correct, same exemption as scripts/ingest_telemetry.exs). The L3 files
must be admitted in `bpm:HandAuthoredSource` + manifest regen — note
`test/beam4pm_authorship_gate_test.exs` renders admitted/debt counts
(65/57), so those counts must regenerate too. The remaining ~50
findings are test/fixtures/* files (pre-existing vs this wave; not
attributed).

### MINOR 4 — raising broadcaster propagates (disclosed); store survives

`ex4pm/lib/ex4pm/stream/ingest.ex:129-137` fires the broadcaster with
no rescue. Real run: a broadcaster raising `RuntimeError` propagates
out of `ingest_envelope/2` (`{:raised, RuntimeError, "boom"}`);
`Ex4pm.Evidence.Store` survives (`whereis` pid alive, subsequent
ingest `:ingested`). L1's notifier moduledoc discloses this and says
Ash surfaces it as `Ash.Error.Unknown` — the action call fails
post-commit. `BeamPM.Evidence.Ex4pmBridge.broadcaster/1` raises only
on L1 contract violation (pattern `%{log: %Ex4pm.EventLog{}}`);
per-event ingest failures inside the bridge are caught, logged, and
surfaced on `[:beam4pm, :ex4pm, :envelope, :refused]` telemetry.

### MINOR 5 — malformed input: FunctionClauseError, no typed refusal

`BeamPM.Ingest.Bridge.ingest/1` has a bare struct head
(`scripts/ingest_telemetry.exs:115`); a malformed map raises
FunctionClauseError (captured in the same run as Finding 1). The
Ex4pmBridge path is safe (goes through generated `OcelEvent.new/1`
with error logging), so this only bites direct callers/other mappers.

### MINOR 6 — sequence inversions are real but harmless downstream

Wall-clock `System.os_time(:nanosecond)` sequences invert under
concurrency: 8 concurrent tasks x 25 envelopes → 62/200 arrivals
carried a sequence smaller than an earlier arrival. Nothing downstream
compares sequence values (ex4pm validates >= 0 only; the bridge buffer
is arrival-ordered; Discovery groups by case attribute), so this is
informational, not a defect today.

### NOTE 7 — ash events do not reach rust4pm replay

`BeamPM.OcelAccumulator` (source of `to_engine_handle/0` rust4pm
replay) is fed solely by `BeamPM.OcelIngest.Router`. The realtime
ex4pm bridge feeds only the Bridge buffer / Discovery traces. If the
realtime gap's goal included engine replay, it is not closed by this
wave.

### NOTE 8 — app-env swap is safe

`broadcaster_opts/0` reads the env per notify; a mid-flight
`attach/0` swap routes each envelope wholly to the old or new fun; no
half-applied state; `Ex4pmBridge.attach/0` returns the previous value
for restore. Verified by reading notifier.ex:194-212.

### NOTE 9 — disjointness holds (verified, not guarded)

One engine telemetry event + one ash envelope in one VM: buffer held
exactly 2 events with disjoint id/type namespaces
(`engine_op_"audit-inv-1"`/`petgraph.graph_new` vs
`ash-evt-1`/`audit_activity`). No event landed in both paths. But
disjointness is by convention (telemetry event-name namespaces vs the
broadcaster seam); no mechanical guard exists. An Ash action emitting
[:beam4pm,:engine,...] telemetry would double-count with no gate to
notice.

### NOTE 10 — fixed ports block test runs on shared host

A 17-hour-old `mix run --no-halt` node (pid 99325) holds ports
4210/4211; `mix test` cannot boot BeamPM.Application:

```
** (EXIT) :eaddrinuse
```

L3's tests could not be executed end to end on this host during the
audit window. Coordinator-level: kill the stale node or make
`ocel_ingest_port`/`a2a_port` overridable for tests.

### NOTE 11 — ensure_loaded/0 is not self-bootstrapping

`BeamPM.Evidence.Ex4pmBridge.ensure_loaded/0` cannot be called before
the module is loaded (calling it IS the load). Callers must
`Code.require_file("scripts/ex4pm_bridge.exs")` first — hit live
during the audit (`UndefinedFunctionError ... module is not
available`). Demo blocks are correctly guarded by
BEAM4PM_EX4PM_BRIDGE_SKIP_DEMO / BEAM4PM_INGEST_SKIP_DEMO.

## Checklist answers

1. Disjointness: holds in practice (Note 9), no guard.
2. Isolation: store survives a raising broadcaster (Finding 4).
3. Backpressure: none; BLOCKER 1 + Finding 5.
4. Ordering: arrival order preserved per process; wall-clock sequence
   inversions exist but nothing consumes them (Finding 6).
5. App-env race: none (Note 8).
6. Authorship: scripts/ placement passes; L3 test files fail the gate
   (Finding 3). L3's e2e tests were port-blocked (Note 10).
