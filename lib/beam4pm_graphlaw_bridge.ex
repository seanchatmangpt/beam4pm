defmodule BeamPM.GraphlawBridge.Conformance do
  @moduledoc """
  Conformance verdict for one `BeamPM.GraphlawBridge.conform/1` run: which
  oracle decided (native RF3 binary or the Elixir engine-handle path), what
  it decided, the real facts it saw, and the on-disk receipt path. Written
  on every decidable path; an oracle that could not run at all returns
  `{:error, term()}` from `conform/1` instead of a verdict.
  """

  defstruct [:outcome, :oracle, :reason, :counts, :verified, :oracle_out, :receipt_path]

  @typedoc "A decided verdict: the oracle ran and answered (:conformant | :refused)."
  @type outcome :: :conformant | :refused

  @typedoc "Which oracle decided: the native binary or the Elixir engine-handle build."
  @type oracle :: :native_rf3_binary | :elixir_engine_handle

  @type t :: %__MODULE__{
          outcome: outcome(),
          oracle: oracle(),
          reason: term() | nil,
          counts: %{events: non_neg_integer(), objects: non_neg_integer()},
          verified: map(),
          oracle_out: map() | nil,
          receipt_path: String.t()
        }
end

defmodule BeamPM.GraphlawBridge do
  @moduledoc """
  Real `[:graphlaw_ex, :admit, :stop]` telemetry -> OCEL 2.0 bridge for the
  graphlaw admission kernel's Elixir bindings (`GraphlawEx`, the graphlaw
  checkout's `graphlaw_ex` app, whose `GraphlawEx.Telemetry.events/0` names
  this family).

  This is the beam4pm-side counterpart of `BeamPM.Evidence`'s
  `[:beam4pm, :engine, engine, op]` bridge family: same mechanics
  (`:telemetry.attach_many/4` to an exact event name, an
  `engine_op_mapper/2`-shaped pure mapper, one buffered OCEL event per
  invocation), different event family. `BeamPM.Evidence`'s bridges remain
  authoritative EXCLUSIVELY for the `[:beam4pm, :engine, engine, op]`
  engine family; this module attaches to the graphlaw_ex admit family and
  never to a beam4pm engine op. The two handlers are disjoint by event
  name, so attaching both is well-defined.

  ## Envelope shape (exactly what `BeamPM.OcelAccumulator.ingest/2` and
  `BeamPM.Ocel.validate_envelope/2` already take)

    * one `BeamPM.Types.OcelEvent` per admit-span stop: `event_type` (the
      OCEL activity) is `"graphlaw_ex." <> op` -- activity = op, namespaced
      by the source engine per `BeamPM.Evidence.engine_op_mapper/2`'s
      `engine.op` convention; `event_time` is the observation-time
      UTC timestamp (an admit-stop measurement carries only `duration` in
      native units, the span's start wall clock is not recoverable, so the
      timestamp is taken when the stop event is observed); `attributes`
      carry the graphlaw identity/outcome fields; `event_id` mints a unique
      suffix because graphlaw_ex admit metadata carries no invocation id;
    * one `BeamPM.Types.OcelObject` per distinct `server` value found in
      the admit metadata -- the object ref FROM the metadata: the graphlaw
      admission server that executed the admit; the event carries an E2O
      `admitted_by` relationship to it, so the envelope is
      referentially closed and `BeamPM.Ocel.validate_envelope/2` returns
      `:ok` over a mapped envelope with no extra objects supplied.

  Art. 12 (GL28-1 leg b): every bridged event carries the source identity
  of the law content the span executed --
  `attributes["pe:sourceDigest"]`, the engine-minted `blake3:` LawState.id
  (RDFC-1.0 canonical N-Quads of the CONTENT, not the source bytes;
  `wasm_sha256` routes to the engine object and is never reused). The
  mapper emits it only when the admit metadata carries `:source_digest`;
  `ingest/1` REFUSES any envelope whose events lack it (typed
  `{:error, {:missing_field, :source_digest}}`, all-or-nothing) -- absence
  is a refusal, never a silent pass.

  ## Conformance leg (after `ingest/2`)

  `conform/1` runs the ACCUMULATED content (what `ingest/2` wrote into the
  real `BeamPM.OcelAccumulator`) through the RF3 conformance oracle and
  returns the verdict plus exactly one on-disk receipt on every path:

    * native path: a compiled `rf3-conformance-oracle` binary present at
      `native/rf3-conformance-oracle` is called through the real RF3
      oracle subprocess wrapper (`BeamPM.RF3Ocel.Oracle.call/3`, the
      single-JSON-in/single-JSON-out wire contract of the RF3 oracle
      family) over the accumulated content serialized to a real OCEL 2.0
      JSON temp file; the oracle's real stats are cross-checked against
      the accumulated counts/type frequencies and any mismatch is a typed
      `:refused` verdict, never a silent pass.
    * Elixir path (else): `BeamPM.OcelAccumulator.to_engine_handle/0` --
      the accumulated content through the real rust4pm engine (which
      refuses dangling relationships and undeclared types); a built
      handle is `:conformant`, the handle is then freed.

  Absence is named, never faked: with neither capability available (no
  binary at `native/rf3-conformance-oracle` and the rust4pm wasm artifact
  not built) `conform/1` returns a typed
  `{:error, {:conformance_oracle_absent, _}}` and the test suite
  loud-skips.
  """

  require Logger

  alias BeamPM.GraphlawBridge.Conformance
  alias BeamPM.OcelAccumulator
  alias BeamPM.RF3Ocel.Oracle
  alias BeamPM.Rust4PM
  alias BeamPM.Types.OcelEvent
  alias BeamPM.Types.OcelObject
  alias BeamPM.Types.OcelRelationship

  @event_name [:graphlaw_ex, :admit, :stop]
  @server_object_type "graphlaw_ex_server"
  @admitted_by "admitted_by"

  @conformance_oracle_rel "native/rf3-conformance-oracle"
  @conformance_receipt_schema "beam4pm-graphlaw-bridge-conformance/v1"

  @typedoc "Ingest-ready envelope: the exact input shape of BeamPM.OcelAccumulator.ingest/2."
  @type envelope :: %{
          required(:events) => [{OcelEvent.t(), [OcelRelationship.t()]}],
          required(:objects) => [{OcelObject.t(), [OcelRelationship.t()]}]
        }

  @doc """
  The exact graphlaw_ex admit-stop event name this bridge attaches to
  (`GraphlawEx.Telemetry.events/0`'s `[:graphlaw_ex, :admit, :stop]`:
  measurements `%{duration: native}`, metadata
  `%{op: String.t(), server: term, source_digest: String.t() | nil,
  outcome: :ok | :refused, refusal_code: atom | nil}` — `source_digest` is
  the engine-minted `blake3:` LawState.id of the law content the span
  executed, nil when the caller omitted the opt).
  """
  @spec event_name() :: [atom()]
  def event_name, do: @event_name

  @doc """
  Attaches the OCEL ingest handler for `event_name/0`. Idempotent per
  handler id, matching `BeamPM.Evidence.attach_all/0`'s own convention --
  a second attach returns `:ok` rather than double-attaching.
  """
  @spec attach() :: :ok
  def attach do
    case :telemetry.attach_many(__MODULE__, [event_name()], &__MODULE__.handle_event/4, %{}) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  @doc "Detaches the handler (a `{:error, :not_found}` when never attached is surfaced, not swallowed)."
  @spec detach() :: :ok | {:error, :not_found}
  def detach, do: :telemetry.detach(__MODULE__)

  @doc """
  Pure `engine_op_mapper/2`-style mapping from a real admit-stop
  `(measurements, metadata)` pair into an ingest-ready OCEL 2.0 envelope
  (see the moduledoc for the field-by-field derivation). Synthetic inputs
  are lawful input: the mapper reads only the two maps it is given.
  """
  @spec mapper(map(), map()) :: envelope()
  def mapper(measurements, metadata) when is_map(measurements) and is_map(metadata) do
    op = Map.get(metadata, :op)
    op_string = string_or_inspect(op)
    server_string = metadata |> Map.get(:server) |> string_or_inspect()
    server_object_id = "graphlaw_ex.server." <> server_string

    attributes = %{
      "graphlaw.op" => op_string,
      "graphlaw.server" => server_string,
      "graphlaw.outcome" => metadata |> Map.get(:outcome) |> inspect(),
      "graphlaw.refusal_code" => metadata |> Map.get(:refusal_code) |> refusal_code_string(),
      "graphlaw.duration_native" => measurements |> Map.get(:duration, 0) |> duration_string()
    }
    # GL28-1 leg (b), Art. 12: the source identity of the law content the
    # span executed (engine-minted `blake3:` LawState.id) is a REQUIRED
    # attribute on every bridged event -- required by the ingest gate below,
    # not by the mapper: a nil (metadata carrying no :source_digest) omits
    # the key here, and `ingest/1` then refuses the envelope.
    |> maybe_put("pe:sourceDigest", Map.get(metadata, :source_digest))

    event = %OcelEvent{
      event_id: "graphlaw_admit_" <> op_string <> "_" <> unique_suffix(),
      event_type: "graphlaw_ex." <> op_string,
      event_time: DateTime.utc_now() |> DateTime.to_iso8601(),
      attributes: attributes
    }

    server_object = %OcelObject{
      object_id: server_object_id,
      object_type: @server_object_type,
      attributes: %{"graphlaw.server" => server_string}
    }

    relationship = %OcelRelationship{qualifier: @admitted_by, object_id: server_object_id}

    %{events: [{event, [relationship]}], objects: [{server_object, []}]}
  end

  @doc """
  Ingest path: refuses (typed, all-or-nothing -- nothing is written) any
  envelope whose events are missing their OCEL 2.0 activity (`event_type`),
  timestamp (`event_time`), or Article 12 source identity
  (`attributes["pe:sourceDigest"]`, the engine-minted `blake3:` LawState.id
  of the law content executed), mirroring the generated
  `BeamPM.Types.OcelEvent.new/1` refusal shape `{:error, {:missing_field,
  field}}`; anything structurally malformed beyond that is left to
  `BeamPM.OcelAccumulator.ingest/2`'s own typed refusals
  (`{:expected_event_with_relationships, _}`, `{:duplicate_record, _}`,
  `{:missing_id, _}`). On success the accumulator's real counts return.
  """
  @spec ingest(envelope()) ::
          {:ok, %{events: non_neg_integer(), objects: non_neg_integer()}} | {:error, term()}
  def ingest(%{events: events, objects: objects}) when is_list(events) and is_list(objects) do
    case first_missing_field(events) do
      nil -> OcelAccumulator.ingest(events, objects)
      field when is_atom(field) -> {:error, {:missing_field, field}}
    end
  end

  # -------------------------------------------------------------------
  # Conformance leg (after ingest/2): the accumulated content through
  # the RF3 conformance oracle -- native binary when present, else the
  # Elixir engine-handle path. One receipt on every path, never a fake.
  # -------------------------------------------------------------------

  @doc """
  Conformance verdict over the accumulated (post-`ingest/2`) content.
  Chooses the oracle by real availability: the compiled binary at
  `#{File.cwd!()}/#{@conformance_oracle_rel}` when a regular file,
  otherwise the Elixir engine-handle path. Returns
  `{:ok, %Conformance{}}` for a decided verdict (`:conformant` or
  `:refused`) and `{:error, term()}` when no oracle could run (empty
  accumulator, stopped accumulator, binary absent AND wasm artifact not
  built, or the native binary failing at the wire level) -- in every case
  exactly one `#{@conformance_receipt_schema}` receipt is written at
  `<receipts_dir>/<run_id>.json`.

  Options: `:run_id` (default a fresh unique id), `:receipts_dir`
  (default `receipts/graphlaw_bridge` under the current working
  directory), `:timeout` (native-oracle call timeout ms, default
  10_000), `:receipt_extras` (a string-keyed map merged as top-level
  fields into the on-disk receipt, default `%{}` -- e.g. the real
  engine digest as `%{"engine_sha256" => ...}`).
  """
  @spec conform(keyword()) :: {:ok, Conformance.t()} | {:error, term()}
  def conform(opts \\ [])

  def conform(opts) when is_list(opts) do
    norm = conform_opts(opts)

    case accumulated() do
      {:error, reason} ->
        _ =
          write_conformance_receipt(norm, %{
            "oracle" => nil,
            "outcome" => "unavailable",
            "reason" => reason_text(reason),
            "counts" => %{events: 0, objects: 0},
            "verified" => %{},
            "oracle_out" => nil,
            "replay" => %{"oracle_bin" => nil}
          })

        {:error, reason}

      {:ok, events, objects} ->
        if events == [] do
          reason = {:empty_accumulator, "conform/1 runs the ACCUMULATED log; ingest/2 first"}

          _ =
            write_conformance_receipt(norm, %{
              "oracle" => nil,
              "outcome" => "unavailable",
              "reason" => reason_text(reason),
              "counts" => %{events: 0, objects: length(objects)},
              "verified" => %{},
              "oracle_out" => nil,
              "replay" => %{"oracle_bin" => nil}
            })

          {:error, reason}
        else
          counts = %{events: length(events), objects: length(objects)}

          case conformance_oracle_bin() do
            nil -> run_elixir_conformance(events, objects, counts, norm)
            bin -> run_native_conformance(bin, events, objects, counts, norm)
          end
        end
    end
  end

  @doc """
  The compiled `rf3-conformance-oracle` binary path when a regular file is
  present at `#{@conformance_oracle_rel}`, `nil` when absent -- a named
  absence, never a fake.
  """
  @spec conformance_oracle_bin() :: String.t() | nil
  def conformance_oracle_bin do
    path = Path.expand(@conformance_oracle_rel)
    if File.regular?(path), do: path, else: nil
  end

  # Elixir path: the accumulated content through the real rust4pm engine.
  # The engine-handle BUILD is the conformance check (the engine refuses
  # dangling relationships and undeclared types); a built handle is
  # :conformant and is then freed (caller-owned, per the accumulator's
  # handle law).
  defp run_elixir_conformance(events, objects, counts, norm) do
    case OcelAccumulator.to_engine_handle() do
      {:ok, handle} ->
        _ = Rust4PM.free_ocel(handle)

        conformance_done(
          :conformant,
          :elixir_engine_handle,
          nil,
          counts,
          %{
            engine_handle_built: true,
            event_type_counts: event_type_frequencies(events),
            object_type_counts: object_type_frequencies(objects)
          },
          nil,
          nil,
          norm
        )

      {:error, :wasm_missing} ->
        reason = {:conformance_oracle_absent, Rust4PM.wasm_missing_reason()}

        _ =
          write_conformance_receipt(norm, %{
            "oracle" => nil,
            "outcome" => "unavailable",
            "reason" => reason_text(reason),
            "counts" => counts,
            "verified" => %{},
            "oracle_out" => nil,
            "replay" => %{"oracle_bin" => nil}
          })

        {:error, reason}

      {:error, reason} ->
        conformance_done(
          :refused,
          :elixir_engine_handle,
          reason,
          counts,
          %{},
          nil,
          nil,
          norm
        )
    end
  end

  # Native path: the accumulated content serialized to a real OCEL 2.0
  # JSON temp file, run through the real binary via the RF3 oracle
  # subprocess wrapper, its real stats cross-checked against the
  # accumulated counts/type frequencies.
  defp run_native_conformance(bin, events, objects, counts, norm) do
    tmp_ocel =
      Path.join(
        System.tmp_dir!(),
        "graphlaw-bridge-ocel2-#{System.unique_integer([:positive, :monotonic])}.ocel.json"
      )

    try do
      with {:ok, body} <- ocel2_encode(events, objects),
           :ok <- File.write(tmp_ocel, body),
           {:ok, out} <-
             Oracle.call(bin, %{"op" => "ocel_stats", "ocel_path" => tmp_ocel}, norm.timeout) do
        classify_native(out, bin, events, objects, counts, norm)
      else
        {:error, reason} ->
          _ =
            write_conformance_receipt(norm, %{
              "oracle" => "native_rf3_binary",
              "outcome" => "unavailable",
              "reason" => reason_text(reason),
              "counts" => counts,
              "verified" => %{},
              "oracle_out" => nil,
              "replay" => %{"oracle_bin" => bin}
            })

          {:error, {:oracle_failed, reason}}
      end
    after
      _ = File.rm(tmp_ocel)
    end
  end

  defp classify_native(out, bin, events, objects, counts, norm) do
    case out do
      %{"ok" => true} ->
        diffs = native_diffs(out, events, objects, counts)

        case diffs do
          [] ->
            conformance_done(
              :conformant,
              :native_rf3_binary,
              nil,
              counts,
              native_facts(out),
              out,
              bin,
              norm
            )

          _ ->
            conformance_done(
              :refused,
              :native_rf3_binary,
              {:oracle_stats_diverged_from_accumulated, diffs},
              counts,
              %{},
              out,
              bin,
              norm
            )
        end

      %{"ok" => false} = out ->
        conformance_done(
          :refused,
          :native_rf3_binary,
          {:oracle_reported_not_ok, out["error"]},
          counts,
          %{},
          out,
          bin,
          norm
        )

      other ->
        _ =
          write_conformance_receipt(norm, %{
            "oracle" => "native_rf3_binary",
            "outcome" => "unavailable",
            "reason" => reason_text({:oracle_bad_reply_shape, other}),
            "counts" => counts,
            "verified" => %{},
            "oracle_out" => safe_oracle_out(other),
            "replay" => %{"oracle_bin" => bin}
          })

        {:error, {:oracle_bad_reply_shape, other}}
    end
  end

  defp native_diffs(out, events, objects, counts) do
    type_stats = Map.get(out, "type_stats") || %{}

    []
    |> diff_field(Map.get(out, "num_events"), counts.events, :num_events)
    |> diff_field(Map.get(out, "num_objects"), counts.objects, :num_objects)
    |> diff_field(
      Map.get(type_stats, "event_type_counts"),
      event_type_frequencies(events),
      :event_type_counts
    )
    |> diff_field(
      Map.get(type_stats, "object_type_counts"),
      object_type_frequencies(objects),
      :object_type_counts
    )
    |> Enum.reverse()
  end

  defp native_facts(out) do
    %{
      num_events: out["num_events"],
      num_objects: out["num_objects"],
      event_type_counts: out["type_stats"]["event_type_counts"],
      object_type_counts: out["type_stats"]["object_type_counts"]
    }
  end

  defp diff_field(diffs, actual, expected, _name) when actual == expected, do: diffs
  defp diff_field(diffs, actual, expected, name), do: [{name, %{expected: expected, oracle_saw: actual}} | diffs]

  defp event_type_frequencies(events) do
    Enum.frequencies_by(events, fn {%OcelEvent{event_type: type}, _rels} -> type end)
  end

  defp object_type_frequencies(objects) do
    Enum.frequencies_by(objects, fn {%OcelObject{object_type: type}, _rels} -> type end)
  end

  # OCEL 2.0 JSON (the spec's JSON binding -- eventTypes/objectTypes/events/
  # objects with name/attributes declarations, id/type/time/attributes/
  # relationships records) over the accumulated content: the input format
  # the RF3 oracle family's real process_mining importer consumes.
  defp ocel2_encode(events, objects) do
    doc = %{
      "eventTypes" =>
        events
        |> event_type_frequencies()
        |> Map.keys()
        |> Enum.sort()
        |> Enum.map(&%{"name" => &1, "attributes" => []}),
      "objectTypes" =>
        objects
        |> object_type_frequencies()
        |> Map.keys()
        |> Enum.sort()
        |> Enum.map(&%{"name" => &1, "attributes" => []}),
      "events" =>
        Enum.map(events, fn {%OcelEvent{} = e, rels} ->
          %{
            "id" => e.event_id,
            "type" => e.event_type,
            "time" => e.event_time,
            "attributes" => ocel2_attributes(e.attributes),
            "relationships" => ocel2_relationships(rels)
          }
        end),
      "objects" => ocel2_objects(objects, events)
    }

    try do
      {:ok, JSON.encode!(doc)}
    rescue
      e in ArgumentError -> {:error, {:ocel2_encode_failed, Exception.message(e)}}
    end
  end

  defp ocel2_attributes(attrs) when is_map(attrs) do
    attrs
    |> Enum.sort_by(fn {name, _value} -> name end)
    |> Enum.map(fn {name, value} -> %{"name" => name, "value" => value} end)
  end

  defp ocel2_attributes(_other), do: []

  # Object attribute records in OCEL 2.0 JSON carry a `time` (the valid time
  # of the attribute value), and the RF3 oracle's process_mining importer
  # requires it (OCELObjectAttribute has no serde default for `time`). The
  # accumulator model stores object attributes without timestamps, so the
  # valid time is derived from the log itself: the earliest `event_time` among
  # the events that reference the object (its first observation in this log),
  # falling back to the log's earliest event. No wall-clock minting -- the
  # emitted time is always a real event_time from the accumulated content.
  defp ocel2_objects(objects, events) do
    Enum.map(objects, fn {%OcelObject{} = o, rels} ->
      %{
        "id" => o.object_id,
        "type" => o.object_type,
        "attributes" => ocel2_object_attributes(o.attributes, events, o.object_id),
        "relationships" => ocel2_relationships(rels)
      }
    end)
  end

  defp ocel2_object_attributes(attrs, events, object_id) when is_map(attrs) do
    case object_attribute_time(events, object_id) do
      {:ok, time} ->
        attrs
        |> Enum.sort_by(fn {name, _value} -> name end)
        |> Enum.map(fn {name, value} -> %{"name" => name, "value" => value, "time" => time} end)

      :error ->
        raise ArgumentError,
              "ocel2_encode: object #{inspect(object_id)} carries attributes but the " <>
                "accumulated log has no events to derive an attribute valid time from"
    end
  end

  defp ocel2_object_attributes(_other, _events, _object_id), do: []

  defp object_attribute_time(events, object_id) do
    referencing = referencing_event_times(events, object_id)

    case {referencing, events} do
      {[], []} -> :error
      {[], _} -> {:ok, earliest_event_time(events)}
      {times, _} -> {:ok, Enum.min(times)}
    end
  end

  defp referencing_event_times(events, object_id) do
    Enum.flat_map(events, fn {%OcelEvent{event_time: t}, rels} ->
      if Enum.any?(rels, &(&1.object_id == object_id)), do: [t], else: []
    end)
  end

  defp earliest_event_time(events) do
    events |> Enum.map(fn {%OcelEvent{event_time: t}, _} -> t end) |> Enum.min()
  end

  defp ocel2_relationships(rels) do
    Enum.map(rels, fn %OcelRelationship{object_id: object_id, qualifier: qualifier} ->
      %{"objectId" => object_id, "qualifier" => qualifier}
    end)
  end

  defp conformance_done(outcome, oracle, reason, counts, verified, oracle_out, replay_bin, norm) do
    path =
      write_conformance_receipt(norm, %{
        "oracle" => Atom.to_string(oracle),
        "outcome" => Atom.to_string(outcome),
        "reason" => (reason && reason_text(reason)) || nil,
        "counts" => counts,
        "verified" => verified,
        "oracle_out" => oracle_out,
        "replay" => %{"oracle_bin" => replay_bin}
      })

    {:ok,
     %Conformance{
       outcome: outcome,
       oracle: oracle,
       reason: reason,
       counts: counts,
       verified: verified,
       oracle_out: oracle_out,
       receipt_path: path
     }}
  end

  defp conform_opts(opts) do
    %{
      receipts_dir:
        Keyword.get(opts, :receipts_dir, Path.join(File.cwd!(), "receipts/graphlaw_bridge")),
      run_id:
        Keyword.get(
          opts,
          :run_id,
          "graphlaw-bridge-conform-#{System.system_time(:millisecond)}-#{System.unique_integer([:positive])}"
        ),
      timeout: Keyword.get(opts, :timeout, 10_000),
      # GL28-1 leg c: caller-supplied extra top-level receipt fields (e.g. the
      # engine's real wasm digest from GraphlawEx.Host.info/1). Default %{} --
      # existing call sites merge nothing and stay behavior-identical.
      extras: Keyword.get(opts, :receipt_extras, %{})
    }
  end

  defp write_conformance_receipt(norm, fields) do
    receipt =
      Map.merge(
        %{
          "receipt_schema" => @conformance_receipt_schema,
          "run_id" => norm.run_id,
          "bridge" => "BeamPM.GraphlawBridge"
        },
        fields
      )
    |> Map.merge(norm.extras)

    path = Path.join(norm.receipts_dir, norm.run_id <> ".json")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, JSON.encode!(receipt))
    path
  end

  defp safe_oracle_out(other) when is_map(other), do: other
  defp safe_oracle_out(other), do: %{"raw" => inspect(other)}

  defp reason_text(reason) when is_binary(reason), do: reason
  defp reason_text(reason), do: inspect(reason)

  defp accumulated do
    {:ok, OcelAccumulator.events(), OcelAccumulator.objects()}
  rescue
    ArgumentError -> {:error, :accumulator_not_running}
  end

  @doc false
  # Telemetry handler: map then ingest, never raising out of the handler.
  # An ingest refusal is logged (never a silent drop) and never propagated:
  # a telemetry handler must not crash the emitting admit call.
  def handle_event(_event_name, measurements, metadata, _config) do
    case measurements
         |> then(&mapper(&1, Map.new(metadata)))
         |> ingest() do
      {:ok, _counts} ->
        :ok

      {:error, reason} ->
        Logger.warning("BeamPM.GraphlawBridge ingest refused: " <> inspect(reason))
    end

    :ok
  end

  # The bridge's own refusal surface: activity (event_type), timestamp
  # (event_time) and the Article 12 source identity (a binary
  # `attributes["pe:sourceDigest"]`) must all be present on every event in
  # the envelope. Structurally malformed pairs are skipped here (they return
  # nil) so the accumulator's own typed shape refusal fires downstream
  # instead.
  defp first_missing_field(events) do
    Enum.reduce_while(events, nil, fn
      {%OcelEvent{} = event, rels}, _acc when is_list(rels) ->
        cond do
          not is_binary(event.event_type) -> {:halt, :event_type}
          not is_binary(event.event_time) -> {:halt, :event_time}
          not is_binary(source_digest_of(event)) -> {:halt, :source_digest}
          true -> {:cont, nil}
        end

      _other, _acc ->
        {:cont, nil}
    end)
  end

  # nil attributes are structural (skipped above so the accumulator's own
  # typed shape refusal fires downstream); a present attributes map without
  # the binary `pe:sourceDigest` halts with `:source_digest`.
  defp source_digest_of(%OcelEvent{attributes: attrs}) when is_map(attrs),
    do: Map.get(attrs, "pe:sourceDigest")

  defp source_digest_of(_event), do: nil

  defp string_or_inspect(value) when is_binary(value), do: value
  defp string_or_inspect(value), do: inspect(value)

  # Leg (b) mapper tail: put the key only when the value is present (a nil
  # `:source_digest` in the telemetry metadata OMITS the attribute -- the
  # ingest gate, not the mapper, turns absence into a typed refusal).
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp refusal_code_string(nil), do: nil
  defp refusal_code_string(code) when is_atom(code), do: Atom.to_string(code)
  defp refusal_code_string(code), do: inspect(code)

  defp duration_string(native) when is_integer(native), do: Integer.to_string(native)
  defp duration_string(other), do: inspect(other)

  defp unique_suffix, do: Integer.to_string(System.unique_integer([:positive, :monotonic]))
end
