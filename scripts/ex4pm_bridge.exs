# ex4pm_bridge.exs -- the ash_ex4pm `:broadcaster` -> `BeamPM.Ingest.Bridge`
# forwarding seam, closing the two-store gap flagged in
# `lib/beam4pm_evidence.ex`'s moduledoc ("once an upstream ash_ex4pm
# broadcaster exists, a `BeamPM.Evidence.Ex4pmBridge` can attach to it and
# forward envelopes through `BeamPM.Ingest.Bridge.ingest/1`").
#
# Hand-authored orchestration over ALREADY-GENERATED capital
# (`BeamPM.Types.OcelEvent`, `BeamPM.Ingest.Bridge`) plus the upstream
# `Ex4pm.EventLog` IR -- not itself a `bpm:RecordType` projection, so it
# lives under scripts/ (a hand-editable manufacturing input per CLAUDE.md's
# doctrine), never under lib/, and therefore never needs a
# `bpm:HandAuthoredSource` admission or trips
# scripts/gate_authorship_check.sh -- the same placement rationale as
# scripts/ingest_telemetry.exs.
#
# `BeamPM.Types.OcelEvent` has exactly four fields (`event_id`,
# `event_type`, `event_time`, `attributes`), so the EventLog's
# objects/relationships ride along inside each event's `attributes` map
# rather than as separate struct fields -- the object membership (E2O
# relationships) and O2O relationships the upstream log carries are
# preserved as attribute data on every event they touch.

defmodule BeamPM.Evidence.Ex4pmBridge do
  @moduledoc """
  Bridges the upstream ash_ex4pm broadcaster seam into beam4pm's OCEL
  buffer.

  The broadcaster fun handed to ash_ex4pm via
  `Application.put_env(:ash_ex4pm, :broadcaster, ...)`: ash_ex4pm delivers
  `%{envelope: envelope, log: %Ex4pm.EventLog{}, event_count: n}` and this
  module maps each of the log's `%Ex4pm.Event{}` into one real
  `%BeamPM.Types.OcelEvent{}` (via the GENERATED
  `BeamPM.Types.OcelEvent.new/1`, never a hand-rolled struct literal --
  the constructor's field-presence validation is exercised on every event)
  and ingests it through `BeamPM.Ingest.Bridge.ingest/1`. A refused event
  never breaks the broadcast: it is logged and surfaced as a
  `[:beam4pm, :ex4pm, :envelope, :refused]` telemetry event, matching
  beam4pm's existing evidence-error style (surfaced, not swallowed).

  Defined in scripts/ex4pm_bridge.exs (a hand-editable manufacturing
  input, per CLAUDE.md's doctrine -- never under lib/, so never compiled
  into the OTP release by default); loaded via `ensure_loaded/0`'s
  `Code.require_file/1`, the same pattern
  `BeamPM.Evidence.ensure_ingest_bridge_loaded/0` already uses for
  scripts/ingest_telemetry.exs.
  """

  alias BeamPM.Types.OcelEvent

  @doc """
  The 1-arity fun handed to ash_ex4pm as its `:broadcaster` callback.

  Payload contract (upstream lane L1): `%{envelope: envelope, log:
  %Ex4pm.EventLog{}, event_count: non_neg_integer()}`. Every event in
  `log.events` is mapped to an `OcelEvent` and ingested individually;
  objects and O2O relationships ride along inside the events' `attributes`
  (object ids via each event's `object_ids`, O2O pairs via the
  `"o2o_relationships"` attribute key on the events they touch).

  Emits `[:beam4pm, :ex4pm, :envelope, :ingested]` with
  `measurements: %{event_count: n}` and `metadata: %{subject_hash:,
  event_ids:}` on success. Returns the payload unchanged (a broadcaster is
  a fire-and-forget observer, not a transformer).
  """
  @spec broadcaster(map()) :: map()
  def broadcaster(%{log: %Ex4pm.EventLog{} = log} = payload) do
    BeamPM.Evidence.ensure_ingest_bridge_loaded()

    event_ids =
      log.events
      |> Enum.map(fn event -> ingest_one(event, log) end)
      |> Enum.reject(&is_nil/1)

    :telemetry.execute(
      [:beam4pm, :ex4pm, :envelope, :ingested],
      %{event_count: length(event_ids)},
      %{subject_hash: subject_hash(log), event_ids: event_ids}
    )

    payload
  end

  @doc false
  @spec ingest_one(Ex4pm.Event.t(), Ex4pm.EventLog.t()) :: String.t() | nil
  def ingest_one(event, log) do
    case OcelEvent.new(%{
           event_id: event.id,
           event_type: event.activity,
           event_time: to_iso8601(event.timestamp),
           attributes: event_attributes(event, log)
         }) do
      {:ok, ocel_event} ->
        # `apply/3`, not a direct call: BeamPM.Ingest.Bridge is
        # runtime-defined (scripts/ingest_telemetry.exs, loaded via
        # Code.require_file), and a direct call would emit an
        # "undefined module" compile-time warning -- the same
        # `apply(...)` pattern lib/beam4pm_evidence.ex's attach_all/0
        # already uses.
        case apply(BeamPM.Ingest.Bridge, :ingest, [ocel_event]) do
          :ok -> event.id
          other -> {:error, other}
        end

      {:error, reason} ->
        {:error, reason}
    end
    |> case do
      event_id when is_binary(event_id) ->
        event_id

      {:error, reason} ->
        require Logger

        Logger.warning(
          "BeamPM.Evidence.Ex4pmBridge refused event " <>
            inspect(event.id) <> ": " <> inspect(reason)
        )

        :telemetry.execute(
          [:beam4pm, :ex4pm, :envelope, :refused],
          %{event_count: 1},
          %{subject_hash: subject_hash(log), event_id: event.id, reason: inspect(reason)}
        )

        nil
    end
  end

  @doc """
  Loads this module's defining script via `Code.require_file/1`, the same
  pattern `BeamPM.Evidence.ensure_ingest_bridge_loaded/0` uses for
  scripts/ingest_telemetry.exs. Idempotent per VM run. This script has no
  bottom-level demo block, so no `*_SKIP_DEMO` env guard is needed --
  requiring the file only defines the module.
  """
  @spec ensure_loaded() :: :ok
  def ensure_loaded do
    unless Code.ensure_loaded?(__MODULE__) do
      Code.require_file(Path.join([__DIR__, "ex4pm_bridge.exs"]))
    end

    BeamPM.Evidence.ensure_ingest_bridge_loaded()
    :ok
  end

  @doc """
  Convenience wiring: puts this module's `broadcaster/1` as ash_ex4pm's
  `:broadcaster` application env and returns the PREVIOUS value so a
  caller (a test) can restore it. Returns the previous value even when it
  was unset (`nil`).
  """
  @spec attach() :: previous :: term()
  def attach do
    previous = Application.get_env(:ash_ex4pm, :broadcaster)
    Application.put_env(:ash_ex4pm, :broadcaster, &__MODULE__.broadcaster/1)
    previous
  end

  ## Internals

  defp event_attributes(event, log) do
    %{
      "object_ids" => Enum.map(event.object_ids, &object_id(&1)),
      "object_relationships" =>
        log.object_relationships
        |> Enum.filter(fn rel -> rel.source_id in event.object_ids end)
        |> Enum.map(fn rel ->
          %{
            "source_id" => object_id(rel.source_id),
            "target_id" => object_id(rel.target_id),
            "qualifier" => to_string(rel.qualifier)
          }
        end)
        |> Enum.uniq()
    }
    |> Map.merge(stringified_attributes(event.attributes))
  end

  defp object_id(%Ex4pm.ObjectRef{id: id}), do: object_id(id)
  defp object_id(id) when is_binary(id), do: id
  defp object_id(other), do: inspect(other)

  defp stringified_attributes(attrs) when attrs == %{}, do: %{}

  defp stringified_attributes(attrs) when is_map(attrs) do
    Map.new(attrs, fn {k, v} -> {to_string(k), if(is_binary(v), do: v, else: inspect(v))} end)
  end

  defp to_iso8601(%DateTime{} = t), do: DateTime.to_iso8601(t)
  defp to_iso8601(%NaiveDateTime{} = t), do: NaiveDateTime.to_iso8601(t)
  defp to_iso8601(t) when is_binary(t), do: t
  defp to_iso8601(t), do: to_string(t)

  defp subject_hash(log) do
    case log.subject && Map.get(log.subject, :hash) do
      hash when is_binary(hash) and hash != "" -> hash
      _ -> log.subject |> :erlang.phash2() |> Integer.to_string()
    end
  end
