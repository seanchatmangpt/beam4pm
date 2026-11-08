defmodule BeamPM.OcelLogIngestTest do
  @moduledoc """
  Chicago controller tests for `POST /api/ocel/ingest`: a REAL wasm4pm-compat
  `WasmOcelLogSchema`-shaped log fixture posted through the real Plug router,
  and a malformed log refused 422 with per-item errors (fail-closed, nothing
  persisted). Runs against the real ETS store (async: false -- shared table).
  """

  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias BeamPM.OcelLogIngest
  alias BeamPM.OcelLogStore

  @path "/api/ocel/ingest"

  # Real fixture built from the wasm4pm-compat WasmOcelLogSchema keys
  # (wasm4pm packages/contracts/src/compat-schemas.ts): events[]/objectTypes[]/
  # eventTypes[]/objects[], event {id, type, time, relationships:[{objectId,
  # qualifier}]}, object {id, type, attributes}, type {name, attributes}.
  defp valid_log do
    %{
      "eventTypes" => [%{"name" => "Create Order", "attributes" => []}],
      "objectTypes" => [%{"name" => "Order", "attributes" => []}],
      "events" => [
        %{
          "id" => "e-1",
          "type" => "Create Order",
          "time" => 1_766_200_000.0,
          "relationships" => [%{"objectId" => "o-1", "qualifier" => "Order"}]
        },
        %{
          "id" => "e-2",
          "type" => "Ship Order",
          "time" => 1_766_200_060.0,
          "relationships" => []
        }
      ],
      "objects" => [
        %{"id" => "o-1", "type" => "Order", "attributes" => [%{"name" => "cost", "value" => 120}]}
      ]
    }
  end

  defp post_log(body) do
    conn(:post, @path, JSON.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> OcelLogIngest.call(OcelLogIngest.init([]))
  end

  test "post /api/ocel/ingest accepts a real WasmOcelLogSchema-shaped log" do
    conn = post_log(valid_log())

    assert conn.status == 201
    resp = JSON.decode!(conn.resp_body)
    assert resp["accepted"] == 2
    assert is_binary(resp["log_id"]) and resp["log_id"] != ""

    # Chicago: assert real persisted state, not the response alone.
    assert {:ok, persisted} = OcelLogStore.get(resp["log_id"])
    assert length(persisted["events"]) == 2
    assert hd(persisted["events"])["id"] == "e-1"
  end

  test "post /api/ocel/ingest refuses a malformed log with per-item errors (422)" do
    before = OcelLogStore.count()
    log = valid_log()

    # an event missing `time` entirely
    malformed =
      log
      |> Map.put("events", [
        Enum.at(log["events"], 0),
        %{"id" => "e-bad", "type" => "Ship Order"}
      ])

    conn = post_log(malformed)

    assert conn.status == 422
    resp = JSON.decode!(conn.resp_body)
    assert resp["accepted"] == 0
    assert is_list(resp["errors"])
    assert Enum.any?(resp["errors"], &String.contains?(&1, "events[1]"))
    assert Enum.any?(resp["errors"], &String.contains?(&1, "time"))

    # Fail-closed: nothing persisted on any validation failure.
    assert OcelLogStore.count() == before
  end

  test "post /api/ocel/ingest refuses a log missing a top-level key (422)" do
    conn =
      valid_log()
      |> Map.delete("objectTypes")
      |> post_log()

    assert conn.status == 422
    resp = JSON.decode!(conn.resp_body)
    assert "missing_key:objectTypes" in resp["errors"]
    assert resp["accepted"] == 0
  end

  # -- Query surface (V8-SIM-BEAM) -------------------------------------------

  test "get /api/ocel/logs lists stored log_ids with event counts" do
    conn = post_log(valid_log())
    assert conn.status == 201
    log_id = JSON.decode!(conn.resp_body)["log_id"]

    conn = conn(:get, "/api/ocel/logs") |> OcelLogIngest.call(OcelLogIngest.init([]))

    assert conn.status == 200
    listing = JSON.decode!(conn.resp_body)
    assert is_map(listing)
    assert listing[log_id] == 2
  end

  test "get /api/ocel/logs/:id returns the stored log" do
    conn = post_log(valid_log())
    log_id = JSON.decode!(conn.resp_body)["log_id"]

    conn = conn(:get, "/api/ocel/logs/#{log_id}") |> OcelLogIngest.call(OcelLogIngest.init([]))

    assert conn.status == 200
    stored = JSON.decode!(conn.resp_body)
    assert stored["events"] |> length() == 2
    assert hd(stored["events"])["id"] == "e-1"
  end

  test "get /api/ocel/logs/:id returns 404 for an unknown id" do
    conn =
      conn(:get, "/api/ocel/logs/ocel-log-does-not-exist")
      |> OcelLogIngest.call(OcelLogIngest.init([]))

    assert conn.status == 404
    assert JSON.decode!(conn.resp_body)["error"] == "log_not_found"
  end

  test "get /api/ocel/logs/:id?format=wasm4pm reshapes to the wpm-trace-conform OcelLog shape" do
    conn = post_log(valid_log())
    log_id = JSON.decode!(conn.resp_body)["log_id"]

    conn =
      conn(:get, "/api/ocel/logs/#{log_id}?format=wasm4pm")
      |> OcelLogIngest.call(OcelLogIngest.init([]))

    assert conn.status == 200
    view = JSON.decode!(conn.resp_body)

    # wasm4pm erlang-bridge OcelLogSchema keys (wpm trace conform input)
    assert view["ocel_version"] == "2.0"
    assert is_map(view["ocel_global_log"]) and is_list(view["ocel_global_log"]["ocel_attribute_names"])
    assert is_list(view["ocel_events"]) and length(view["ocel_events"]) == 2
    assert is_list(view["ocel_objects"]) and length(view["ocel_objects"]) == 1

    ev = hd(view["ocel_events"])
    assert %{"event_id" => "e-1", "activity" => "Create Order", "timestamp" => ts, "objects" => objs, "attributes" => attrs} = ev
    assert is_binary(ts)
    assert objs == [%{"id" => "o-1", "type" => "Order"}]
    assert is_map(attrs)

    obj = hd(view["ocel_objects"])
    assert %{"id" => "o-1", "type" => "Order", "attributes" => %{} = oattrs} = obj
    assert is_map(oattrs)
  end
end
