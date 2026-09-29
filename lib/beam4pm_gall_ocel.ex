defmodule BeamPM.GallOcel do
  @moduledoc """
  OCEL projection of the GALL Semantic Work Fabric lifecycle (v26.9.18,
  PRD §43.6): projects semantic work milestones into the repo's existing
  OCEL shapes (`BeamPM.Types.OcelEvent` + `BeamPM.Types.OcelRelationship`
  pairs, `BeamPM.Types.OcelObject` + pairs -- the exact pair convention
  consumed by `BeamPM.Ocel.object_trace/2`, `BeamPM.Ocel.validate_envelope/2`
  and `BeamPM.Ocel.encode/1`), plus a pure conformance checker for the
  permitted lifecycle order (PRD §27/§28).

  ## Observation, never subject success

  Every projected event is provenance-only. An event log records what was
  OBSERVED; it does not confer authority and it does not assert that the
  observed work succeeded. Observation, never subject success. Concretely:

    * `project/1` and `check/1` are total, pure functions over their input
      list. They mutate nothing, spawn nothing, touch no filesystem, and
      emit no messages (asserted statically by the test suite walking the
      compiled module's abstract code for `File`/`System`/`IO`/`Port`/`Mix`
      remote calls).
    * every projected event carries the fixed attribute
      `"authority" => "none"`: no event in this log is, carries, or implies
      execution authority. A lease token, an authority grant, or a brokered
      receipt path never enters this log as authority -- at most as an
      observed identifier.
    * an event named `verification_finished` records that a verification
      transition was observed, not that the subject is correct; an event
      named `checkpoint_promoted` records the observation of a promotion,
      never the promotion itself.

  ## Event vocabulary (exact names, PRD §43.6)

      checkpoint_admitted, run_created, epoch_created, worktree_provisioned,
      lease_claimed, tool_admitted, candidate_committed, lease_closed,
      verification_started, verification_finished, receipt_sealed,
      repair_created, checkpoint_promoted

  ## Object identities per event (PRD §40)

  Each observation carries the object identities applicable to its event
  type: `checkpoint`, `run`, `epoch`, `lease`, `worker`, `candidate` (the
  commit SHA itself), `verifier`, `receipt`. The admitted per-event-type
  binding is:

      checkpoint_admitted     checkpoint
      run_created             checkpoint, run
      epoch_created           run, epoch
      worktree_provisioned    epoch, worker
      lease_claimed           epoch, lease, worker
      tool_admitted           lease
      candidate_committed     lease, candidate
      lease_closed            lease, candidate
      verification_started    lease, candidate, verifier
      verification_finished   lease, candidate, verifier
      receipt_sealed          receipt, candidate
      repair_created          lease, worker
      checkpoint_promoted     checkpoint, receipt

  ## Permitted lifecycle order (PRD §27/§28, checked by `check/1`)

    * `checkpoint_admitted` before `run_created` before `epoch_created`
    * `worktree_provisioned` before `lease_claimed`
    * `lease_claimed` before `candidate_committed` before `lease_closed`
    * `verification_started` before `verification_finished` before
      `receipt_sealed`
    * `receipt_sealed` is required before `checkpoint_promoted`
    * `repair_created` may appear only after `verification_finished` and
      before a subsequent `lease_claimed` (the repair loop)

  Violations are never silent: `check/1` returns
  `{:refused, "REFUSED_CONFORMANCE", violating_event_name, expected_before_name}`
  with the exact event-name strings.

  ## Determinism

  `project/1` is a pure function of its input: same trace in, structurally
  identical projection out (event ids are derived from the trace position
  and event name, never from the clock or any process dictionary; object
  enumeration follows the canonical object-type order above with
  lexicographic id sort). Timestamps are caller-supplied, never sampled.
  """

  alias BeamPM.Types.OcelEvent
  alias BeamPM.Types.OcelObject
  alias BeamPM.Types.OcelRelationship

  @event_atoms [
    :checkpoint_admitted,
    :run_created,
    :epoch_created,
    :worktree_provisioned,
    :lease_claimed,
    :tool_admitted,
    :candidate_committed,
    :lease_closed,
    :verification_started,
    :verification_finished,
    :receipt_sealed,
    :repair_created,
    :checkpoint_promoted
  ]

  @object_types [:checkpoint, :run, :epoch, :lease, :worker, :candidate, :verifier, :receipt]

  @required_objects %{
    checkpoint_admitted: [:checkpoint],
    run_created: [:checkpoint, :run],
    epoch_created: [:run, :epoch],
    worktree_provisioned: [:epoch, :worker],
    lease_claimed: [:epoch, :lease, :worker],
    tool_admitted: [:lease],
    candidate_committed: [:lease, :candidate],
    lease_closed: [:lease, :candidate],
    verification_started: [:lease, :candidate, :verifier],
    verification_finished: [:lease, :candidate, :verifier],
    receipt_sealed: [:receipt, :candidate],
    repair_created: [:lease, :worker],
    checkpoint_promoted: [:checkpoint, :receipt]
  }

  # Direct prerequisites; transitive precedence falls out of the seen-set
  # walk in check_names/1 (each event's own prerequisite was itself checked
  # when it appeared).
  @prerequisites %{
    checkpoint_admitted: [],
    run_created: [:checkpoint_admitted],
    epoch_created: [:run_created],
    worktree_provisioned: [:epoch_created],
    lease_claimed: [:worktree_provisioned],
    tool_admitted: [:lease_claimed],
    candidate_committed: [:lease_claimed],
    lease_closed: [:candidate_committed],
    verification_started: [:lease_closed],
    verification_finished: [:verification_started],
    receipt_sealed: [:verification_finished],
    repair_created: [],
    checkpoint_promoted: [:receipt_sealed]
  }

  @typedoc "One observed milestone: name plus caller-supplied time and object identities."
  @type observation :: %{
          required(:name) => atom() | String.t(),
          optional(:time) => String.t(),
          optional(:objects) => map()
        }

  @typedoc "A refusal of a non-conforming trace, with exact event-name strings."
  @type refusal :: {:refused, String.t(), String.t(), String.t()}

  @doc """
  The exact GALL lifecycle event vocabulary, in lifecycle order, as the
  exact name strings used in projected `event_type`s and in refusals.
  """
  @spec event_names() :: [String.t()]
  def event_names, do: Enum.map(@event_atoms, &Atom.to_string/1)

  @doc """
  The PRD §40 object types carried by projected events and objects:
  `checkpoint`, `run`, `epoch`, `lease`, `worker`, `candidate` (commit SHA),
  `verifier`, `receipt`.
  """
  @spec object_types() :: [String.t()]
  def object_types, do: Enum.map(@object_types, &Atom.to_string/1)

  @doc """
  The admitted per-event-type object-identity binding (see the moduledoc
  table): event name string -> object type strings, in canonical order.
  """
  @spec required_objects() :: %{String.t() => [String.t()]}
  def required_objects do
    Map.new(@required_objects, fn {name, types} ->
      {Atom.to_string(name), Enum.map(types, &Atom.to_string/1)}
    end)
  end

  @doc """
  Project an ordered list of observed milestones into the repo's existing
  OCEL shapes: `{:ok, %{events: [{OcelEvent, [OcelRelationship]}],
  objects: [{OcelObject, [OcelRelationship]}]}}`.

  The returned pairs are the exact convention consumed by
  `BeamPM.Ocel.object_trace/2`, `BeamPM.Ocel.validate_envelope/2` and
  `BeamPM.Ocel.encode/1` (see `encode/1`). Each event's E2O relationships
  bind the applicable PRD §40 object identities with the object type as
  qualifier; each event's fixed `attributes` are
  `%{"authority" => "none", "provenance" => "observation_only"}`.

  Pure and deterministic: no clock reads, no mutation, no side effects.
  Projection does NOT judge conformance -- a log records what was observed,
  including out-of-order observations; run `check/1` for the conformance
  judgment.

  Refusals (never silent):

    * `{:error, {:invalid_trace_element, element}}` -- not a name-carrying map
    * `{:error, {:unknown_event, name}}` -- outside the closed vocabulary
    * `{:error, {:missing_time, name}}` / `{:error, {:time_not_binary, name, v}}`
    * `{:error, {:missing_object_identity, name, object_type}}` -- a required
      PRD §40 identity absent from the observation
    * `{:error, {:inapplicable_object_identity, name, object_type}}` -- an
      object type not admitted for this event type
    * `{:error, {:object_identity_not_binary, name, object_type}}`
  """
  @spec project([observation()]) ::
          {:ok, %{:events => [{OcelEvent.t(), [OcelRelationship.t()]}],
                 :objects => [{OcelObject.t(), [OcelRelationship.t()]}]}}
          | {:error, term()}
  def project(trace) when is_list(trace) do
    with {:ok, observations} <- normalize_trace(trace) do
      events_with_rels =
        observations
        |> Enum.with_index(1)
        |> Enum.map(fn {observation, index} -> build_event(observation, index) end)

      {:ok, %{events: events_with_rels, objects: build_objects(observations)}}
    end
  end

  @doc """
  Pure conformance judgment of an ordered event trace against the permitted
  GALL lifecycle order (PRD §27/§28 -- see the moduledoc). Returns `:ok`,
  or `{:refused, "REFUSED_CONFORMANCE", violating_event_name,
  expected_before_name}` with the exact name strings, or
  `{:error, {:unknown_event, name}}`. Never silent, never raising on
  non-conforming input.
  """
  @spec check([observation() | atom() | String.t()]) ::
          :ok | refusal() | {:error, term()}
  def check(trace) when is_list(trace) do
    names =
      Enum.reduce_while(trace, {:ok, []}, fn element, {:ok, acc} ->
        case observation_name(element) do
          {:ok, name} -> {:cont, {:ok, [name | acc]}}
          {:error, _} = error -> {:halt, error}
        end
      end)

    with {:ok, names} <- names, do: check_names(Enum.reverse(names))
  end

  @doc """
  Encode a projection from `project/1` into the repo's existing OCEL 2.0
  JSON envelope by delegating to `BeamPM.Ocel.encode/1`
  (`{"objectTypes": [...], "eventTypes": [...], "objects": [...],
  "events": [...]}`). beam4pm already owns an OCEL exporter, so this module
  adds no second wire shape. The E2O/O2O relationship pairs remain
  first-class on the `project/1` return value for
  `BeamPM.Ocel.validate_envelope/2` / `BeamPM.Ocel.object_trace/2`.
  """
  @spec encode(%{:events => [{OcelEvent.t(), [OcelRelationship.t()]}],
                 :objects => [{OcelObject.t(), [OcelRelationship.t()]}]}) ::
          {:ok, String.t()} | {:error, term()}
  def encode(%{events: events_with_rels, objects: objects_with_rels}) do
    BeamPM.Ocel.encode(
      events: Enum.map(events_with_rels, &elem(&1, 0)),
      objects: Enum.map(objects_with_rels, &elem(&1, 0))
    )
  end

  ## Trace normalization (pure; typed refusals, never silent)

  defp normalize_trace(trace) do
    Enum.reduce_while(trace, {:ok, []}, fn element, {:ok, acc} ->
      case normalize_observation(element) do
        {:ok, observation} -> {:cont, {:ok, [observation | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, observations} -> {:ok, Enum.reverse(observations)}
      error -> error
    end
  end

  defp normalize_observation(%{name: raw_name} = element) do
    with {:ok, name} <- event_atom(raw_name),
         {:ok, objects} <- normalize_objects(name, Map.get(element, :objects, %{})),
         {:ok, time} <- normalize_time(name, Map.get(element, :time)) do
      {:ok, %{name: name, time: time, objects: objects}}
    end
  end

  defp normalize_observation(other), do: {:error, {:invalid_trace_element, other}}

  defp observation_name(%{name: raw_name}), do: event_atom(raw_name)
  defp observation_name(%{}), do: {:error, {:invalid_trace_element, %{}}}
  defp observation_name(element), do: event_atom(element)

  defp event_atom(name) when is_atom(name) do
    if name in @event_atoms, do: {:ok, name}, else: {:error, {:unknown_event, name}}
  end

  defp event_atom(name) when is_binary(name) do
    case safe_existing_atom(name) do
      {:ok, atom} -> event_atom(atom)
      :unknown -> {:error, {:unknown_event, name}}
    end
  end

  defp event_atom(other), do: {:error, {:unknown_event, other}}

  defp safe_existing_atom(name) do
    {:ok, String.to_existing_atom(name)}
  rescue
    ArgumentError -> :unknown
  end

  defp normalize_objects(name, objects) when is_map(objects) do
    required = Map.fetch!(@required_objects, name)

    inapplicable =
      Enum.find(objects, fn {type, _} -> type not in required or type not in @object_types end)

    cond do
      inapplicable != nil ->
        {:error, {:inapplicable_object_identity, name, elem(inapplicable, 0)}}

      true ->
        case Enum.find(required, fn type -> not Map.has_key?(objects, type) end) do
          nil ->
            non_binary =
              Enum.find(required, fn type -> not is_binary(Map.fetch!(objects, type)) end)

            if non_binary,
              do: {:error, {:object_identity_not_binary, name, non_binary}},
              else: {:ok, objects}

          missing ->
            {:error, {:missing_object_identity, name, missing}}
        end
    end
  end

  defp normalize_objects(name, objects), do: {:error, {:objects_not_map, name, objects}}

  defp normalize_time(_name, time) when is_binary(time), do: {:ok, time}
  defp normalize_time(name, nil), do: {:error, {:missing_time, name}}
  defp normalize_time(name, other), do: {:error, {:time_not_binary, name, other}}

  ## Event building (deterministic: index-derived ids, canonical order)

  defp build_event(%{name: name, time: time, objects: objects}, index) do
    {:ok, event} =
      OcelEvent.new(%{
        event_id: event_id(name, index),
        event_type: Atom.to_string(name),
        event_time: time,
        attributes: %{"authority" => "none", "provenance" => "observation_only"}
      })

    relationships =
      objects
      |> Map.take(@object_types)
      |> Enum.map(fn {type, object_id} ->
        {:ok, rel} = OcelRelationship.new(%{qualifier: Atom.to_string(type), object_id: object_id})
        rel
      end)

    {event, relationships}
  end

  defp event_id(name, index) do
    "gall-" <> String.pad_leading(Integer.to_string(index), 4, "0") <> "-" <> Atom.to_string(name)
  end

  defp build_objects(observations) do
    Enum.flat_map(@object_types, fn type ->
      observations
      |> Enum.flat_map(fn %{objects: objects} ->
        case Map.fetch(objects, type) do
          {:ok, id} -> [id]
          :error -> []
        end
      end)
      |> Enum.sort()
      |> Enum.uniq()
      |> Enum.map(fn object_id ->
        {:ok, object} =
          OcelObject.new(%{object_id: object_id, object_type: Atom.to_string(type)})

        {object, []}
      end)
    end)
  end

  ## Conformance walk (seen-set precedence + repair-window rule)

  defp check_names(names) do
    {_seen, _window, verdict} =
      Enum.reduce_while(names, {MapSet.new(), false, :ok}, fn name, {seen, window, _} ->
        case violation(name, seen, window) do
          nil -> {:cont, {MapSet.put(seen, name), transition(name, window), :ok}}
          refusal -> {:halt, {seen, window, refusal}}
        end
      end)

    verdict
  end

  defp violation(:repair_created = name, seen, window) do
    if window,
      do: prerequisite_violation(name, seen),
      else: {:refused, "REFUSED_CONFORMANCE", "repair_created", "verification_finished"}
  end

  defp violation(name, seen, _window), do: prerequisite_violation(name, seen)

  defp prerequisite_violation(name, seen) do
    case Enum.find(Map.fetch!(@prerequisites, name), fn prereq ->
           not MapSet.member?(seen, prereq)
         end) do
      nil -> nil
      missing -> {:refused, "REFUSED_CONFORMANCE", Atom.to_string(name), Atom.to_string(missing)}
    end
  end

  # `repair_created` may appear only after a `verification_finished` and
  # before a subsequent `lease_claimed` (PRD §28 repair loop): the window
  # opens on `verification_finished` and closes on the next `lease_claimed`.
  defp transition(:verification_finished, _window), do: true
  defp transition(:lease_claimed, _window), do: false
  defp transition(_name, window), do: window
end
