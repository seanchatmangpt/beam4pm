# Ingest and bridge API reference

Reference for beam4pm's telemetry/evidence ingestion surface: the
script-defined `BeamPM.Ingest.Bridge` and `BeamPM.Evidence.Ex4pmBridge`
modules, the GENERATED types they build, and the GENERATED discovery
function they feed. All signatures verified against the cited files.

Provenance note: `BeamPM.Ingest.Bridge` is defined in
`scripts/ingest_telemetry.exs`, `BeamPM.Evidence.Ex4pmBridge` in
`scripts/ex4pm_bridge.exs` — hand-authored orchestration over generated
capital, loaded at runtime via `Code.require_file/1`. Neither module lives
in `lib/`: both are script-local definitions, so they are not part of the
compiled `:beam4pm` application and are only available when the defining
script is loaded. The types and
discovery functions are GENERATED (`lib/beam4pm_types.ex`,
`lib/beam4pm_discovery.ex`); never hand-edit them.

## BeamPM.Ingest.Bridge

(`scripts/ingest_telemetry.exs`)

### attach/2

```elixir
attach(event_name, mapper \\ &__MODULE__.default_mapper/2) :: :ok | {:error, :already_exists}
  when event_name: [atom()], mapper: (map(), map() -> map())
```

Attaches a `:telemetry` handler for one event name. `mapper` receives the
real `(measurements, metadata)` maps and must return a map with the four
keys `:event_id`, `:event_type`, `:event_time`, `:attributes` — exactly
what `BeamPM.Types.OcelEvent.new/1` requires. `{:error, :already_exists}`
when the same handler id is already attached.

### attach_many/2

```elixir
attach_many(event_names, mapper \\ &__MODULE__.default_mapper/2) :: :ok | {:error, :already_exists}
  when event_names: [[atom()]]
```

One `:telemetry.attach_many/4` call over many event names — used by
`BeamPM.Evidence.attach_all/0` (`lib/beam4pm_evidence.ex`) to wire the full
`[:beam4pm, :engine, engine, op]` family (79 admitted ops) without 79
separate `attach/2` calls.

### detach/1

```elixir
detach(event_name) :: :ok | {:error, :not_found}
```

Detaches the handler for `event_name`.

### ingest/1

```elixir
ingest(%BeamPM.Types.OcelEvent{} = event) :: :ok
ingest(other) :: {:error, {:invalid_ocel_event, other}}
```

Appends one constructed event to the bounded buffer, O(1) (ets insert +
cap trim; oldest dropped over cap). Malformed input returns a typed error
instead of raising. Cap: `Application.get_env(:beam4pm, :ingest_buffer_cap,
50_000)` (50,000 default), oldest-drop. The monotonic sequence is an
atomic `:ets.update_counter/4` counter row — safe under concurrent
ingest.

### events/0

```elixir
events() :: [BeamPM.Types.OcelEvent.t()]
```

Every buffered event, oldest first (at most the newest `cap` entries).

### traces/1

```elixir
traces(case_attr_key) :: [BeamPM.Types.LogTrace.t()] when case_attr_key: String.t()
```

Feeds `events/0` through the GENERATED
`BeamPM.Discovery.traces_from_events/2`, grouping by the `attributes` key
that names the case (e.g. `"trace_id"`).

### reset/0

```elixir
reset() :: :ok
```

Clears the buffer (used between independent runs/tests).

### default_mapper/2

```elixir
default_mapper(measurements, metadata) :: %{
  event_id: String.t(), event_type: String.t(),
  event_time: String.t(), attributes: map()
}
```

OTel/Ash-shaped mapper. Reads `metadata[:resource]`,
`metadata[:action]`/`metadata[:query]`, `metadata[:trace_id]`,
`metadata[:span_id]`:

- `event_id` = `"trace_id:span_id"` (both binary), `trace_id` alone, else a
  unique generated id.
- `event_type` = `"{resource}.{action}"` when both atoms, the action alone,
  else `"telemetry_event"`.
- `event_time` = ISO8601 from `measurements[:system_time_native]`, else
  current UTC time.
- `attributes` = stringified `trace_id`/`span_id`/`resource`/`action`/`query`
  plus `"duration_native"` when present.

Unexpected payload shapes never crash: a degraded-provenance OCEL event is
emitted, never silently dropped.

## BeamPM.Evidence.Ex4pmBridge

(`scripts/ex4pm_bridge.exs`)

### broadcaster/1

```elixir
broadcaster(payload) :: payload when payload: map()
```

The 1-arity ash_ex4pm `:broadcaster` callback. Payload contract:
`%{envelope: term(), log: %Ex4pm.EventLog{}, event_count: non_neg_integer()}`.
Maps each `%Ex4pm.Event{}` in `log.events` to an `%OcelEvent{}` (via the
GENERATED `BeamPM.Types.OcelEvent.new/1`) and ingests individually.
Emits `[:beam4pm, :ex4pm, :envelope, :ingested]` (measurements
`%{event_count: n}`, metadata `%{subject_hash:, event_ids:}`) on success.
Returns the payload unchanged.

