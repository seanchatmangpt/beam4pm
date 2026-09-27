defmodule BeamPM.OcelAccumulator do
  @moduledoc """
  OCEL event accumulation -> rust4pm engine handle. Closes the storage gap
  `BeamPM.Ocel` explicitly leaves open (lib/beam4pm_ocel.ex:17-22: "this
  module owns no storage ... A caller wanting these functions to operate
  over 'everything ever ingested' is responsible for accumulating the
  ingested `{record, relationships}` pairs itself"): THIS module is that
  accumulator -- a GenServer serializing writes into a `:protected` ETS
  set, holding decoded `BeamPM.Types.OcelEvent`/`OcelObject` records with
  their nested relationships in exactly the shape
  `BeamPM.OcelIngest.Router`'s decode returns (`{:ok, record, rels}`, see
  lib/beam4pm_ocel_ingest.ex:128-153).

  `to_engine_handle/0` replays the accumulated content through the real
  engine construction ops -- `ocel_new`, `ocel_add_event_type`/
  `ocel_add_object_type`, `ocel_add_object` (objects BEFORE events: the
  engine refuses e2o to unknown objects, native/rust4pm-wasm/src/lib.rs
  ocel_add_event arm), `ocel_add_event` -- and returns a fresh
  `ocel_handle` ready for `ocel_variants_of_object_type/3`,
  `ocel_discover_powl/3`, etc.

  ## Handle-restart invalidation law

  The engine's handles die with its Wasmex store ("A restart yields a
  fresh store and invalidates every handle", lib/beam4pm_rust4pm.ex
  moduledoc). This module therefore NEVER caches an engine handle: every
  `to_engine_handle/0` call builds a new one from the ETS content, so a
  post-restart call can only produce a valid handle. The returned handle
  is owned and freed by the caller (`BeamPM.Rust4PM.free_ocel/2`).

  Ingest is all-or-nothing per call: duplicate ids and invalid record
  kinds refuse the whole call with a typed error, never a silent partial
  write. Dangling relationships (an e2o/o2o naming an object id never
  accumulated) are NOT refused at ingest time (objects may arrive in a
  later batch); `to_engine_handle/0` refuses them at build time with
  `{:error, {:dangling_relationships, [...]}}` -- mirroring
  `BeamPM.Ocel.validate_envelope/2`'s referential-integrity semantics and
  the engine's own refusal.
  """

  use GenServer

  alias BeamPM.Rust4PM
  alias BeamPM.Types.OcelEvent
  alias BeamPM.Types.OcelObject
  alias BeamPM.Types.OcelRelationship

  @name __MODULE__
  @table __MODULE__

  # ---------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------

  @doc "Start the accumulator (idempotent under the standard name)."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, Keyword.take(opts, [:name]), name: opts[:name] || @name)
  end

  @doc """
  Ingest decoded records: `events` is a list of `{%OcelEvent{}, [%OcelRelationship{}]}`,
  `objects` a list of `{%OcelObject{}, [%OcelRelationship{}]}` -- the exact
  `{record, relationships}` shape the ingest router decodes into. Returns
  `{:ok, %{events: n, objects: n}}` (counts ingested THIS call) or
  `{:error, term()}` (whole call refused, nothing written).
  """
  @spec ingest([{OcelEvent.t(), [OcelRelationship.t()]}], [
          {OcelObject.t(), [OcelRelationship.t()]}
        ]) :: {:ok, %{events: non_neg_integer(), objects: non_neg_integer()}} | {:error, term()}
  def ingest(events, objects \\ []) when is_list(events) and is_list(objects) do
    GenServer.call(server(), {:ingest, events, objects})
  catch
    :exit, _ -> {:error, :accumulator_not_running}
  end

  @doc "All accumulated `{%OcelEvent{}, rels}` pairs, sorted by event_id."
  @spec events() :: [{OcelEvent.t(), [OcelRelationship.t()]}]
  def events do
    table()
    |> :ets.tab2list()
    |> Enum.filter(&match?({{:event, _}, _}, &1))
    |> Enum.sort_by(fn {{:event, id}, _} -> id end)
    |> Enum.map(fn {_k, pair} -> pair end)
  end

  @doc "All accumulated `{%OcelObject{}, rels}` pairs, sorted by object_id."
  @spec objects() :: [{OcelObject.t(), [OcelRelationship.t()]}]
  def objects do
    table()
    |> :ets.tab2list()
    |> Enum.filter(&match?({{:object, _}, _}, &1))
    |> Enum.sort_by(fn {{:object, id}, _} -> id end)
    |> Enum.map(fn {_k, pair} -> pair end)
  end

  @doc "Accumulated totals: %{events: n, objects: n}."
  @spec counts() :: %{events: non_neg_integer(), objects: non_neg_integer()}
  def counts do
    %{events: length(events()), objects: length(objects())}
  end

  @doc """
  Build a FRESH rust4pm OCEL handle over the accumulated content. Never
  cached -- see the moduledoc's handle-restart invalidation law. On any
  mid-build engine refusal the partially-built handle is freed and a typed
  error returned. The caller owns and frees the returned handle.
  """
  @spec to_engine_handle() :: {:ok, non_neg_integer()} | {:error, term()}
  def to_engine_handle do
    acc_events = events()
    acc_objects = objects()

    with :ok <- preflight(acc_events, acc_objects),
         :ok <- start_engine(),
         {:ok, %{"ocel_handle" => handle}} <- Rust4PM.ocel_new(),
         :ok <- declare_types(handle, acc_events, acc_objects),
         :ok <- add_objects(handle, acc_objects),
         :ok <- add_events(handle, acc_events) do
      {:ok, handle}
    else
      {:error, {:mid_build, handle, reason}} ->
        _ = Rust4PM.free_ocel(handle)
        {:error, reason}

      {:error, _} = err ->
        err
    end
  end

  @doc "Drop ALL accumulated content (typed, explicit -- never implicit)."
  @spec reset() :: :ok
  def reset do
    GenServer.call(server(), :reset)
  catch
    :exit, _ -> :ok
  end

  @doc false
  def child_spec(_arg), do: %{id: @name, start: {__MODULE__, :start_link, []}}

  # ---------------------------------------------------------------------
  # GenServer (owner of the ETS writes -- serialized)
  # ---------------------------------------------------------------------

  @impl true
  def init(_opts) do
    :ets.new(@table, [:set, :protected, :named_table, read_concurrency: true])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:ingest, events, objects}, _from, state) do
    case validate_and_stage(events, objects) do
      {:ok, staged} ->
        Enum.each(staged, fn {key, pair} -> :ets.insert(@table, {key, pair}) end)
        {:reply, {:ok, %{events: length(events), objects: length(objects)}}, state}

      {:error, _} = err ->
        {:reply, err, state}
    end
  end

  def handle_call(:reset, _from, state) do
    :ets.delete_all_objects(@table)
    {:reply, :ok, state}
  end

  defp validate_and_stage(events, objects) do
    staged =
      Enum.flat_map(events, fn
        {%OcelEvent{} = record, rels} when is_list(rels) ->
          [{{:event, record.event_id}, {record, rels}}]

        other ->
          [{:invalid, {:expected_event_with_relationships, other}}]
      end) ++
        Enum.flat_map(objects, fn
          {%OcelObject{} = record, rels} when is_list(rels) ->
            [{{:object, record.object_id}, {record, rels}}]

          other ->
            [{:invalid, {:expected_object_with_relationships, other}}]
        end)

    cond do
      bad = Enum.find(staged, &match?({:invalid, _}, &1)) ->
        {:error, elem(bad, 1)}

      missing_id = Enum.find(staged, fn {key, _} -> elem(key, 1) in [nil, ""] end) ->
        {:error, {:missing_id, elem(missing_id, 0)}}

      true ->
        dup = Enum.find(staged, fn {key, _} -> :ets.member(@table, key) end)

        case dup do
          nil -> {:ok, staged}
          {key, _} -> {:error, {:duplicate_record, key}}
        end
    end
  end

  # ---------------------------------------------------------------------
  # Engine handle construction (real ops, engine-refused never faked)
  # ---------------------------------------------------------------------

  defp preflight(acc_events, acc_objects) do
    known =
      MapSet.new(acc_objects, fn {%OcelObject{object_id: id}, _} -> id end)

    dangling =
      Enum.flat_map(acc_events, fn {%OcelEvent{event_id: eid}, rels} ->
        for %OcelRelationship{object_id: rid} <- rels,
            not MapSet.member?(known, rid),
            do: {:event, eid, rid}
      end) ++
        Enum.flat_map(acc_objects, fn {%OcelObject{object_id: oid}, rels} ->
          for %OcelRelationship{object_id: rid} <- rels,
              not MapSet.member?(known, rid),
              do: {:object, oid, rid}
        end)

    nil_qualifiers =
      Enum.flat_map(acc_events ++ acc_objects, fn {record, rels} ->
        owner = owner_id(record)

        for %OcelRelationship{object_id: rid, qualifier: q} <- rels,
            not is_binary(q),
            do: {owner, rid, q}
      end)

    cond do
      dangling != [] -> {:error, {:dangling_relationships, dangling}}
      nil_qualifiers != [] -> {:error, {:non_binary_qualifier, nil_qualifiers}}
      true -> :ok
    end
  end

  defp owner_id(%OcelEvent{event_id: id}), do: {:event, id}
  defp owner_id(%OcelObject{object_id: id}), do: {:object, id}

  defp start_engine do
    if Rust4PM.wasm_built?() do
      case Rust4PM.start() do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
        {:error, reason} -> {:error, {:engine_start_failed, reason}}
      end
    else
      {:error, :wasm_missing}
    end
  end

  defp declare_types(handle, acc_events, acc_objects) do
    event_types =
      acc_events |> Enum.map(fn {%OcelEvent{event_type: t}, _} -> t end) |> Enum.uniq() |> Enum.sort()

    object_types =
      acc_objects |> Enum.map(fn {%OcelObject{object_type: t}, _} -> t end) |> Enum.uniq() |> Enum.sort()

    with :ok <- declare_each(handle, event_types, &Rust4PM.ocel_add_event_type(handle, &1)),
         :ok <- declare_each(handle, object_types, &Rust4PM.ocel_add_object_type(handle, &1)) do
      :ok
    else
      {:error, _} = err -> err
    end
  end

  defp declare_each(_handle, [], _fun), do: :ok

  defp declare_each(handle, [type | rest], fun) do
    case fun.(type) do
      {:ok, _} -> declare_each(handle, rest, fun)
      {:error, reason} -> {:error, {:mid_build, handle, {:declare_type_failed, type, reason}}}
    end
  end

  defp add_objects(handle, acc_objects) do
    Enum.reduce_while(acc_objects, :ok, fn {%OcelObject{object_id: id, object_type: type}, rels}, :ok ->
      case Rust4PM.ocel_add_object(handle, id, type, o2o_wire(rels)) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:mid_build, handle, {:add_object_failed, id, reason}}}}
      end
    end)
  end

  defp add_events(handle, acc_events) do
    Enum.reduce_while(acc_events, :ok, fn {%OcelEvent{event_id: id, event_type: type, event_time: time}, rels}, :ok ->
      case Rust4PM.ocel_add_event(handle, id, type, time, e2o_wire(rels)) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:mid_build, handle, {:add_event_failed, id, reason}}}}
      end
    end)
  end

  # Engine wire: [object_id, qualifier] pairs (native/rust4pm-wasm
  # parse_relationships, lib.rs:435-461 -- both entries must be strings).
  # Non-binary qualifiers are refused in preflight, never silently coerced.
  defp o2o_wire(rels), do: rel_wire(rels)
  defp e2o_wire(rels), do: rel_wire(rels)

  defp rel_wire(rels) do
    Enum.map(rels, fn %OcelRelationship{object_id: object_id, qualifier: qualifier} ->
      [object_id, qualifier]
    end)
  end

  defp server, do: @name
  defp table, do: @table
end
