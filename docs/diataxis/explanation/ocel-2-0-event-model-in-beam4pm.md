# The OCEL 2.0 event model as implemented (explanation)

Why beam4pm's object-centric model looks the way it does: four fields per
event, objects and relationships as first-class citizens, and a strict
split between decoding, buffering, and querying.

## The event shape: four fields

The GENERATED `%BeamPM.Types.OcelEvent{}` (`lib/beam4pm_types.ex`) carries
exactly four fields: `event_id`, `event_type`, `event_time` (ISO8601
string), and `attributes` (a map). Objects and relationships are not lost —
they ride inside `attributes`:

- `"object_ids"` — the objects the event touches
- `"object_relationships"` — O2O relationships whose `source_id` is among
  the event's `object_ids` (the exact filtering is
  `ingest_one/2` in `scripts/ex4pm_bridge.exs`)

This shape is the contract every ingest path converges on. The generated
constructor `BeamPM.Types.OcelEvent.new/1` validates field presence on
every build, which is why all bridges go through it and never hand-roll
struct literals.

## Two representation layers, one vocabulary

beam4pm keeps a plain-struct layer and an Ash layer in step:

- **Plain structs** (`BeamPM.Types.OcelEvent/OcelObject/OcelRelationship/
  OcelAttribute`, `lib/beam4pm_types.ex`) — the wire and buffer currency.
  `BeamPM.Codec.to_map/1`/`from_map/2` (generated) do the map conversion.
- **Ash resources** (`BeamPM.Ash.Resources.OcelEvent`, `OcelObject`,
  `OcelRelationship`, `OcelAttribute`, plus `EventLog`, `EventType`,
  `ObjectType` — all GENERATED under `lib/beam4pm_ash/resources/`) — the
  same records as queryable resources on the ETS data layer with the
  `AshEx4pm` extension. `OcelEvent`'s `ex4pm do` block declares
  `object_type(:ocel_event, attributes: [...])` and a `:create` activity
  (`lib/beam4pm_ash/resources/ocel_event.ex`).

One notable simplification, stated in the resource files themselves: map
fields (`attributes`) have no `bpm:ocelTypeExpr`, because "OCEL object
attributes are scalars only" (comment in `ocel_event.ex` and
`ocel_object.ex`).

## Decoding: the admission-gated HTTP router

`BeamPM.OcelIngest.Router` (`lib/beam4pm_ocel_ingest.ex`, GENERATED from
the `bpmi:AdmittedIngestRoute` graph) is the network-facing decode path.
Its admission property: a route not in the admission graph is a real 404
(`route_not_admitted`), and a malformed payload is a typed `422` from the
generated constructor's validation — never a crash and never a catch-all.

## Buffering: the bridge layer

`BeamPM.Ingest.Bridge` (`scripts/ingest_telemetry.exs`) buffers events in
a bounded, named, public `:ordered_set` ETS table owned by a lazily-started
GenServer (oldest-drop cap, `Application.get_env(:beam4pm,
:ingest_buffer_cap, 50_000)`). The design rationale (O(1) ingest,
crash-survivable evidence, why the first `:persistent_term` literal-list
buffer was replaced) is in
`why-the-ingest-bridges-live-in-scripts.md` (same directory).

## Querying: pure functions, caller-owned storage

`BeamPM.Ocel` (`lib/beam4pm_ocel.ex`) is the object-centric query layer:
`object_trace/2` (time-ordered events touching one object, ordered by
`event_time` with `event_id` tie-break, via each event's nested E2O
relationships), `attribute_history/1`, `relationships_for/2`,
`validate_envelope/2`, plus a general OCEL 2.0 JSON `encode/1`/`decode/1`
pair built on the generated structs and `BeamPM.Codec`. Per its
`@moduledoc`, the query functions take plain lists the caller assembles —
the module owns no storage, so "everything ever ingested" accumulation is
the caller's job (Ash resource, ETS, or process state).

## Why this decomposition

Each layer has one job and one owner:

1. Wire decoding is admission-gated (generated, regenerable).
2. Buffering is orchestration (hand-written, script-local, cheap).
3. Querying is pure computation over caller-owned data (hand-written
   wrapper module, no admission needed — same convention as
   `BeamPM.Petgraph`/`BeamPM.Tract`, per `lib/beam4pm_ocel.ex`'s
   `@moduledoc`).

Semantics stay where they are admitted and regenerable; orchestration
stays thin and hand-editable.

See Also: `docs/diataxis/reference/ash-resources-index.md` ·
`docs/diataxis/how-to/ingest-ocel-json-over-http.md` ·
`docs/explanation/object-centric-process-mining-in-beam4pm.md`
