# Realtime Ash-Action OCEL Capture

How `AshEx4pm.Notifier` envelopes reach beam4pm's realtime ingest path as they
are emitted, closing the gap documented in `lib/beam4pm_evidence.ex`'s
moduledoc ("the two evidence stores are disjoint by package design").

## Status

- Upstream: `AshEx4pm.Notifier` threads
  `Application.get_env(:ash_ex4pm, :broadcaster)` into
  `Ex4pm.Stream.Ingest.ingest_envelope/2`'s existing optional `:broadcaster`
  callback (`ex4pm` `lib/ex4pm/stream/ingest.ex:129-137`). This is in the
  local `~/ash_ex4pm` checkout and ships with the NEXT `ash_ex4pm` hex
  release; the released 26.10.1 notifier passes no broadcaster.
- beam4pm: `scripts/ex4pm_bridge.exs` defines `BeamPM.Evidence.Ex4pmBridge`.
- This branch keeps the hex dependency `{:ash_ex4pm, "~> 26.10"}`. Dogfooding
  the unreleased upstream notifier change locally uses a temporary,
  uncommitted `{:ash_ex4pm, path: "../ash_ex4pm", override: true}` override
  (never landed; the bridge and its tests run against released hex 26.10.1
  by passing the broadcaster explicitly). Release path: upstream
  `ash_ex4pm` release publishes -> bump the pin.

## Seam

```text
Ash resource action commits
        |
        v
AshEx4pm.Notifier.notify/1
        |  (post-commit, fire-and-forget; refusals logged, never block)
        v
Ex4pm.Stream.Ingest.ingest_envelope/2
        |
        +-- validation fails --> {:error, _}; no broadcast
        |
        +-- duplicate --> {:duplicate_ignored, _}; returns BEFORE the
        |                 broadcaster call -- duplicates never broadcast
        |
        +-- fresh ingest --> Store.put/2, then optional broadcaster:
                broadcaster.(%{envelope:, log:, event_count:})
                        |
                        v
        BeamPM.Evidence.Ex4pmBridge (app env :broadcaster, or attach/0)
                |  maps envelope -> %BeamPM.Types.OcelEvent{}
                v
        BeamPM.Ingest.Bridge.ingest/1
                +  emits [:beam4pm, :ex4pm, :envelope, :ingested]
```

## What fires when

- **Fresh ingest only.** The broadcaster callback runs once, after
  `Store.put/2`, on the `{:ok, %{status: :ingested, ...}}` path of
  `ingest_envelope/2`.
- **Fire-and-forget.** The notifier ingests post-commit and does not block
  the committing Ash change; the same applies to the bridge hop.
- **`duplicate_ignored` never broadcasts.** `Ex4pm.Stream.Ingest` returns the
  duplicate outcome before reaching the broadcaster call (ingest.ex:77 vs
  ingest.ex:129-137), so replays of an already-ingested envelope do not
  reach the bridge or its telemetry.

## How to attach

Either form works; both feed the same `:broadcaster` contract.

```elixir
# Option 1: app env, read by AshEx4pm.Notifier per notification
Application.put_env(:ash_ex4pm, :broadcaster, &BeamPM.Evidence.Ex4pmBridge.handle_envelope/1)

# Option 2: the bridge's own attach/0
BeamPM.Evidence.Ex4pmBridge.attach()
```

Attach once at application boot (e.g. from `BeamPM.Application.start/2`,
where the other evidence bridges are wired) or from a script.

## Error semantics

- Upstream notifier: refusals are logged and never block the committing
  change (unchanged 26.10.1 behavior).
- Broadcast is best-effort: an exception inside the broadcaster callback
  propagates to the `ingest_envelope/2` caller, it is not rescued by ex4pm.

## See Also

- `docs/explanation/object-centric-process-mining-in-beam4pm.md`
- `lib/beam4pm_evidence.ex` (moduledoc; refresh pending in the next
  generated-docs pass)
- `scripts/ex4pm_bridge.exs`
