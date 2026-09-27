defmodule BeamPM.LegacyEquivalence do
  @moduledoc """
  Bounded behavioral equivalence court for legacy-system reconstitution.

  The court compares admitted observable event projections, not implementation
  identity. It emits a deterministic, machine-readable report suitable for
  ggen-legacy admission and XaaS repair sensing.

  This module has no DO surface. A conformant report is evidence about the
  supplied observations only; it does not authorize release or predecessor
  retirement.
  """

  @schema "beam4pm-legacy-equivalence/1"
  @default_fields ["event_type", "objects", "outcome", "side_effects"]

  @type event :: map()
  @type report :: map()

  @doc "Return the wire schema emitted by compare/4."
  @spec schema() :: String.t()
  def schema, do: @schema

  @doc """
  Compare legacy and candidate observations for one exact subject.

  Options:

    * :fields - observable fields to compare.
    * :order_sensitive - preserve event ordering; defaults true.
    * :legacy_identity / :candidate_identity - externally supplied identities.

  Unknown event fields are deliberately ignored: source paths, function names,
  framework details and other implementation identity are not semantic
  differences unless explicitly admitted through :fields.
  """
  @spec compare(String.t(), [event()], [event()], keyword()) ::
          {:ok, report()} | {:error, term()}
  def compare(subject, legacy_events, candidate_events, opts \\ [])
      when is_binary(subject) and is_list(legacy_events) and is_list(candidate_events) do
    fields = opts |> Keyword.get(:fields, @default_fields) |> Enum.map(&to_string/1)
    order_sensitive = Keyword.get(opts, :order_sensitive, true)

    with :ok <- admit_subject(subject),
         :ok <- admit_fields(fields),
         {:ok, legacy} <- project_events(legacy_events, fields),
         {:ok, candidate} <- project_events(candidate_events, fields) do
      legacy_cmp = comparable(legacy, order_sensitive)
      candidate_cmp = comparable(candidate, order_sensitive)
      equivalent = legacy_cmp == candidate_cmp
      counterexamples = if equivalent, do: [], else: counterexamples(legacy_cmp, candidate_cmp)

      legacy_identity =
        Keyword.get(opts, :legacy_identity) || digest(%{"events" => legacy_cmp})

      candidate_identity =
        Keyword.get(opts, :candidate_identity) || digest(%{"events" => candidate_cmp})

      receipt_preimage = %{
        "schema" => @schema,
        "subject" => subject,
        "fields" => fields,
        "order_sensitive" => order_sensitive,
        "legacy_identity" => legacy_identity,
        "candidate_identity" => candidate_identity,
        "legacy" => legacy_cmp,
        "candidate" => candidate_cmp
      }

      {:ok,
       %{
         "schema" => @schema,
         "subject" => subject,
         "legacy_identity" => legacy_identity,
         "candidate_identity" => candidate_identity,
         "fields" => fields,
         "order_sensitive" => order_sensitive,
         "verdict" => if(equivalent, do: "EQUIVALENT", else: "COUNTEREXAMPLE"),
         "equivalent" => equivalent,
         "counterexamples" => counterexamples,
         "receipt_digest" => digest(receipt_preimage),
         "authority_ceiling" => "OBSERVE"
       }}
    end
  end

  def compare(subject, _legacy, _candidate, _opts) when not is_binary(subject),
    do: {:error, :subject_not_a_string}

  def compare(_subject, _legacy, _candidate, _opts), do: {:error, :events_not_lists}

  defp admit_subject(subject) do
    if String.trim(subject) == "", do: {:error, :empty_subject}, else: :ok
  end

  defp admit_fields([]), do: {:error, :no_observable_fields}

  defp admit_fields(fields) do
    if Enum.all?(fields, &(is_binary(&1) and String.trim(&1) != "")),
      do: :ok,
      else: {:error, :invalid_observable_field}
  end

  defp project_events(events, fields) do
    events
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {event, index}, {:ok, acc} ->
      case project_event(event, fields) do
        {:ok, projected} -> {:cont, {:ok, [projected | acc]}}
        {:error, reason} -> {:halt, {:error, {:invalid_event, index, reason}}}
      end
    end)
    |> case do
      {:ok, projected} -> {:ok, Enum.reverse(projected)}
      error -> error
    end
  end

  defp project_event(event, fields) when is_map(event) do
    canonical = canonical_event(event)

    if Map.get(canonical, "event_type") in [nil, ""] do
      {:error, :missing_event_type}
    else
      {:ok, Map.take(canonical, fields)}
    end
  end

  defp project_event(_event, _fields), do: {:error, :event_not_a_map}

  defp canonical_event(event) do
    %{
      "event_type" => first(event, ["event_type", :event_type, "type", :type, "activity", :activity]),
      "objects" =>
        event
        |> first(["objects", :objects, "object_ids", :object_ids, "omap", :omap])
        |> normalize_set(),
      "outcome" => first(event, ["outcome", :outcome, "result", :result]),
      "side_effects" =>
        event
        |> first(["side_effects", :side_effects, "effects", :effects])
        |> normalize_set()
    }
    |> Map.new(fn {key, value} -> {key, normalize(value)} end)
  end

  defp first(map, keys), do: Enum.find_value(keys, &Map.get(map, &1))

  defp normalize_set(nil), do: []
  defp normalize_set(value) when is_list(value), do: value |> Enum.map(&normalize/1) |> Enum.sort()
  defp normalize_set(value), do: [normalize(value)]

  defp normalize(value) when is_map(value) do
    value
    |> Enum.map(fn {k, v} -> {to_string(k), normalize(v)} end)
    |> Enum.sort()
    |> Map.new()
  end

  defp normalize(value) when is_list(value), do: Enum.map(value, &normalize/1)
  defp normalize(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize(value), do: value

  defp comparable(events, true), do: events
  defp comparable(events, false), do: Enum.sort_by(events, &canonical_json/1)

  defp counterexamples(left, right) do
    max_len = max(length(left), length(right))

    if max_len == 0 do
      []
    else
      0..(max_len - 1)
      |> Enum.flat_map(fn index ->
        l = Enum.at(left, index, :missing)
        r = Enum.at(right, index, :missing)

        if l == r do
          []
        else
          [
            %{
              "index" => index,
              "legacy" => wire_value(l),
              "candidate" => wire_value(r),
              "falsifier" => "make candidate projection equal legacy projection at this index"
            }
          ]
        end
      end)
    end
  end

  defp wire_value(:missing), do: %{"missing" => true}
  defp wire_value(value), do: value

  defp digest(value) do
    :crypto.hash(:sha256, canonical_json(value))
    |> Base.encode16(case: :lower)
  end

  defp canonical_json(value) when is_map(value) do
    body =
      value
      |> Enum.map(fn {k, v} -> {to_string(k), v} end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map_join(",", fn {k, v} -> Jason.encode!(k) <> ":" <> canonical_json(v) end)

    "{" <> body <> "}"
  end

  defp canonical_json(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"

  defp canonical_json(value) when is_atom(value), do: Jason.encode!(Atom.to_string(value))
  defp canonical_json(value), do: Jason.encode!(value)
end
