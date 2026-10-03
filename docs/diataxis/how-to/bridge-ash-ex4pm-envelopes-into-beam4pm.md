# Bridge ash_ex4pm broadcast envelopes into beam4pm (how-to)

Goal: Ash actions committed in an `ash_ex4pm`-instrumented app should appear
in beam4pm's OCEL buffer in realtime, with zero event loss on refusal.

The seam is `BeamPM.Evidence.Ex4pmBridge` in
`scripts/ex4pm_bridge.exs`. It is the ash_ex4pm `:broadcaster` callback:
ash_ex4pm delivers `%{envelope: envelope, log: %Ex4pm.EventLog{},
event_count: n}` and the bridge maps every `%Ex4pm.Event{}` in the log to a
real `%BeamPM.Types.OcelEvent{}` (built by the GENERATED
`BeamPM.Types.OcelEvent.new/1`, never a hand-rolled struct literal) and
forwards it through `BeamPM.Ingest.Bridge.ingest/1`.

## When to use this vs. plain telemetry ingest

- Use `BeamPM.Ingest.Bridge` (`scripts/ingest_telemetry.exs`) when your
  source is raw `:telemetry.execute/3` calls (engine ops, OTel spans, Ash
  instrumentation).
- Use `BeamPM.Evidence.Ex4pmBridge` (`scripts/ex4pm_bridge.exs`) when your
  source is the ash_ex4pm broadcaster seam — Ash resource actions already
  captured as OCEL 2.0 envelopes upstream.

The two compose: the bridge ingests **into** the same
`BeamPM.Ingest.Bridge` buffer.

## 1. Wire the broadcaster

Simplest wiring:

```elixir
BeamPM.Evidence.Ex4pmBridge.ensure_loaded()
BeamPM.Evidence.Ex4pmBridge.attach()
```

`attach/0` puts the bridge's `broadcaster/1` under
`Application.put_env(:ash_ex4pm, :broadcaster, ...)` and returns the
previous value, so a test can restore it:

```elixir
previous = BeamPM.Evidence.Ex4pmBridge.attach()
# ... run ...
Application.put_env(:ash_ex4pm, :broadcaster, previous)
```

Manual equivalent (what `attach/0` does):

```elixir
Application.put_env(:ash_ex4pm, :broadcaster, &BeamPM.Evidence.Ex4pmBridge.broadcaster/1)
```

### Hex-consumer caveat

The automatic notifier-driven path requires the NEXT `ash_ex4pm` release:
the released 26.10.1 notifier passes no broadcaster. Against released hex
26.10.1, pass the broadcaster explicitly as
`Ex4pm.Stream.Ingest.ingest_envelope/2`'s optional `:broadcaster` opt (this
is exactly what `bench/ex4pm_bridge_bench.exs` does — see `CHANGELOG.md`
[Unreleased]). Note that release path in the changelog: upstream publish,
then bump the `{:ash_ex4pm, "~> 26.10"}` pin in `mix.exs`.

## 2. Fire an envelope and observe

```elixir
payload = %{
  envelope: %{demo: true},
  log: %Ex4pm.EventLog{
    events: [
      %Ex4pm.Event{
        id: "evt-1",
        activity: "order.place",
        timestamp: ~U[2026-10-01 00:00:00Z],
        object_ids: ["order-1", "customer-1"]
      }
    ],
    objects: [%Ex4pm.ObjectRef{id: "order-1", type: "order"}],
    subject: %Ex4pm.Subject{kind: :demo, hash: "subject-demo-hash"},
    object_relationships: []
  },
  event_count: 1
}

^payload = BeamPM.Evidence.Ex4pmBridge.broadcaster(payload)

[%BeamPM.Types.OcelEvent{} = e] = BeamPM.Ingest.Bridge.events()
e.event_id   #=> "evt-1"
e.event_type #=> "order.place"
```

`broadcaster/1` returns the payload unchanged — a broadcaster is a
fire-and-forget observer, not a transformer.

## 3. What happens to each event

For every event in `log.events` (`scripts/ex4pm_bridge.exs`):

- `event_id` <- `event.id`, `event_type` <- `event.activity`,
  `event_time` <- ISO8601 of the timestamp.
- Objects and O2O relationships ride along inside the event's
  `attributes` map (OcelEvent has exactly four fields): `"object_ids"`
  (from the event's `object_ids`), `"object_relationships"` (filtered to
  relationships whose `source_id` is among the event's `object_ids`), plus
  the event's own attributes stringified.
- Success path: ingested via `BeamPM.Ingest.Bridge.ingest/1` and an
  envelope telemetry event is emitted:

  - `[:beam4pm, :ex4pm, :envelope, :ingested]` — measurements
    `%{event_count: n}`, metadata `%{subject_hash:, event_ids:}`.
- Refusal path (constructor validation or `ingest/1` rejection): the event
  is **logged** (`Logger.warning`) and surfaced as
  `[:beam4pm, :ex4pm, :envelope, :refused]` (measurements
  `%{event_count: 1}`, metadata `%{subject_hash:, event_id:, reason:}`) —
  a refused event never breaks the broadcast and is never silently
  swallowed.

## 4. Benchmark and soak evidence

```console
$ MIX_BUILD_ROOT=_build-soak4 MIX_ENV=test mix run --no-start bench/ex4pm_bridge_bench.exs
```

Real envelope maps, real `Ex4pm` normalization + content hashing, real
`OcelEvent` structs, real telemetry. Historical baseline (unbounded
`:persistent_term` buffer): ~397us/event at 2k buffered events, VM crash at
20k — fixed by the bounded ETS buffer documented in
`notes/ex4pm-realtime-audit.md` and cited in the bench header.
`scripts/ex4pm_soak.exs` is the corresponding soak run.

## 5. Load mechanics

Like `BeamPM.Ingest.Bridge`, this module is script-defined and loaded at
runtime via `Code.require_file/1` — `ensure_loaded/0` does the requiring and
also calls `BeamPM.Evidence.ensure_ingest_bridge_loaded/0` so the downstream
`BeamPM.Ingest.Bridge` exists first. Idempotent per VM run. Neither script
needs a `*_SKIP_DEMO` guard for plain loading: `ex4pm_bridge.exs`'s demo
block additionally self-suppresses whenever the `:telemetry` handler table
is absent (e.g. under `mix run --no-start`).

## Troubleshooting

- **Envelopes broadcast, buffer empty** — `BeamPM.Ingest.Bridge` not
  loaded: call `BeamPM.Evidence.Ex4pmBridge.ensure_loaded/0` (it loads both
  scripts).
- **Refused events in logs** — the payload lacked a required OcelEvent
  field; `[:beam4pm, :ex4pm, :envelope, :refused]` metadata carries
  `reason`. This is the constructor's field-presence validation doing its
  job.
- **Old events between runs** — `BeamPM.Ingest.Bridge.reset/0` between
  independent runs; the buffer cap default is 50,000 events
  (`Application.get_env(:beam4pm, :ingest_buffer_cap, 50_000)`),
  oldest-drop.