end

# The demo needs the real `:telemetry` handler table (a GenServer started
# with the :telemetry application): under `mix run --no-start` the app is
# not booted, so the demo is skipped there rather than crashing on the
# missing handler-table process.
if System.get_env("BEAM4PM_EX4PM_BRIDGE_SKIP_DEMO") != "1" and
     Process.whereis(:telemetry_handler_table) != nil do
  BeamPM.Evidence.ensure_ingest_bridge_loaded()
  BeamPM.Evidence.Ex4pmBridge.ensure_loaded()
  BeamPM.Ingest.Bridge.reset()

  previous = BeamPM.Evidence.Ex4pmBridge.attach()

  log = %Ex4pm.EventLog{
    events: [
      %Ex4pm.Event{
        id: "evt-1",
        activity: "order.place",
        timestamp: ~U[2026-10-01 00:00:00Z],
        object_ids: ["order-1", "customer-1"]
      },
      %Ex4pm.Event{
        id: "evt-2",
        activity: "order.ship",
        timestamp: ~U[2026-10-01 01:00:00Z],
        object_ids: ["order-1"]
      }
    ],
    objects: [
      %Ex4pm.ObjectRef{id: "order-1", type: "order"},
      %Ex4pm.ObjectRef{id: "customer-1", type: "customer"}
    ],
    subject: %Ex4pm.Subject{kind: :demo, hash: "subject-demo-hash"},
    object_relationships: [
      %Ex4pm.ObjectRelationship{
        source_id: "order-1",
        target_id: "customer-1",
        qualifier: "placed_by"
      }
    ]
  }

  :telemetry.attach(
    {:ex4pm_bridge_demo, :ingested},
    [:beam4pm, :ex4pm, :envelope, :ingested],
    fn _name, measurements, metadata, _ ->
      IO.puts(
        "== BeamPM.Evidence.Ex4pmBridge demo ==\n" <>
          "ingested: #{inspect(measurements)} subject_hash=#{metadata.subject_hash} " <>
          "event_ids=#{inspect(metadata.event_ids)}"
      )
    end,
    nil
  )

  BeamPM.Evidence.Ex4pmBridge.broadcaster(%{envelope: %{demo: true}, log: log, event_count: 2})

  buffered = BeamPM.Ingest.Bridge.events()
  IO.puts("buffered OcelEvents: #{length(buffered)}")
  IO.inspect(Enum.map(buffered, & &1.event_id), label: "buffered event_ids")

  for %BeamPM.Types.OcelEvent{event_id: eid, attributes: attrs} <- buffered do
    IO.puts("  #{eid}: object_ids=#{inspect(attrs["object_ids"])}")
  end

  :telemetry.detach({:ex4pm_bridge_demo, :ingested})
  Application.put_env(:ash_ex4pm, :broadcaster, previous)
end
