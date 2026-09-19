defmodule BeamPM.EconomicISATest do
  use ExUnit.Case, async: true

  alias BeamPM.EconomicISA
  alias BeamPM.Types.OcelRelationship

  @assigned EconomicISA.registry()

  test "all assigned common-path activities are unique one-byte round trips" do
    assert map_size(@assigned) == map_size(Map.new(@assigned, fn {byte, activity} -> {activity, byte} end))

    Enum.each(@assigned, fn {byte, activity} ->
      assert {:ok, <<^byte>>} = EconomicISA.encode(activity)
      assert {:ok, {:fixed, ^byte, ^activity}} = EconomicISA.decode(<<byte>>)
      assert {:ok, ^activity} = EconomicISA.lookup_byte(byte)
      assert {:ok, ^byte} = EconomicISA.lookup_activity(activity)
    end)
  end

  test "reserved bytes refuse instead of acquiring local semantics" do
    for byte <- [0x06, 0x1F, 0x27, 0x3F, 0x46, 0x5F, 0x66, 0x7F, 0x86, 0x9F, 0xA7, 0xBF, 0xC7, 0xDF, 0xE7, 0xEF, 0xF0, 0xFE] do
      assert {:error, {:unassigned_economic_opcode, ^byte}} = EconomicISA.decode(<<byte>>)
    end
  end

  test "UNKNOWN and extended escape boundaries are stable" do
    assert EconomicISA.unknown() == 0x00
    assert EconomicISA.escape() == 0xFF
    assert EconomicISA.category(0x00) == :null
    assert EconomicISA.category(0xFF) == :escape
    assert {:error, :missing_extended_semantic_id} = EconomicISA.decode(<<0xFF>>)
  end

  test "extended semantic identifiers round trip losslessly" do
    semantic_id = "urn:example:economic:custom-action"
    assert {:ok, encoded} = EconomicISA.encode({:extended, semantic_id})
    assert encoded == <<0xFF, semantic_id::binary>>
    assert {:ok, {:extended, ^semantic_id}} = EconomicISA.decode(encoded)
  end

  test "fixed opcode rejects trailing payload" do
    assert {:error, :trailing_bytes_on_fixed_economic_opcode} = EconomicISA.decode(<<0x41, 0x00>>)
  end

  test "economic opcode projects into existing OCEL event without collapsing relationships or evidence" do
    {:ok, relationship} =
      OcelRelationship.new(%{qualifier: "customer", object_id: "customer-1"})

    assert {:ok, event, [^relationship]} =
             EconomicISA.to_ocel_event(
               :pay,
               "evt-1",
               "2026-09-10T22:00:00Z",
               relationships: [relationship],
               authority: %{"principal" => "customer-1"},
               provenance: %{"source" => "payment-gateway"},
               economic_value: %{"amount" => "125.00", "currency" => "USD"}
             )

    assert event.event_id == "evt-1"
    assert event.event_type == "pay"
    assert event.event_time == "2026-09-10T22:00:00Z"
    assert event.attributes["economic:opcode"] == 0x41
    assert event.attributes["economic:category"] == "payment_settlement"
    assert event.attributes["authority"] == %{"principal" => "customer-1"}
    assert event.attributes["provenance"] == %{"source" => "payment-gateway"}
    assert event.attributes["economic:value"] == %{"amount" => "125.00", "currency" => "USD"}
  end

  test "extended OCEL event preserves semantic identifier rather than allocating a byte" do
    semantic_id = "https://example.org/economic/custom-action"

    assert {:ok, event, []} =
             EconomicISA.to_ocel_event(
               {:extended, semantic_id},
               "evt-x",
               "2026-09-10T22:00:00Z"
             )

    assert event.event_type == "extended"
    assert event.attributes["economic:opcode"] == 0xFF
    assert event.attributes["economic:category"] == "escape"
    assert event.attributes["economic:semantic_id"] == semantic_id
  end
end
