# Ingest telemetry into OCEL traces (tutorial)

A first end-to-end walkthrough of beam4pm's `:telemetry` -> OCEL -> process
discovery pipeline. You will attach a real telemetry handler, fire real
telemetry events, and mine real case-centric traces out of them — no
network, no endpoint, no auth.

Everything you touch in this tutorial already exists. The bridge module
(`BeamPM.Ingest.Bridge`) is hand-authored orchestration defined in
`scripts/ingest_telemetry.exs`; the types it builds
(`BeamPM.Types.OcelEvent`, `BeamPM.Types.LogTrace`) and the discovery
functions (`BeamPM.Discovery.traces_from_events/2`) are GENERATED code under
`lib/` — do not edit any of them by hand (`CONTRIBUTING.md` section 1).

## Prerequisites

- Elixir `~> 1.17` (`mix.exs`)
- Dependencies fetched: `mix deps.get` (the `:telemetry` application ships
  transitively via `:ash`/`:reactor`/`:plug` and is also a direct dep,
  `{:telemetry, "~> 1.4"}` in `mix.exs`)

## 1. Run the shipped demo

From the repo root:

```console
$ mix run scripts/ingest_telemetry.exs
```

The script's bottom demo block (`scripts/ingest_telemetry.exs`) resets the
buffer, attaches the default mapper to `[:demo, :order, :stop]`, fires three
real `:telemetry.execute/3` calls for two cases, and prints:

```
== BeamPM.Ingest.Bridge demo ==
events ingested: 3
traces mined:    2
  case "case-1": ["place", "ship"]
  case "case-2": ["place"]
```

If you only wanted to see the pipeline work, you are done.

## 2. Run the self-test

`scripts/ingest_telemetry_check.exs` is the Chicago-style self-test: real
`:telemetry.execute/3` calls, real `%OcelEvent{}` structs, real assertions on
returned state, exit code 0/1.

```console
$ BEAM4PM_INGEST_SKIP_DEMO=1 mix run scripts/ingest_telemetry_check.exs
...
ALL CHECKS PASSED
```

The env var is required because `mix run` of the check script
`Code.require_file`s `ingest_telemetry.exs`, which would otherwise fire its
own demo events into the same buffer (see the header comment of
`scripts/ingest_telemetry_check.exs`).

## 3. Attach to your own telemetry

The whole integration is one call:

```elixir
:ok = BeamPM.Ingest.Bridge.attach([:ash, :action, :stop])
```

Then any real telemetry emission buffers an OCEL event:

```elixir
:telemetry.execute(
  [:ash, :action, :stop],
  %{duration_native: 1_000, system_time_native: System.monotonic_time()},
  %{resource: MyApp.Order, action: :place, trace_id: "t1", span_id: "s1"}
)
```

Read it back:

```elixir
[%BeamPM.Types.OcelEvent{} = event] = BeamPM.Ingest.Bridge.events()
event.event_id    #=> "t1:s1"     (trace_id:span_id)
event.event_type  #=> "MyApp.Order.place"
event.event_time  #=> ISO8601 string derived from :system_time_native
event.attributes  #=> %{"trace_id" => "t1", "span_id" => "s1", ...}
```

(These exact values are asserted in `scripts/ingest_telemetry_check.exs`.)

## 4. Mine traces

```elixir
traces = BeamPM.Ingest.Bridge.traces("trace_id")
#=> [%BeamPM.Types.LogTrace{case_id: "t1", activity_sequence: [...]}, ...]
```

`traces/1` delegates to the GENERATED
`BeamPM.Discovery.traces_from_events/2` (`lib/beam4pm_discovery.ex`): the
case id is read from each event's `attributes` at the string key
`"trace_id"`; events lacking that key are skipped; events within a case are
ordered by `event_time` (lexicographic ISO8601) with `event_id` breaking
ties.

## 5. Clean up

```elixir
:ok = BeamPM.Ingest.Bridge.detach([:ash, :action, :stop])
BeamPM.Ingest.Bridge.reset()
```

## What you built

A zero-wiring ingestion path: raw `:telemetry.execute/3` calls become real
OCEL 2.0 events in a bounded ETS buffer, and one function call turns them
into case-centric traces ready for discovery/conformance. For the design
rationale (why the buffer is ETS owned by a GenServer, why this lives in
`scripts/` rather than `lib/`), see
`docs/diataxis/explanation/why-the-ingest-bridges-live-in-scripts.md`.

## Troubleshooting

- **Demo prints nothing / script errors on missing `:telemetry`** — run
  `mix deps.get` first; `:telemetry` must be loadable.
- **Two runs, doubled events** — the buffer persists per VM; call
  `BeamPM.Ingest.Bridge.reset/0` between independent runs (as the shipped
  demo does).
- **`{:error, :already_exists}` from `attach/2`** — the exact handler id for
  that event name is already attached (`:telemetry.attach/4`'s contract,
  surfaced not swallowed). `detach/1` the old one first.
