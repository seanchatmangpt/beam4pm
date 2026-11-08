defmodule BeamPM.OcelLogIngest do
  @moduledoc """
  `POST /api/ocel/ingest` -- whole-log OCEL 2.0 ingestion endpoint, shaped
  on the wasm4pm-compat `WasmOcelLogSchema` (zod) wire keys:

      {
        "events":       [{id, type, time, attributes?, relationships?}],
        "objectTypes":  [{name, attributes?}],
        "eventTypes":   [{name, attributes?}],
        "objects":      [{id, type, attributes?}]
      }

  Each event carries `id`/`type`/`time` (number) and may carry
  `relationships` (`{objectId, qualifier}`), per WasmOcelEventSchema.
  Accepted logs are persisted whole (ETS via `BeamPM.OcelLogStore`) and the
  endpoint returns `201 {"accepted": N, "log_id": id}`. A malformed log is
  refused fail-closed with `422` and a per-item error list -- nothing is
  persisted on any validation failure.

  Hand-authored (HTTP-mount wiring, same manufacturing-input class as
  `beam4pm_application.ex`). Complements, never replaces, the generated
  `BeamPM.OcelIngest.Router` (`/ocel/events`, `/ocel/objects` on port
  4210): this router serves a distinct mount (`/api/ocel/ingest`).
  """

  use Plug.Router
  alias BeamPM.OcelLogStore

  plug(Plug.Parsers, parsers: [:json], json_decoder: JSON, pass: ["application/json"])
  plug(:match)
  plug(:dispatch)

  post("/api/ocel/ingest") do
    case validate_log(conn.body_params) do
      {:ok, log} ->
        log_id = OcelLogStore.put(log)

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          201,
          JSON.encode!(%{"accepted" => length(log["events"]), "log_id" => log_id})
        )

      {:error, errors} ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(422, JSON.encode!(%{"accepted" => 0, "errors" => errors}))
    end
  end

  match(_) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(404, JSON.encode!(%{"error" => "route_not_admitted"}))
  end

  # -- Validation (fail-closed: first error list wins, nothing persisted) ----

  @required_log_keys ["events", "objectTypes", "eventTypes", "objects"]

  defp validate_log(%{} = body) do
    missing = for k <- @required_log_keys, not Map.has_key?(body, k), do: "missing_key:#{k}"

    cond do
      missing != [] ->
        {:error, missing}

      true ->
        with :ok <- validate_list(body, "eventTypes"),
             :ok <- validate_list(body, "objectTypes"),
             :ok <- validate_list(body, "objects"),
             :ok <- validate_list(body, "events") do
          {:ok, body}
        end
    end
  end

  defp validate_log(_), do: {:error, ["expected a JSON object OCEL 2.0 log"]}

  defp validate_list(body, "eventTypes"),
    do: validate_items(body["eventTypes"], &validate_event_type/1, "eventTypes")

  defp validate_list(body, "objectTypes"),
    do: validate_items(body["objectTypes"], &validate_object_type/1, "objectTypes")

  defp validate_list(body, "objects"),
    do: validate_items(body["objects"], &validate_object/1, "objects")

  defp validate_list(body, "events"),
    do: validate_items(body["events"], &validate_event/1, "events")

  defp validate_items(items, validator, key) when is_list(items) do
    errors =
      items
      |> Enum.with_index()
      |> Enum.flat_map(fn {item, i} -> validator.(item) |> with_index(key, i) end)

    if errors == [], do: :ok, else: {:error, errors}
  end

  defp validate_items(_, _, key), do: {:error, ["#{key}:expected_array"]}

  defp with_index(:ok, _, _), do: []
  defp with_index(errors, key, i) when is_list(errors), do: Enum.map(errors, &"#{key}[#{i}]:#{&1}")

  # events: id/type/time required, time a number, relationships each
  # {objectId, qualifier} strings (wasm4pm-compat OcelRelationshipSchema).
  defp validate_event(%{} = e) do
    errors =
      for {k, pred} <- [
            {"id", &is_binary/1},
            {"type", &is_binary/1},
            {"time", &is_number/1}
          ],
          # sentinel default: a nil filter result would skip the item and
          # silently accept a missing key (fail-open)
          v = Map.get(e, k, :__missing__),
          not pred.(v),
          into: [],
          do: "missing_or_invalid:#{k}"

    errors =
      errors ++
        case Map.get(e, "relationships") do
          nil -> []
          rels when is_list(rels) -> Enum.flat_map(rels, &validate_relationship/1)
          _ -> ["missing_or_invalid:relationships"]
        end

    errors
  end

  defp validate_event(_), do: ["not_an_object"]

  defp validate_relationship(%{"objectId" => oid, "qualifier" => q})
       when is_binary(oid) and is_binary(q),
       do: []

  defp validate_relationship(_), do: ["invalid_relationship"]

  # objects: id/type required strings.
  defp validate_object(%{"id" => id, "type" => t}) when is_binary(id) and is_binary(t),
    do: []

  defp validate_object(_), do: ["missing_or_invalid:id_or_type"]

  # eventTypes/objectTypes: name required string.
  defp validate_event_type(%{"name" => n}) when is_binary(n), do: []
  defp validate_event_type(_), do: ["missing_or_invalid:name"]

  defp validate_object_type(%{"name" => n}) when is_binary(n), do: []
  defp validate_object_type(_), do: ["missing_or_invalid:name"]
end
