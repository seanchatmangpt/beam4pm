defmodule BeamPM.OcelSessionFacts do
  @moduledoc """
  Closes the observation edge between real OCEL event logs and Ferroplan's
  strictly-boolean `session_observe/3` sight batch: OCEL logs in (three real
  upstream serialization dialects), real POWL conformance deviations out,
  projected as `[{fact_name :: String.t(), boolean()}]` feedable to
  `BeamPM.Ferroplan.session_observe/3` one-for-one (`session_set_fact/4`
  guards facts to `is_boolean/1`).

  Hand-written orchestration over already-real engine ops (same convention
  as `BeamPM.PowlConformance`/`BeamPM.OcelIngest.Router`; not
  ggen-generated -- no admitted pack expresses this projection yet, which
  is exactly the capability gap this module names).

  ## Input dialects (detected structurally, never by filename)

    * `:zcode_plain_key` -- one JSON document with plain top-level keys
      `objectTypes` / `eventTypes` / `objects` / `events`; each event
      `{id, type, time, attributes: [{name, value}], relationships:
      [{objectId, qualifier}]}` (zcode-cli generated `ocel.ts` shape).
    * `:xaas_ocel_prefixed` -- the RESHAPED xaas ndjson form: each line is
      a complete OCEL 2.0 JSON log with `ocel:`-prefixed TOP-LEVEL keys
      (`ocel:objectTypes` / `ocel:eventTypes` / `ocel:events` /
      `ocel:objects`); events carry plain spec keys `{id, type, time,
      attributes: %{..}, relationships: [{objectId, qualifier}]}`. The
      legacy flat per-line `ocel:eid`/`ocel:activity` shape is NOT this
      dialect -- it is the typed violation named by
      `Xaas.Telemetry.OcelNdjson` -- and is refused here as unknown.
    * `:beam4pm_ingest` -- beam4pm's own internal shape: `event_id` /
      `event_type` / `event_time` / `attributes` (map) / `relationships`
      nested as `[{qualifier, object_id}]` (the shape
      `BeamPM.OcelIngest.Router` decodes into and echoes).
    * `:internal` -- a list already in the internal shape (`normalize/1`
      is idempotent on its own output).

  The normalized event shape IS the internal (`:beam4pm_ingest`) shape:

      %{
        "event_id" => binary(),
        "event_type" => binary(),
        "event_time" => binary(),
        "attributes" => %{binary() => term()},
        "relationships" => [%{"qualifier" => binary(), "object_id" => binary()}]
      }

  Events are returned sorted by `{event_time, event_id}` -- a
  deterministic canonical order, so identical inputs normalize to
  identical outputs.

  ## Fact-name policy (pinned, lane RESOLUTIONS #4)

    * umbrella fact `"conforms"` = the conformance result's `conforms`
      boolean;
    * each deviation move `[log_side, model_side]`:
        - model-only move (`log_side == ">>"`, the log skipped an
          activity the model requires) -> fact `"dev_" <> activity`
          where `activity` is the NON-`">>"` side (`model_side`);
        - log-only move (`model_side == ">>"`) -> fact
          `"dev_" <> log_side`;
        - BOTH sides real activities (a substitution) -> one fact per
          side: `"dev_log_" <> log_side` and `"dev_model_" <>
          model_side`;
        - both sides `">>"` (degenerate; alignment never emits it) ->
          contributes no fact;
    * discretized attributes (opt `:attributes`, a map of the observed
      trace's attributes): ONLY boolean-valued attributes become facts --
      fact `name <> "_" <> value` where value is the exact string
      `"true"`/`"false"` (or a real `true`/`false`). Any other value
      (numbers, non-boolean strings, nil) is SKIPPED and counted in
      `skipped_attributes` (`fact_summary/2`, `sight_for_trace/4`).

  All emitted facts are `true`; the list is deduplicated and sorted by
  fact name -- deterministic order, feedable to `session_observe/3`
  as-is.

  ## Redaction note

  Inputs are assumed POST-REDACTION: the upstream tap redacts attribute
  values at ingest, BEFORE hashing, so this module never receives and
  never needs raw sensitive values. Corollary obligations enforced here:
  this module performs NO logging at all (no logging facilities of any
  kind, no direct output), and its
  error details carry STRUCTURAL information only (dialect atoms, reason
  atoms, indices) -- never raw attribute values, event ids, or object
  ids. Attribute values reach facts ONLY through the boolean-token
  discretization above, so an emitted sight batch can carry nothing
  beyond boolean tokens.

  ## Process model (documented, not fixed here)

  Conformance runs against the ONE shared `BeamPM.Rust4PM.Engine` wasmex
  GenServer. As documented in `BeamPM.Rust4PM` (and identically for the
  Ferroplan engine), a call exit or timeout STOPS AND DISCARDS the
  engine; a restart yields a fresh store and INVALIDATES every
  previously issued handle -- including caller-held OCEL handles passed
  to `sight_for_trace/4`. This module does not re-validate handles
  (handle lifecycle belongs to the caller); an invalidated handle
  surfaces as the engine's own typed `{:error, {:wasmex, _}}` refusal.
  When `sight_for_trace/4` builds the OCEL handle itself (the events
  path), it owns that handle and frees it before returning.
  """

  alias BeamPM.PowlConformance
  alias BeamPM.Rust4PM

  @typedoc """
  The normalized internal event shape (== the `:beam4pm_ingest` wire
  shape): exactly the five string keys `"event_id"`, `"event_type"`,
  `"event_time"` (binaries), `"attributes"` (string-keyed map), and
  `"relationships"` (list of `%{"qualifier" => binary(), "object_id" =>
  binary()}`).
  """
  @type event_map() :: %{String.t() => term()}

  @typedoc "Which serialization dialect the input was detected as."
  @type dialect() :: :zcode_plain_key | :xaas_ocel_prefixed | :beam4pm_ingest | :internal

  @typedoc "Boolean sight batch accepted 1:1 by `BeamPM.Ferroplan.session_observe/3`."
  @type sight() :: [{String.t(), boolean()}]

  @typedoc """
  Pure summary of one sight projection. `dialect` is `:handle` when the
  caller supplied a live OCEL handle (no normalization happened).
  """
  @type summary() :: %{
          conforms: boolean(),
          deviation_count: non_neg_integer(),
          skipped_attributes: non_neg_integer(),
          dialect: dialect() | :handle
        }

  @typedoc "Structural-only error detail -- never carries raw attribute values."
  @type dialect_error() :: {:ocel_dialect_unknown, %{String.t() => term()}}

  # ---------------------------------------------------------------------
  # normalize/1
  # ---------------------------------------------------------------------

  @doc """
  Detects the input's serialization dialect structurally and projects it
  to the internal event shape.

  Accepts:

    * a single document map -- dialect `:zcode_plain_key` (plain top-level
      `events`), `:beam4pm_ingest` (snake_case `events`), or
      `:xaas_ocel_prefixed` (`ocel:`-prefixed top-level keys);
    * a list of ndjson line maps, each carrying the `ocel:`-prefixed
      top-level keys (dialect b);
    * a list of already-internal event maps (idempotent passthrough).

  Returns `{:ok, [event_map()]}` sorted by `{event_time, event_id}`, or
  `{:error, {:ocel_dialect_unknown, detail}}` where `detail` is
  structural only. Normalization is all-or-nothing: one malformed event
  inside an otherwise-recognized dialect refuses the whole input.
  """
  @spec normalize(map() | [map()]) :: {:ok, [event_map()]} | {:error, dialect_error()}
  def normalize(input) do
    case normalize_with_dialect(input) do
      {:ok, events, _dialect} -> {:ok, events}
      {:error, detail} -> {:error, detail}
    end
  end

  # Single source of truth for dialect detection + projection; `dialect`
  # is consumed by sight_for_trace's summary.
  defp normalize_with_dialect(%{"ocel:events" => events} = doc) when is_list(events) do
    if Map.has_key?(doc, "ocel:objectTypes") or Map.has_key?(doc, "ocel:objects") do
      case normalize_xaas_events(events) do
        {:ok, normalized} -> {:ok, normalized, :xaas_ocel_prefixed}
        {:error, detail} -> {:error, detail}
      end
    else
      {:error,
       dialect_unknown(%{
         "dialect" => :xaas_ocel_prefixed,
         "reason" => :document_missing_object_surface
       })}
    end
  end

  defp normalize_with_dialect(%{"events" => events} = doc) when is_list(events) do
    cond do
      events != [] and Enum.all?(events, &is_map/1) and Enum.all?(events, &internal_event?/1) ->
        {:ok, sort_events(events), :beam4pm_ingest}

      events == [] and Map.has_key?(doc, "objects") ->
        # An empty zcode-shaped document is unambiguous (plain-key surface).
        {:ok, [], :zcode_plain_key}

      events != [] and Enum.all?(events, &is_map/1) and Enum.all?(events, &zcode_event?/1) ->
        case normalize_zcode_events(events) do
          {:ok, normalized} -> {:ok, normalized, :zcode_plain_key}
          {:error, detail} -> {:error, detail}
        end

      true ->
        {:error,
         dialect_unknown(%{"input_kind" => :events_document, "reason" => :event_shape_unrecognized})}
    end
  end

  defp normalize_with_dialect(input) when is_list(input) do
    cond do
      input != [] and Enum.all?(input, &is_map/1) and Enum.all?(input, &internal_event?/1) ->
        {:ok, sort_events(input), :internal}

      input != [] and Enum.all?(input, &is_map/1) and
          Enum.all?(input, &Map.has_key?(&1, "ocel:events")) ->
        case xaas_lines_events(input) do
          {:ok, events} -> {:ok, events, :xaas_ocel_prefixed}
          {:error, detail} -> {:error, detail}
        end

      true ->
        {:error, dialect_unknown(%{"input_kind" => kind_of(input), "reason" => :no_dialect_matched})}
    end
  end

  defp normalize_with_dialect(input) do
    {:error, dialect_unknown(%{"input_kind" => kind_of(input), "reason" => :not_a_document_or_list})}
  end

  # -- dialect detection per event -----------------------------------------

  defp internal_event?(%{"event_id" => id, "event_type" => t, "event_time" => time})
       when is_binary(id) and is_binary(t) and is_binary(time),
       do: true

  defp internal_event?(_), do: false

  # Detection is STRUCTURAL only (id/type/time binary, attributes a list).
  # Deeper well-formedness (attribute pair keys, relationship shapes) is
  # reported by the per-event parser so the refusal can name the dialect
  # and the offending event index.
  defp zcode_event?(%{"id" => id, "type" => t, "time" => time, "attributes" => attrs})
       when is_binary(id) and is_binary(t) and is_binary(time) and is_list(attrs),
       do: true

  defp zcode_event?(_), do: false

  # -- dialect a: zcode plain-key document ----------------------------------

  defp normalize_zcode_events(events) do
    events
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {event, i}, {:ok, acc} ->
      case normalize_zcode_event(event) do
        {:ok, normalized} ->
          {:cont, {:ok, [normalized | acc]}}

        {:error, reason} ->
          {:halt,
           {:error,
            dialect_unknown(%{
              "dialect" => :zcode_plain_key,
              "reason" => reason,
              "event_index" => i
            })}}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, sort_events(Enum.reverse(reversed))}
      error -> error
    end
  end

  defp normalize_zcode_event(%{"id" => id, "type" => type, "time" => time} = event)
       when is_binary(id) and is_binary(type) and is_binary(time) do
    with {:ok, attrs} <- zcode_attributes(Map.get(event, "attributes", [])),
         {:ok, rels} <- oid_qualifier_relationships(Map.get(event, "relationships", [])) do
      {:ok,
       %{
         "event_id" => id,
         "event_type" => type,
         "event_time" => time,
         "attributes" => attrs,
         "relationships" => rels
       }}
    end
  end

  defp normalize_zcode_event(_), do: {:error, :missing_required_plain_keys}

  defp zcode_attributes(attrs) when is_list(attrs) do
    Enum.reduce_while(attrs, {:ok, %{}}, fn
      %{"name" => name, "value" => value}, {:ok, acc} when is_binary(name) ->
        {:cont, {:ok, Map.put(acc, name, value)}}

      _, _ ->
        {:halt, {:error, :malformed_attribute_pair}}
    end)
  end

  defp zcode_attributes(_), do: {:error, :attributes_not_a_list}

  # `[{objectId, qualifier}]` (dialects a and b) -> internal relationship
  # shape `[{"object_id" =>, "qualifier" =>}]`, order-preserving.
  defp oid_qualifier_relationships(rels) when is_list(rels) do
    Enum.reduce_while(rels, {:ok, []}, fn
      %{"objectId" => oid, "qualifier" => q}, {:ok, acc} when is_binary(oid) and is_binary(q) ->
        {:cont, {:ok, [%{"object_id" => oid, "qualifier" => q} | acc]}}

      _, _ ->
        {:halt, {:error, :malformed_relationship}}
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      error -> error
    end
  end

  defp oid_qualifier_relationships(_), do: {:error, :relationships_not_a_list}

  # -- dialect b: xaas ocel:-prefixed (ndjson lines or one document) --------

  defp xaas_lines_events(lines) do
    lines
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {line, i}, {:ok, acc} ->
      case normalize_xaas_events(Map.fetch!(line, "ocel:events")) do
        {:ok, events} ->
          {:cont, {:ok, Enum.reverse(events) ++ acc}}

        {:error, {:ocel_dialect_unknown, detail}} ->
          {:halt,
           {:error,
            {:ocel_dialect_unknown, Map.put(detail, "line_index", i)}}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, sort_events(Enum.reverse(acc))}
      error -> error
    end
  end

  defp normalize_xaas_events(events) when is_list(events) do
    events
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {event, i}, {:ok, acc} ->
      case normalize_xaas_event(event) do
        {:ok, normalized} ->
          {:cont, {:ok, [normalized | acc]}}

        {:error, reason} ->
          {:halt,
           {:error,
            dialect_unknown(%{
              "dialect" => :xaas_ocel_prefixed,
              "reason" => reason,
              "event_index" => i
            })}}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      error -> error
    end
  end

  defp normalize_xaas_events(_),
    do: {:error, dialect_unknown(%{"dialect" => :xaas_ocel_prefixed, "reason" => :events_not_a_list})}

  defp normalize_xaas_event(%{"id" => id, "type" => type, "time" => time} = event)
       when is_binary(id) and is_binary(type) and is_binary(time) do
    with {:ok, attrs} <- xaas_attributes(Map.get(event, "attributes", %{})),
         {:ok, rels} <- oid_qualifier_relationships(Map.get(event, "relationships", [])) do
      {:ok,
       %{
         "event_id" => id,
         "event_type" => type,
         "event_time" => time,
         "attributes" => attrs,
         "relationships" => rels
       }}
    end
  end

  defp normalize_xaas_event(_), do: {:error, :missing_or_non_binary_spec_keys}

  defp xaas_attributes(attrs) when is_map(attrs) and not is_struct(attrs) do
    if Enum.all?(attrs, fn {k, _} -> is_binary(k) end) do
      {:ok, attrs}
    else
      {:error, :non_string_attribute_key}
    end
  end

  defp xaas_attributes(_), do: {:error, :attributes_not_a_map}

  # -- shared helpers ---------------------------------------------------------

  defp sort_events(events) do
    Enum.sort_by(events, &{Map.fetch!(&1, "event_time"), Map.fetch!(&1, "event_id")})
  end

  defp kind_of(input) when is_list(input), do: :list
  defp kind_of(input) when is_map(input), do: :map
  defp kind_of(_), do: :other

  defp dialect_unknown(fields), do: {:ocel_dialect_unknown, fields}

  # ---------------------------------------------------------------------
  # deviation_facts/2 + fact_summary/2
  # ---------------------------------------------------------------------

  @doc """
  Projects one `BeamPM.PowlConformance.check_conformance/3` result into
  the boolean sight batch, per the pinned fact-name policy (see the
  moduledoc). `opts` may carry `:attributes` -- a map of the observed
  trace's attributes; only boolean-valued ones become facts, the rest are
  skipped (counted by `fact_summary/2`). The returned list is
  deduplicated and sorted by fact name.
  """
  @spec deviation_facts(PowlConformance.conformance_result(), keyword()) :: sight()
  def deviation_facts(result, opts \\ []) when is_map(result) and is_list(opts) do
    {facts, _skipped} = build_facts(result, opts)
    facts
  end

  @doc """
  The same projection as `deviation_facts/2`, with the pure summary:
  `%{facts:, conforms:, deviation_count:, skipped_attributes:}`.
  `deviation_facts/2` returns exactly `fact_summary/2`'s `:facts`.
  """
  @spec fact_summary(PowlConformance.conformance_result(), keyword()) ::
          %{
            facts: sight(),
            conforms: boolean(),
            deviation_count: non_neg_integer(),
            skipped_attributes: non_neg_integer()
          }
  def fact_summary(result, opts \\ []) when is_map(result) and is_list(opts) do
    {facts, skipped} = build_facts(result, opts)

    %{
      facts: facts,
      conforms: result.conforms == true,
      deviation_count: deviations_of(result) |> length(),
      skipped_attributes: skipped
    }
  end

  defp build_facts(result, opts) do
    {attr_facts, skipped} = attribute_facts(Keyword.get(opts, :attributes, %{}))

    facts =
      %{"conforms" => Map.get(result, :conforms) == true}
      |> Map.merge(move_facts(deviations_of(result)))
      |> Map.merge(attr_facts)
      |> Enum.to_list()
      |> Enum.sort()

    {facts, skipped}
  end

  defp deviations_of(result), do: Map.get(result, :deviations) || []

  # One alignment move [log_side, model_side] per the pinned policy.
  defp move_facts(deviations) do
    Enum.reduce(deviations, %{}, fn
      [">>", ">>"], acc ->
        # Degenerate move: contributes nothing.
        acc

      [">>", model_side], acc when is_binary(model_side) ->
        Map.put(acc, "dev_" <> model_side, true)

      [log_side, ">>"], acc when is_binary(log_side) ->
        Map.put(acc, "dev_" <> log_side, true)

      [log_side, model_side], acc when is_binary(log_side) and is_binary(model_side) ->
        acc
        |> Map.put("dev_log_" <> log_side, true)
        |> Map.put("dev_model_" <> model_side, true)

      _malformed, acc ->
        # check_conformance types moves as 2-element string lists; a
        # malformed move contributes nothing rather than crashing the
        # sight batch.
        acc
    end)
  end

  defp attribute_facts(attrs) when is_map(attrs) and not is_struct(attrs) do
    Enum.reduce(attrs, {%{}, 0}, fn
      {name, value}, {acc, skipped} when is_binary(name) ->
        case boolean_token(value) do
          nil -> {acc, skipped + 1}
          token -> {Map.put(acc, name <> "_" <> token, true), skipped}
        end

      _non_string_name, {acc, skipped} ->
        {acc, skipped + 1}
    end)
  end

  defp attribute_facts(_), do: {%{}, 0}

  defp boolean_token(true), do: "true"
  defp boolean_token(false), do: "false"
  defp boolean_token("true"), do: "true"
  defp boolean_token("false"), do: "false"
  defp boolean_token(_), do: nil

  # ---------------------------------------------------------------------
  # sight_for_trace
  # ---------------------------------------------------------------------

  @doc """
  Runs real POWL conformance (`BeamPM.PowlConformance.check_conformance/3`)
  and projects the result into `{:ok, sight, summary}`.

  `reference` is either

    * a live OCEL handle from `BeamPM.Rust4PM` -- the caller owns its
      lifecycle and the summary's `dialect` is `:handle`; or
    * events -- a list (internal-shape event maps or dialect-b ndjson
      lines) or a single document map (any accepted dialect). The events
      are normalized, turned into a real OCEL handle via `ocel_new` +
      `ocel_add_*`, conformed, and the handle is FREED before returning.

  `opts`:

    * `:attributes` -- the observed trace's attribute map, discretized
      per the fact-name policy;
    * `:objects` -- optional `[%{"object_id" => id, "object_type" => t}]`
      used when building the handle from events. Object ids referenced by
      event relationships but absent from `:objects` are auto-added with
      object type = the relationship's qualifier (xaas's own qualifier
      rule is "the referenced object's type, lowercased", so
      qualifier-derived types are exact for xaas logs and for beam4pm's
      own reference logs; zcode role qualifiers like `"in_turn"` REQUIRE
      `:objects` to carry the real object types).

  Errors: `{:error, {:ocel_build, reason}}` if handle construction fails
  at an engine op (best-effort `free_ocel` first; `reason` is the
  engine's own `{:engine, _}`/`{:wasmex, _}` tuple), or the engine's own
  typed error from `check_conformance/3` -- including the artifact-absent
  `{:error, {:wasmex, {:engine_not_started, _}}}` refusal.
  """
  @spec sight_for_trace(non_neg_integer() | map() | [map()], String.t(), [String.t()], keyword()) ::
          {:ok, sight(), summary()} | {:error, term()}
  def sight_for_trace(reference, object_type, test_trace_activities, opts \\ [])

  def sight_for_trace(handle, object_type, test_trace_activities, opts)
      when is_integer(handle) and is_binary(object_type) and is_list(test_trace_activities) and
             is_list(opts) do
    with {:ok, result} <-
           PowlConformance.check_conformance(handle, object_type, test_trace_activities) do
      {:ok, sight, summary} = summarize(result, :handle, opts)
      {:ok, sight, summary}
    end
  end

  def sight_for_trace(events, object_type, test_trace_activities, opts)
      when (is_list(events) or is_map(events)) and is_binary(object_type) and
             is_list(test_trace_activities) and is_list(opts) do
    with {:ok, events, dialect} <- normalize_with_dialect(events),
         {:ok, handle} <- build_ocel_handle(events, opts),
         :ok <- populate_handle(handle, events, Keyword.get(opts, :objects, [])),
         {:ok, result} <-
           PowlConformance.check_conformance(handle, object_type, test_trace_activities) do
      _ = Rust4PM.free_ocel(handle)
      {:ok, sight, summary} = summarize(result, dialect, opts)
      {:ok, sight, summary}
    else
      {:error, {:ocel_dialect_unknown, _}} = err -> err
      {:error, {:engine, _}} = err -> err
      {:error, {:wasmex, _}} = err -> err
      {:error, reason} -> {:error, {:ocel_build, reason}}
    end
  end

  defp summarize(result, dialect, opts) do
    summary = fact_summary(result, opts)

    {:ok, summary.facts,
     %{
       conforms: summary.conforms,
       deviation_count: summary.deviation_count,
       skipped_attributes: summary.skipped_attributes,
       dialect: dialect
     }}
  end

  defp build_ocel_handle(_events, _opts) do
    case Rust4PM.ocel_new() do
      {:ok, %{"ocel_handle" => handle}} -> {:ok, handle}
      {:error, reason} -> {:error, {:ocel_build, reason}}
    end
  end

  # Populates a real OCEL handle from normalized events: the exact recipe
  # proven in test/beam4pm_deviation_admission_test.exs (ocel_new ->
  # ocel_add_event_type per activity -> ocel_add_object_type +
  # ocel_add_object per object -> ocel_add_event with [object_id,
  # qualifier] e2o pairs), driven from the events themselves.
  defp populate_handle(handle, events, objects_opt) do
    declared_objects =
      objects_opt
      |> Enum.flat_map(fn
        %{"object_id" => id, "object_type" => t} when is_binary(id) and is_binary(t) ->
          [{id, t}]

        _malformed ->
          []
      end)
      |> Map.new()

    # Every object referenced by any event relationship; type from the
    # caller's :objects declaration, else the relationship qualifier.
    referenced =
      for event <- events,
          rel <- event["relationships"] || [],
          into: %{},
          do: {rel["object_id"], Map.get(declared_objects, rel["object_id"], rel["qualifier"])}

    objects = Map.merge(referenced, declared_objects)

    event_types = events |> Enum.map(& &1["event_type"]) |> Enum.uniq() |> Enum.sort()
    object_types = objects |> Map.values() |> Enum.uniq() |> Enum.sort()

    event_steps =
      for event <- events do
        {:ocel_add_event,
         [
           handle,
           event["event_id"],
           event["event_type"],
           event["event_time"],
           for(rel <- event["relationships"] || [], do: [rel["object_id"], rel["qualifier"]])
         ]}
      end

    steps =
      List.flatten([
        for(t <- event_types, do: {:ocel_add_event_type, [handle, t]}),
        for(t <- object_types, do: {:ocel_add_object_type, [handle, t]}),
        for({id, t} <- Enum.sort(objects), do: {:ocel_add_object, [handle, id, t]}),
        event_steps
      ])

    steps
    |> Enum.reduce_while(:ok, fn {op, args}, :ok ->
      case apply(Rust4PM, op, args) do
        {:ok, _} -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      :ok ->
        :ok

      {:error, _} = err ->
        _ = Rust4PM.free_ocel(handle)
        {:error, err}
    end
  end
end
