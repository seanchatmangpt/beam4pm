# 18. Dogfood Self-Mine Loop: beam4pm Mines Its Own Manufacturing Process

Updated 2026-08-29. Standing: **ALIVE** (whole loop executed for real, end to end, in a scratch
consumer mirroring beam4pm; exit 0 with all assertions passing, and both falsifier paths exit 1).

The product mines its factory: real OCEL telemetry from a real `mix ggen_igniter.sync`
manufacturing run of beam4pm's own Ash recipe is converted into beam4pm `ocel_event` wire maps
and fed through the real generated `BeamPM.Discovery` -- so the process-mining library's first
production event log is the log of the run that manufactures the library itself.

## 1. The loop

`scripts/dogfood_selfmine.exs`, run from the beam4pm repo root:

```bash
mix run scripts/dogfood_selfmine.exs
```

One BEAM, five stages, all real:

1. Attach a real `:telemetry` handler on
   `GgenIgniter.Telemetry.OcelEmitter.telemetry_event()` == `[:ggen_igniter, :reconcile, :ocel]`
   (the emitter fires `:telemetry.execute/3` on every OCEL event it builds, whether or not a
   sink is listening -- `ggen_igniter` 26.8.30, `lib/ggen_igniter/telemetry/ocel_emitter.ex`).
2. Run the pack's real Ash recipe in-process via `Mix.Task.run/2`: `mix ggen_igniter.sync
   --ontology ontology.ttl --query records/fields --template
   vendor/ggen-marketplace/packs/beam4pm-process-model-pack/igniter/templates/beam4pm_ash.ex.eex
   --out lib/beam4pm_ash.ex` -- exactly `scripts/igniter_sync.sh` step 1.
   Since AR-9 (26.8.30) the sync ALWAYS attempts the Reactor pipeline
   (`GgenIgniter.Reactors.ReconcileReactor.run/1`) first; no `use_reactor` config is needed and
   the flag is no longer read by the sync task. The notice line confirms the route:
   `... (via reactor)`. The pipeline's `:verify` step really runs
   `mix compile --warnings-as-errors` against the repo as a subprocess.
3. Convert each captured emitter event into a `BeamPM.Types.OcelEvent` through the real
   validating `new/1` constructor: `event_id <- "id"`, `event_type <- "activity"`,
   `event_time <- "time"`, `attributes <- attributes + "manufacturing_run" case key`.
4. Mine with the real generated `BeamPM.Discovery.traces_from_events/2` (case key
   `"manufacturing_run"`) and `dfg_from_traces/1`; print the mined DFG (plus a
   `MINED_DFG_JSON:` line in the fixed oracle wire shape, edges sorted by source then target).
5. Hard-assert the mined process (section 4) and cross-check the durable
   `GgenIgniter.Receipt` the same run appended under `.ggen_igniter/receipts/`.
   Any failure prints `FAIL:` lines to stderr and exits 1.

## 2. What the emitter really emits (captured, not assumed)

Captured live 2026-08-29 (ggen_igniter 26.8.30, Elixir 1.19.5/OTP 28, oxigraph engine, 2
queries, 123 rows) from one real sync of the Ash template: exactly **10** events, one JSON-able
map each with keys `"id"`, `"activity"`, `"time"`, `"objects"`, `"attributes"`. Three of the ten
verbatim (only the scratch-consumer absolute path is long; nothing else truncated):

```json
{"activity": "RECONCILIATION_STARTED", "attributes": {"manifest_dir": "<consumer repo root>"},
 "id": "ev_98f28a06d69a5165", "objects": [], "time": "2026-08-30T05:02:37.378935Z"}
{"activity": "FILES_CHANGED", "attributes": {"paths": ["lib/beam4pm_ash.ex"]},
 "id": "ev_6beb4adb19e597ca",
 "objects": [{"id": "lib/beam4pm_ash.ex", "type": "file"}],
 "time": "2026-08-30T05:02:37.922059Z"}
{"activity": "STANDING_SET", "attributes": {"manifest_promotion": ":promoted",
 "prune_outcome": ":not_applicable", "standing": "alive"},
 "id": "ev_83119f394fccbbe3", "objects": [], "time": "2026-08-30T05:02:38.476008Z"}