Per-event attribute mapping (`ingest_one/2`): `"object_ids"` from the
event's `object_ids`; `"object_relationships"` from `log.object_relationships`
filtered to relationships whose `source_id` is among the event's
`object_ids` (each as `%{"source_id", "target_id", "qualifier"}`); the
event's own attributes stringified (non-binary values via `inspect/1`).
`event_time` is the ISO8601 of the timestamp. A refused event is logged and
surfaced as `[:beam4pm, :ex4pm, :envelope, :refused]` (measurements
`%{event_count: 1}`, metadata `%{subject_hash:, event_id:, reason:}`);
it never breaks the broadcast.

### ensure_loaded/0

```elixir
ensure_loaded() :: :ok
```

`Code.require_file/1`s this script if the module is not already loaded
(idempotent per VM run), then calls
`BeamPM.Evidence.ensure_ingest_bridge_loaded/0` so
`BeamPM.Ingest.Bridge` exists downstream. No `*_SKIP_DEMO` guard needed —
the script's demo block self-suppresses whenever the `:telemetry` handler
table process is absent (e.g. `mix run --no-start`).

### attach/0

```elixir
attach() :: previous :: term()
```

Puts `broadcaster/1` as ash_ex4pm's `:broadcaster` application env and
returns the PREVIOUS value (including `nil` when unset), so a caller can
restore it.

## GENERATED types (do not hand-edit)

`lib/beam4pm_types.ex` — GENERATED by ggen. Both types use the standard
generated constructor shape: `new/1` requires field presence and returns
`{:ok, t()}` or `{:error, {:missing_field, atom()}}`.

### BeamPM.Types.OcelEvent

Fields: `event_id`, `event_type`, `event_time`, `attributes`.
`new/1` checks presence of the first three keys (missing any yields
`{:error, {:missing_field, _}}`); `attributes` is present-unchecked in the
constructor (defaults to `nil` when the key is absent) and is typed
`map()`.

### BeamPM.Types.LogTrace

Fields: `case_id` (`String.t()`), `activity_sequence` (`[String.t()]`),
both required by `new/1`.

## GENERATED discovery functions

`lib/beam4pm_discovery.ex` — GENERATED by ggen.

### traces_from_events/2

```elixir
traces_from_events(events, case_attr_key) :: [LogTrace.t()]
```

Case id read from each event's `attributes` at the string key
`case_attr_key`; events without it (including `nil` attributes) skipped.
Within a case, ordered by `event_time` (lexicographic ISO8601), ties broken
by `event_id`. Traces sorted by `case_id`.

### dfg_from_traces/1

```elixir
dfg_from_traces(traces) :: [DfgEdge.t()]
```

Counts adjacent `(a, b)` activity pairs into frequency-annotated
directly-follows edges (fields `source_activity`, `target_activity`,
`frequency`, `edge_weight`), sorted by source then target activity.

## Telemetry events (summary)

| Event | Measurements | Metadata |
|---|---|---|
| `[:beam4pm, :ex4pm, :envelope, :ingested]` | `%{event_count: n}` | `%{subject_hash:, event_ids:}` |
| `[:beam4pm, :ex4pm, :envelope, :refused]` | `%{event_count: 1}` | `%{subject_hash:, event_id:, reason:}` |

## Configuration

| Key | Default | Meaning |
|---|---|---|
| `:beam4pm, :ingest_buffer_cap` | `50_000` | Bounded ETS buffer cap, oldest-drop |
| `:ash_ex4pm, :broadcaster` | unset | 1-arity broadcaster fun called by ash_ex4pm's notifier with `%{envelope:, log:, event_count:}` |

## Related scripts

| Script | Role |
|---|---|
| `scripts/ingest_telemetry.exs` | Defines `BeamPM.Ingest.Bridge` + demo (`mix run scripts/ingest_telemetry.exs`) |
| `scripts/ingest_telemetry_check.exs` | Chicago-style self-test (`BEAM4PM_INGEST_SKIP_DEMO=1 mix run scripts/ingest_telemetry_check.exs`, exit 0/1) |
| `scripts/ex4pm_bridge.exs` | Defines `BeamPM.Evidence.Ex4pmBridge` + demo |
| `scripts/ex4pm_soak.exs` | Soak run for the ingest path |
| `bench/ex4pm_bridge_bench.exs` | Realtime capture-path benchmark (`MIX_BUILD_ROOT=_build-soak4 MIX_ENV=test mix run --no-start bench/ex4pm_bridge_bench.exs`) |

See Also: `docs/diataxis/explanation/why-the-ingest-bridges-live-in-scripts.md`
