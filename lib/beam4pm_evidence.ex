defmodule BeamPM.Evidence do
  @moduledoc """
  Wires the real `[:beam4pm, :engine, engine, op]` `:telemetry.execute/3`
  event family (emitted by every generated engine facade op -- see
  `vendor/ggen-marketplace/packs/beam4pm-process-model-pack/templates/
  beam4pm_engine.ex.tmpl`, OCEL evidence-contract Phase 2) to two real
  consumers, both attached at application boot by `BeamPM.Application`:

    1. `BeamPM.Ingest.Bridge` (`scripts/ingest_telemetry.exs`, already
       real/working capital -- not rewritten here) -- buffers a real
       `%BeamPM.Types.OcelEvent{}` per invocation.
    2. `BeamPM.Evidence.OtelBridge` (this module) -- opens/closes a real
       OpenTelemetry span per invocation, mirroring the OCEL event's
       identity fields as span attributes.

  Hand-authored orchestration over already-generated capital
  (`BeamPM.Ingest.Bridge`, the generated engine facades' telemetry
  metadata shape, `BeamPM.Types.OcelEvent`) -- not itself a `bpm:RecordType`
  projection or a template-rendered file, so it lives under `lib/` as a
  genuinely hand-written module analogous to `lib/beam4pm_application.ex`
  and `lib/beam4pm_ocel_ingest.ex` (both already hand-authored `lib/`
  modules with no `GENERATED` marker), not under `scripts/`. It is called
  from `BeamPM.Application.start/2`, which is itself the correct place per
  that module's own doc comment: "supervision-tree wiring is a
  manufacturing input ... never generated output."

  ## Event family

  Every admitted `bpm:EngineOp` fact (79 total: ferroplan 33, rust4pm 31,
  petgraph 10, tract 5 -- `schema/beam4pm_engine_ops.tsv`) becomes one
  `[:beam4pm, :engine, engine, op]` telemetry event name, fired on both the
  success and `{:error, reason}` refusal paths. `:telemetry.attach/4`
  requires one exact event-name list per handler (no wildcard/prefix
  matching), so `event_names/0` below derives the full 79-name list
  directly from the same generated manifest
  `scripts/gate_engine_dispatch_check.sh` already reads, rather than
  hand-enumerating engine/op pairs (which would drift the moment a new
  `bpm:EngineOp` fact is admitted).
  """

  @manifest_path Path.join([__DIR__, "..", "schema", "beam4pm_engine_ops.tsv"])

  @doc """
  Every `[:beam4pm, :engine, engine, op]` event name admitted in
  `schema/beam4pm_engine_ops.tsv`, deduplicated (the manifest has one row
  per (engine, op, wire_name) triple; several wire ops can share one op
  name at the dispatch level, e.g. arity variants -- deduplicated here
  since `:telemetry.attach_many/4` needs one entry per distinct event
  name, not one per manifest row).
  """
  @spec event_names() :: [[atom()]]
  def event_names do
    @manifest_path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.starts_with?(&1, "#"))
    |> Enum.map(fn line ->
      [engine, op | _rest] = String.split(line, "\t")
      [:beam4pm, :engine, String.to_atom(engine), String.to_atom(op)]
    end)
    |> Enum.uniq()
  end

  @doc """
  Attaches both real consumers (OCEL bridge + OTel span bridge) to every
  event name in `event_names/0`. Idempotent per handler id, matching
  `:telemetry.attach/4`'s own contract -- calling this twice returns
  `{:error, :already_exists}` from the second call rather than
  double-firing (surfaced, not swallowed).
  """
  @spec attach_all() :: :ok
  def attach_all do
    ensure_ingest_bridge_loaded()
    names = event_names()

    :ok =
      case apply(BeamPM.Ingest.Bridge, :attach_many, [names, &__MODULE__.engine_op_mapper/2]) do
        :ok -> :ok
        {:error, :already_exists} -> :ok
      end

    :ok = BeamPM.Evidence.OtelBridge.attach(names)
  end

  # `BeamPM.Ingest.Bridge` is defined in scripts/ingest_telemetry.exs (a
  # hand-editable manufacturing input, per CLAUDE.md's doctrine -- never
  # under lib/, so never compiled into the OTP release by default).
  # `Code.require_file/1` is idempotent per VM run (a second require_file
  # of the same absolute path is a documented no-op), so calling this from
  # `attach_all/0` more than once in one running node is safe.
  # `BEAM4PM_INGEST_SKIP_DEMO=1` suppresses the script's own bottom-level
  # demo block (real `:telemetry.execute/3` calls against a `[:demo, ...]`
  # event name) so requiring the file at application boot only defines the
  # module -- it never fires the demo's own telemetry events into the
  # buffer this module is about to attach real engine-op handlers to.
  @doc false
  @spec ensure_ingest_bridge_loaded() :: :ok
  def ensure_ingest_bridge_loaded do
    unless Code.ensure_loaded?(BeamPM.Ingest.Bridge) do
      System.put_env("BEAM4PM_INGEST_SKIP_DEMO", "1")
      Code.require_file(Path.join([__DIR__, "..", "scripts", "ingest_telemetry.exs"]))
    end

    :ok
  end

  @doc """
  Mapper from a real engine-op telemetry event's `(measurements, metadata)`
  into the four fields `BeamPM.Types.OcelEvent.new/1` requires, giving each
  buffered `OcelEvent` a meaningful `event_type` (`"<engine>.<op>"`,
  OCEL activity-equivalent) and `event_id` (from the real
  `invocation_id`) instead of `BeamPM.Ingest.Bridge.default_mapper/2`'s
  generic fallback (which is shaped for OTel/Ash span metadata, not this
  event family's `:engine`/`:op`/`:invocation_id` metadata keys).
  """
  @spec engine_op_mapper(map(), map()) :: map()
  def engine_op_mapper(measurements, metadata) do
    engine = Map.get(metadata, :engine)
    op = Map.get(metadata, :op)
    invocation_id = Map.get(metadata, :invocation_id)

    attrs =
      metadata
      |> Map.take([:op_iri, :engine, :op, :args_digest, :invocation_id, :verification_class, :refusal_reason])
      |> Map.new(fn {k, v} -> {to_string(k), if(is_binary(v), do: v, else: inspect(v))} end)
      |> Map.put("duration_native", to_string(Map.get(measurements, :duration_native, 0)))

    %{
      event_id: "engine_op_" <> inspect(invocation_id),
      event_type: "#{engine}.#{op}",
      event_time: DateTime.utc_now() |> DateTime.to_iso8601(),
      attributes: attrs
    }
  end
