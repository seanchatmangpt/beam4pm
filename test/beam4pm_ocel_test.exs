defmodule BeamPM.OcelTest do
  use ExUnit.Case, async: true

  alias BeamPM.Ocel
  alias BeamPM.Types.OcelAttribute
  alias BeamPM.Types.OcelEvent
  alias BeamPM.Types.OcelObject
  alias BeamPM.Types.OcelRelationship

  defp event!(id, type, time, rels) do
    {:ok, e} = OcelEvent.new(%{event_id: id, event_type: type, event_time: time})
    {e, rels}
  end

  defp object!(id, type), do: object!(id, type, [])

  defp object!(id, type, rels) do
    {:ok, o} = OcelObject.new(%{object_id: id, object_type: type})
    {o, rels}
  end

  defp rel!(qualifier, object_id) do
    {:ok, r} = OcelRelationship.new(%{qualifier: qualifier, object_id: object_id})
    r
  end

  describe "object_trace/2" do
    test "returns only events touching the given object id, time-ordered" do
      e1 = event!("e-1", "Create Order", "2026-09-09T02:00:00Z", [rel!("places", "o-1")])
      e2 = event!("e-2", "Unrelated", "2026-09-09T00:00:00Z", [rel!("touches", "o-999")])
      e3 = event!("e-3", "Ship Order", "2026-09-09T01:00:00Z", [rel!("ships", "o-1")])

      trace = Ocel.object_trace([e1, e2, e3], "o-1")

      assert Enum.map(trace, & &1.event_id) == ["e-3", "e-1"]
    end

    test "an object touched by no event returns an empty trace, not an error" do
      e1 = event!("e-1", "Create Order", "2026-09-09T00:00:00Z", [rel!("places", "o-1")])
      assert Ocel.object_trace([e1], "o-does-not-exist") == []
    end
  end

  describe "attribute_history/1" do
    test "sorts real attribute records chronologically" do
      {:ok, a1} = OcelAttribute.new(%{attribute_name: "price", attribute_value: "10", recorded_at: "2026-09-09T02:00:00Z"})
      {:ok, a2} = OcelAttribute.new(%{attribute_name: "price", attribute_value: "5", recorded_at: "2026-09-09T00:00:00Z"})
      {:ok, a3} = OcelAttribute.new(%{attribute_name: "price", attribute_value: "8", recorded_at: "2026-09-09T01:00:00Z"})

      history = Ocel.attribute_history([a1, a2, a3])

      assert Enum.map(history, & &1.attribute_value) == ["5", "8", "10"]
    end
  end

  describe "relationships_for/2" do
    test "collects real relationships from both events and objects touching one object id" do
      e1 = event!("e-1", "Create Order", "2026-09-09T00:00:00Z", [rel!("places", "o-1")])
      o1 = object!("o-parent", "Order", [rel!("contains", "o-1")])
      o2 = object!("o-other", "Order", [rel!("contains", "o-999")])

      rels = Ocel.relationships_for([e1, o1, o2], "o-1")

      assert Enum.map(rels, & &1.qualifier) |> Enum.sort() == ["contains", "places"]
    end
  end

  describe "validate_envelope/2" do
    test "a real envelope whose relationships all resolve is :ok" do
      o1 = object!("o-1", "Order")
      e1 = event!("e-1", "Create Order", "2026-09-09T00:00:00Z", [rel!("places", "o-1")])

      assert Ocel.validate_envelope([e1], [o1]) == :ok
    end

    test "a real dangling event relationship is refused, never silently dropped" do
      e1 = event!("e-1", "Create Order", "2026-09-09T00:00:00Z", [rel!("places", "o-ghost")])

      assert {:error, {:dangling_relationships, dangling}} = Ocel.validate_envelope([e1], [])
      assert {:event, "e-1", "o-ghost"} in dangling
    end

    test "a real dangling object-to-object relationship is refused too" do
      o1 = object!("o-1", "Order", [rel!("contains", "o-ghost")])

      assert {:error, {:dangling_relationships, dangling}} = Ocel.validate_envelope([], [o1])
      assert {:object, "o-1", "o-ghost"} in dangling
    end
  end
end
