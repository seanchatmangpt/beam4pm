defmodule BeamPM.LegacyEquivalenceTest do
  use ExUnit.Case, async: true

  alias BeamPM.LegacyEquivalence

  test "implementation identity is ignored when admitted behavior is equal" do
    legacy = [
      %{event_type: "order.cancel", objects: ["order:1"], outcome: "cancelled", source_file: "old.rb"}
    ]

    candidate = [
      %{"event_type" => "order.cancel", "objects" => ["order:1"], "outcome" => "cancelled", "source_file" => "new.ex"}
    ]

    assert {:ok, report} = LegacyEquivalence.compare("orders.cancel", legacy, candidate)
    assert report["schema"] == "beam4pm-legacy-equivalence/1"
    assert report["equivalent"] == true
    assert report["verdict"] == "EQUIVALENT"
    assert report["counterexamples"] == []
    assert report["authority_ceiling"] == "OBSERVE"
  end

  test "semantic outcome delta produces a typed counterexample" do
    legacy = [%{event_type: "order.cancel", objects: ["order:1"], outcome: "cancelled"}]
    candidate = [%{event_type: "order.cancel", objects: ["order:1"], outcome: "pending"}]

    assert {:ok, report} = LegacyEquivalence.compare("orders.cancel", legacy, candidate)
    refute report["equivalent"]
    assert report["verdict"] == "COUNTEREXAMPLE"
    assert [%{"index" => 0} = counterexample] = report["counterexamples"]
    assert counterexample["legacy"]["outcome"] == "cancelled"
    assert counterexample["candidate"]["outcome"] == "pending"
  end

  test "ordering is semantic by default and can be explicitly relaxed" do
    a = %{event_type: "reserve", objects: ["order:1"]}
    b = %{event_type: "cancel", objects: ["order:1"]}

    assert {:ok, ordered} = LegacyEquivalence.compare("orders.cancel", [a, b], [b, a])
    refute ordered["equivalent"]

    assert {:ok, unordered} =
             LegacyEquivalence.compare("orders.cancel", [a, b], [b, a], order_sensitive: false)

    assert unordered["equivalent"]
  end

  test "receipt is deterministic and exact identities can be externally bound" do
    events = [%{event_type: "cancel", objects: ["order:1"], outcome: "ok"}]

    opts = [legacy_identity: "legacy@abc", candidate_identity: "candidate@def"]
    assert {:ok, first} = LegacyEquivalence.compare("orders.cancel", events, events, opts)
    assert {:ok, second} = LegacyEquivalence.compare("orders.cancel", events, events, opts)

    assert first["receipt_digest"] == second["receipt_digest"]
    assert first["legacy_identity"] == "legacy@abc"
    assert first["candidate_identity"] == "candidate@def"
    assert byte_size(first["receipt_digest"]) == 64
  end

  test "events without an observable type are refused" do
    assert {:error, {:invalid_event, 0, :missing_event_type}} =
             LegacyEquivalence.compare("orders.cancel", [%{outcome: "ok"}], [])
  end
end