```

The full captured alive-path activity sequence, in strictly increasing microsecond-resolution
`event_time` order (every adjacent gap >= 12 microseconds in both real runs):

```text
RECONCILIATION_STARTED -> PLAN_CONSTRUCTED -> ADMISSION_ACCEPTED -> ACTUATION_STARTED
  -> FILES_CHANGED -> VERIFICATION_SUCCEEDED -> ADMITTED -> EVIDENCE_FINALIZED
  -> RECONCILIATION_ALIVE -> STANDING_SET
```

Not observed (failure/compensation path only, per `reconcile_reactor.ex` source):
`GUARD_REFUSED`, `VERIFICATION_FAILED`, `COMPENSATION_STARTED`, `FILES_RESTORED`,
`COMPENSATION_COMPLETED`, `COMPENSATION_FAILED`. The spec's illustrative
"load->query->render->write" event names do not exist in this emitter; the assertions below are
grounded in the ten activities actually captured, not invented types.

## 3. Correlation (case) attribute: stamped at the capture boundary

The emitter provides **no uniform per-run correlation attribute**: only
`RECONCILIATION_STARTED` carries `manifest_dir`, and no event carries a run id (the
`reconcile_run` OCEL object type exists in the emitter's API but is not attached by any
happy-path emit site). The script therefore stamps each converted event's `attributes` with
`"manufacturing_run" => "selfmine-<utc-iso8601>"` at capture time -- honest, because one
attached handler session observes exactly one sync run, so the correlation is real even though
the emitter did not serialize it. Consequence: one case, one trace, every DFG frequency is 1.

## 4. Exact assertions (all executed, all passing; exit 1 on any failure)

1. Exactly one trace mined; `case_id` equals the stamped run id.
2. `trace.activity_sequence` equals the full 10-activity alive-path sequence above, exactly.
3. The mined DFG is exactly these 9 edges, each frequency 1, sorted by source then target
   (computed in the script from the expected sequence, never hand-listed):
   `ACTUATION_STARTED->FILES_CHANGED`, `ADMISSION_ACCEPTED->ACTUATION_STARTED`,
   `ADMITTED->EVIDENCE_FINALIZED`, `EVIDENCE_FINALIZED->RECONCILIATION_ALIVE`,
   `FILES_CHANGED->VERIFICATION_SUCCEEDED`, `PLAN_CONSTRUCTED->ADMISSION_ACCEPTED`,
   `RECONCILIATION_ALIVE->STANDING_SET`, `RECONCILIATION_STARTED->PLAN_CONSTRUCTED`,
   `VERIFICATION_SUCCEEDED->ADMITTED`.
4. No failure/compensation activity appears in the trace.
5. `BeamPM.Discovery.conformance(dfg, trace).fitness == 1.0`.
6. Receipt cross-check: the last line of the newest `.ggen_igniter/receipts/*.jsonl` has
   `"standing": "alive"` and its embedded `events` activity list is a **strict prefix** of the
   telemetry-captured list -- really 9 of 10: `:finalize_evidence` snapshots the sink
   (`peek_sink/1`) before `STANDING_SET` is emitted, so the receipt structurally never contains
   the final event. A real, captured asymmetry, asserted as such.

Guards before mining: nonzero captured events (else the sync did not route via the reactor);
`event_time`s in arrival order AND free of duplicates -- a same-microsecond tie would make
`traces_from_events/2`'s `event_id` tie-break nondeterministic over the emitter's random hex
ids, so the script refuses loudly instead of asserting on top of it.

## 5. Verification runs (real executions)

- Scratch consumer (beam4pm is READ ONLY to this stream) mirroring beam4pm exactly:
  `mix.exs` with `{:ggen_igniter, "~> 26.8", only: [:dev, :test], runtime: false}` (hex
  resolved 26.8.30, same as beam4pm's own `mix.lock`) + `{:ash, "~> 3.0"}` (3.32.1),
  `elixirc_paths: ["generated/elixir/lib"]` with beam4pm's six generated modules copied in,
  beam4pm's `ontology.ttl`, and the pack's `igniter/` assets from
  `ggen-marketplace/packs/beam4pm-process-model-pack/` at the same `vendor/...` relative path.
  The oxigraph Rustler NIF was compiled for real by cargo during `mix compile`.
- `mix run scripts/dogfood_selfmine.exs` -> 10 events captured, DFG mined and printed,
  `== dogfood self-mine: ALIVE (all assertions passed) ==`, exit 0. Bonus grounding: the sync
  reported `unchanged (skipped, identical content)` -- the copied checked-in
  `lib/beam4pm_ash.ex` is byte-identical to what ontology.ttl + the pack
  template render, and `FILES_CHANGED` still fires on that skip path (real emitter behavior).
- Falsifier 1: a copy with one expected activity corrupted
  (`VERIFICATION_SUCCEEDED` -> `VERIFICATION_EXPLODED`) fails assertions 2 and 3 and exits 1.
- Falsifier 2: run from a directory without the inputs exits 1 (`BLOCKED:` message).
- Mock grep over delivered scripts: zero matches (no Mox/meck/mocks anywhere in the loop).

## 6. Honest limits

1. **Assertions are pinned to ggen_igniter 26.8.30's observed alive path.** A future version
   emitting more/fewer/renamed activities fails loudly (by design), not adaptively.
2. **The case key is capture-supplied, not emitter-supplied** (section 3). If the emitter ever
   stamps a run id into every event's attributes, the script should switch to it.
3. **OCEL `objects` refs are dropped** by the projection: beam4pm's `ocel_event` record type
   has no objects field (`event_id`/`event_type`/`event_time`/`attributes` only), so the
   file-object refs (see the `FILES_CHANGED` sample) do not survive conversion.
4. **Single-case log**: with one sync run there is one trace; the DFG is a 9-edge path graph
   with all frequencies 1. Frequencies > 1 need multiple captured runs (future work: loop N
   syncs under N distinct case ids in one session).
5. **Running it in beam4pm's root is a real manufacturing step**: it (re)writes
   `lib/beam4pm_ash.ex` (a skip when the ontology is unchanged), updates
   `.ggen_igniter/manifest.json`, and appends one receipt line -- the normal, documented
   `ggen_igniter` side effects, not extra ones. This stream verified in a scratch mirror only;
   `mix run scripts/dogfood_selfmine.exs` in beam4pm itself is UNVERIFIED-here (the repo is
   read-only to this stream), with layout parity as the transfer argument.
6. **In-process capture requires the same BEAM**: `:telemetry` events do not cross OS
   processes, so the script runs the sync via `Mix.Task.run/2`, not `System.cmd/3`. A
   subprocess variant would have to fall back to the receipt's embedded (9-event) list.
7. **Tie-break exposure is guarded, not solved**: microsecond timestamps were strictly
   increasing in both real runs (min adjacent gap 12us), but a same-microsecond tie on a
   faster machine aborts the run with a named diagnostic rather than flaking.
8. The `--engine sparql` fallback documented in `scripts/igniter_sync.sh` is untested with
   this script (oxigraph NIF built fine here); event capture is engine-independent in
   principle, standing UNVERIFIED for that path.

## See Also

- `scripts/dogfood_selfmine.exs` -- the loop itself (this doc's subject)
- `scripts/igniter_sync.sh` -- the manufacturing recipe the loop dogfoods (step 1)
- `lib/beam4pm_discovery.ex` -- the real mining functions exercised
- ggen_igniter 26.8.30 `lib/ggen_igniter/telemetry/ocel_emitter.ex` and
  `lib/ggen_igniter/reactors/reconcile_reactor.ex` -- the emitter and every emit site
