defmodule BeamPM.Ocel do
  @moduledoc """
  Hand-authored general OCEL 2.0 JSON encode/decode pair.

  Admitted `bpm:HandAuthoredSource` individual: `lib/beam4pm_ocel.ex` (see
  `docs/jira/` roadmap gap — "today real OCEL 2.0 encode/decode only exists
  inside the RF3 Rust oracle via two fixed wire ops, not a general encode/1
  decode/1 pair"). Built entirely on top of the existing generated
  `BeamPM.Types.OcelEvent` / `BeamPM.Types.OcelObject` structs and the
  existing generated `BeamPM.Codec.to_map/1` / `from_map/2` — no generated
  file is modified.
  """

  @spec encode(events: [BeamPM.Types.OcelEvent.t()], objects: [BeamPM.Types.OcelObject.t()]) ::
          {:ok, String.t()} | {:error, term()}
  def encode(opts) when is_list(opts) do
    events = Keyword.get(opts, :events, [])
    objects = Keyword.get(opts, :objects, [])

    with true <- Enum.all?(events, &match?(%BeamPM.Types.OcelEvent{}, &1)),
         true <- Enum.all?(objects, &match?(%BeamPM.Types.OcelObject{}, &1)) do
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

  @spec decode(String.t()) ::
          {:ok, %{events: [BeamPM.Types.OcelEvent.t()], objects: [BeamPM.Types.OcelObject.t()]}}
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
