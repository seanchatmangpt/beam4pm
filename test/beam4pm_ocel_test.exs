defmodule BeamPM.OcelTest do
  @moduledoc """
  Chicago-style round-trip test for the hand-authored `BeamPM.Ocel`
  encode/1 decode/1 pair. No mocks: real `BeamPM.Types.OcelEvent.new/1` /
  `BeamPM.Types.OcelObject.new/1` constructors, real `BeamPM.Ocel.encode/1`,
  real `BeamPM.Ocel.decode/1`, real JSON on the wire, assertions on the
  actual returned data.
  """
  use ExUnit.Case, async: true

  test "encode/1 then decode/1 round-trips real OCEL 2.0 events and objects" do
    {:ok, event} =
      BeamPM.Types.OcelEvent.new(%{
        event_id: "e1",
        event_type: "place_order",
        event_time: "2026-09-09T12:00:00Z",
        attributes: %{"amount" => 42}
      })

    {:ok, object} =
      BeamPM.Types.OcelObject.new(%{
        object_id: "o1",
        object_type: "order",
        attributes: %{"status" => "open"}
      })

    assert {:ok, json} = BeamPM.Ocel.encode(events: [event], objects: [object])
    assert is_binary(json)

    assert {:ok, %{events: [decoded_event], objects: [decoded_object]}} = BeamPM.Ocel.decode(json)

    assert decoded_event.event_id == event.event_id
    assert decoded_event.event_type == event.event_type
    assert decoded_event.event_time == event.event_time
    assert decoded_event.attributes == event.attributes

    assert decoded_object.object_id == object.object_id
    assert decoded_object.object_type == object.object_type
    assert decoded_object.attributes == object.attributes
  end

  test "encode/1 produces a real OCEL 2.0 JSON envelope shape" do
    {:ok, event} =
      BeamPM.Types.OcelEvent.new(%{
        event_id: "e2",
        event_type: "ship_order",
        event_time: "2026-09-09T13:00:00Z",
        attributes: %{}
      })

    {:ok, object} =
      BeamPM.Types.OcelObject.new(%{
        object_id: "o2",
        object_type: "shipment",
        attributes: %{}
      })

    {:ok, json} = BeamPM.Ocel.encode(events: [event], objects: [object])
    decoded_raw = JSON.decode!(json)

    assert Map.has_key?(decoded_raw, "objectTypes")
    assert Map.has_key?(decoded_raw, "eventTypes")
    assert Map.has_key?(decoded_raw, "objects")
    assert Map.has_key?(decoded_raw, "events")
    assert decoded_raw["objectTypes"] == [%{"name" => "shipment", "attributes" => []}]
    assert decoded_raw["eventTypes"] == [%{"name" => "ship_order", "attributes" => []}]
  end

  test "decode/1 returns an error tuple for a malformed envelope" do
    assert {:error, _} = BeamPM.Ocel.decode(JSON.encode!(%{"nonsense" => true}))
  end
end