end

defmodule BeamPM.Evidence.OtelBridge do
  @moduledoc """
  Real OTel span emission half of the `[:beam4pm, :engine, engine, op]`
  bridge. A `:telemetry` handler (not a `with_span/3` wrapper around the
  call site itself, since the span must be opened and closed from inside
  one telemetry callback that only ever sees the already-completed
  measurements/metadata `:telemetry.execute/3` was called with -- the
  generated facade emits ONE event per call, after the call already
  returned, so this handler uses `OpenTelemetry.Tracer.start_span/2` +
  `OpenTelemetry.Span.end_span/1` around that already-known duration
  rather than `with_span/3`, which expects to wrap the still-executing
  work itself).

  Span attributes mirror the OCEL event's identity fields, dot-namespaced
  per the `ocel.*`/`<domain>.*` convention confirmed this session in xaas,
  adapted to beam4pm's own domain (`beam4pm.capability.*`):

    * `beam4pm.capability.id`   -- `"<engine>.<op>"` (OCEL activity-equivalent)
    * `beam4pm.capability.engine`
    * `beam4pm.capability.op`
    * `beam4pm.capability.op_iri`
    * `beam4pm.capability.invocation_id`
    * `beam4pm.capability.verification_class`
    * `beam4pm.capability.args_digest`
    * `ocel.outcome`            -- `"ok"` or `"error"`
    * `ocel.refusal_reason`     -- present only on the refusal path
  """

  require OpenTelemetry.Tracer

  @doc "Attaches this handler (id `#{inspect(__MODULE__)}`) for every event name in `names`."
  @spec attach([[atom()]]) :: :ok
  def attach(names) when is_list(names) do
    case :telemetry.attach_many(__MODULE__, names, &__MODULE__.handle_event/4, %{}) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  @doc "Detaches this handler."
  @spec detach() :: :ok | {:error, :not_found}
  def detach do
    :telemetry.detach(__MODULE__)
  end

  @doc false
  def handle_event([:beam4pm, :engine, engine, op], measurements, metadata, _config) do
    span_name = "beam4pm.engine.#{engine}.#{op}"
    outcome = if Map.has_key?(metadata, :refusal_reason), do: "error", else: "ok"

    attrs = [
      {"beam4pm.capability.id", "#{engine}.#{op}"},
      {"beam4pm.capability.engine", to_string(engine)},
      {"beam4pm.capability.op", to_string(op)},
      {"beam4pm.capability.op_iri", to_string(Map.get(metadata, :op_iri, ""))},
      {"beam4pm.capability.invocation_id", inspect(Map.get(metadata, :invocation_id))},
      {"beam4pm.capability.verification_class", to_string(Map.get(metadata, :verification_class, ""))},
      {"beam4pm.capability.args_digest", to_string(Map.get(metadata, :args_digest, ""))},
      {"ocel.outcome", outcome}
    ]

    attrs =
      case Map.get(metadata, :refusal_reason) do
        nil -> attrs
        reason -> [{"ocel.refusal_reason", to_string(reason)} | attrs]
      end

    ctx = OpenTelemetry.Tracer.start_span(span_name, %{attributes: attrs})
    duration_native = Map.get(measurements, :duration_native, 0)
    duration_ms = System.convert_time_unit(duration_native, :native, :millisecond)

    OpenTelemetry.Span.set_attribute(ctx, "beam4pm.capability.duration_ms", duration_ms)

    status =
      case outcome do
        "ok" -> OpenTelemetry.status(:ok)
        _ -> OpenTelemetry.status(:error, to_string(Map.get(metadata, :refusal_reason, "")))
      end

    OpenTelemetry.Span.set_status(ctx, status)
    OpenTelemetry.Span.end_span(ctx)
    :ok
  end
end
