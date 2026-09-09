defmodule BeamPM.Ocel do
  @moduledoc """
  Real OCEL 2.0 object-centric query functions over already-ingested
  `BeamPM.Types.OcelEvent`/`OcelObject`/`OcelRelationship`/`OcelAttribute`
  structs (see `lib/beam4pm_ocel_ingest.ex` for how events/objects and their
  nested relationships are decoded off the wire), plus a hand-authored
  general OCEL 2.0 JSON `encode/1`/`decode/1` pair.

  Not ggen-generated: this is hand-written computation OVER already-admitted
  data shapes (same convention as `BeamPM.Petgraph`/`BeamPM.Tract` -- a
  wrapper/algorithm module, not a projection of the ontology graph itself),
  since none of these functions are admission-fact-driven the way
  `BeamPM.OcelIngest.Router` or `BeamPM.Actuation` are.

  The query functions (`object_trace/2`, `attribute_history/1`,
  `relationships_for/2`, `validate_envelope/2`) take plain lists the caller
  assembles -- this module owns no storage/persistence of its own (matching
  `BeamPM.OcelIngest.Router`, which also does not persist). A caller wanting
  these functions to operate over "everything ever ingested" is responsible
  for accumulating the ingested `{record, relationships}` pairs itself (e.g.
  in an Ash resource, ETS table, or its own process state) and passing them
  in.

  `encode/1`/`decode/1` close a separate roadmap gap (see `docs/jira/`
  roadmap gap -- "today real OCEL 2.0 encode/decode only exists inside the
  RF3 Rust oracle via two fixed wire ops, not a general encode/1 decode/1
  pair"). Built entirely on top of the existing generated
  `BeamPM.Types.OcelEvent` / `BeamPM.Types.OcelObject` structs and the
  existing generated `BeamPM.Codec.to_map/1` / `from_map/2` -- no generated
  file is modified.
  """

  alias BeamPM.Types.OcelAttribute
  alias BeamPM.Types.OcelEvent
  alias BeamPM.Types.OcelObject
  alias BeamPM.Types.OcelRelationship

  @typedoc "One decoded event paired with its own nested E2O relationships."
  @type event_with_rels :: {OcelEvent.t(), [OcelRelationship.t()]}

  @typedoc "One decoded object paired with its own nested O2O relationships."
  @type object_with_rels :: {OcelObject.t(), [OcelRelationship.t()]}

  @doc """
  The time-ordered (by `event_time`, ties broken by `event_id`) sequence of
  events touching one object id -- an event "touches" the object when the
  object id appears among that event's own nested E2O relationships'
  `object_id`s. Events with no relationship to `object_id` are excluded.
  """
  @spec object_trace([event_with_rels()], String.t()) :: [OcelEvent.t()]
  def object_trace(events_with_rels, object_id)
      when is_list(events_with_rels) and is_binary(object_id) do
    events_with_rels
    |> Enum.filter(fn {_event, rels} ->
      Enum.any?(rels, fn %OcelRelationship{object_id: rid} -> rid == object_id end)
    end)
    |> Enum.map(fn {event, _rels} -> event end)
    |> Enum.sort_by(&{&1.event_time, &1.event_id})
  end

  @doc """
  Chronological (by `recorded_at`) history of one object's one dynamic
  attribute, given the real `BeamPM.Types.OcelAttribute` records observed
  for it. Ties broken by insertion order (a stable sort) since two
  attribute changes recorded at the identical timestamp have no further
  admitted ordering signal.
  """
  @spec attribute_history([OcelAttribute.t()]) :: [OcelAttribute.t()]
  def attribute_history(attribute_records) when is_list(attribute_records) do
    Enum.sort_by(attribute_records, & &1.recorded_at)
  end

  @doc """
  Every relationship (from any event's E2O list or any object's O2O list)
  touching one object id -- `object_id` itself as the relationship
  TARGET, not the owner (an owner-side qualifier is available from the
  caller's own owning event/object, not reconstructed here since
  `OcelRelationship` carries no back-reference to its owner by design --
  see the ingestion router's own note on this admitted shape).
  """
  @spec relationships_for([event_with_rels() | object_with_rels()], String.t()) :: [
          OcelRelationship.t()
        ]
  def relationships_for(owners_with_rels, object_id)
      when is_list(owners_with_rels) and is_binary(object_id) do
    owners_with_rels
    |> Enum.flat_map(fn {_owner, rels} -> rels end)
    |> Enum.filter(fn %OcelRelationship{object_id: rid} -> rid == object_id end)
  end

  @doc """
  Real whole-envelope validation: checks every event's and every object's
  own nested relationships for referential integrity against the real set
  of objects actually present in this same envelope (an `OcelRelationship`
  whose `object_id` names no object in `known_object_ids` is a dangling
  reference). Returns `:ok` or `{:error, {:dangling_relationships,
  [{owner_kind, owner_id, dangling_object_id}]}}` -- never a silent drop.
  """
  @spec validate_envelope([event_with_rels()], [object_with_rels()]) ::
          :ok | {:error, {:dangling_relationships, [{atom(), String.t(), String.t()}]}}
  def validate_envelope(events_with_rels, objects_with_rels)
      when is_list(events_with_rels) and is_list(objects_with_rels) do
    known_object_ids =
      objects_with_rels
      |> Enum.map(fn {%OcelObject{object_id: id}, _rels} -> id end)
      |> MapSet.new()

    event_dangling =
      Enum.flat_map(events_with_rels, fn {%OcelEvent{event_id: eid}, rels} ->
        dangling_for(:event, eid, rels, known_object_ids)
      end)

    object_dangling =
      Enum.flat_map(objects_with_rels, fn {%OcelObject{object_id: oid}, rels} ->
        dangling_for(:object, oid, rels, known_object_ids)
      end)

    case event_dangling ++ object_dangling do
      [] -> :ok
      dangling -> {:error, {:dangling_relationships, dangling}}
    end
  end

  defp dangling_for(owner_kind, owner_id, rels, known_object_ids) do
    rels
    |> Enum.reject(fn %OcelRelationship{object_id: rid} -> MapSet.member?(known_object_ids, rid) end)
    |> Enum.map(fn %OcelRelationship{object_id: rid} -> {owner_kind, owner_id, rid} end)
  end

  @doc """
  Encode a set of already-decoded events/objects into a general OCEL 2.0
  JSON envelope (`{"objectTypes": [...], "eventTypes": [...], "objects":
  [...], "events": [...]}`), using the existing generated
  `BeamPM.Codec.to_map/1` for each record.
  """
  @spec encode(events: [OcelEvent.t()], objects: [OcelObject.t()]) ::
          {:ok, String.t()} | {:error, term()}
  def encode(opts) when is_list(opts) do
    events = Keyword.get(opts, :events, [])
    objects = Keyword.get(opts, :objects, [])

    with true <- Enum.all?(events, &match?(%OcelEvent{}, &1)),
         true <- Enum.all?(objects, &match?(%OcelObject{}, &1)) do
      envelope = %{
        "objectTypes" => objects |> Enum.map(& &1.object_type) |> Enum.uniq() |> object_type_defs(),
        "eventTypes" => events |> Enum.map(& &1.event_type) |> Enum.uniq() |> event_type_defs(),
        "objects" => Enum.map(objects, &BeamPM.Codec.to_map/1),
        "events" => Enum.map(events, &BeamPM.Codec.to_map/1)
      }

      {:ok, JSON.encode!(envelope)}
    else
      false -> {:error, {:invalid_input, :expected_ocel_event_and_ocel_object_structs}}
    end
  end

  @doc """
  Decode a general OCEL 2.0 JSON envelope (as produced by `encode/1`) back
  into `{:ok, %{events: [...], objects: [...]}}`, using the existing
  generated `BeamPM.Codec.from_map/2` for each record.
  """
  @spec decode(String.t()) ::
          {:ok, %{events: [OcelEvent.t()], objects: [OcelObject.t()]}}
          | {:error, term()}
  def decode(json) when is_binary(json) do
    with %{"events" => raw_events, "objects" => raw_objects} <- JSON.decode!(json) do
      with {:ok, events} <- decode_all(raw_events, :ocel_event),
           {:ok, objects} <- decode_all(raw_objects, :ocel_object) do
        {:ok, %{events: events, objects: objects}}
      end
    else
      _ -> {:error, {:invalid_envelope, :missing_events_or_objects}}
    end
  rescue
    e -> {:error, {:decode_failed, Exception.message(e)}}
  end

  defp decode_all(items, record_kind) when is_list(items) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
      case BeamPM.Codec.from_map(record_kind, item) do
        {:ok, record} -> {:cont, {:ok, [record | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      err -> err
    end
  end

  defp object_type_defs(object_types) do
    Enum.map(object_types, fn type -> %{"name" => type, "attributes" => []} end)
  end

  defp event_type_defs(event_types) do
    Enum.map(event_types, fn type -> %{"name" => type, "attributes" => []} end)
  end
end
