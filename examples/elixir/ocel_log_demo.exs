# Real, runnable demo of the ggen-manufactured BeamPM.Types.OcelEvent module.
#
# This script builds a small in-memory OCEL 2.0 event log (three events) directly
# against `BeamPM.Types.OcelEvent` from generated/elixir/lib/beam4pm_types.ex --
# no mocks, no stubs, no fixtures standing in for the real module.
#
# Invocation (from the beam4pm project root, after `mix compile`):
#
#     mix run examples/elixir/ocel_log_demo.exs
#
# See examples/elixir/README.md for the full setup/invocation story.

alias BeamPM.Types.OcelEvent

# Three raw event maps, as OCEL 2.0 would carry them: required :event_id,
# :event_type, :event_time, plus optional free-form :attributes.
raw_events = [
  %{
    event_id: "e-1001",
    event_type: "PlaceOrder",
    event_time: "2026-08-29T09:00:00Z",
    attributes: %{"customer" => "cust-42", "channel" => "web"}
  },
  %{
    event_id: "e-1002",
    event_type: "PackItems",
    event_time: "2026-08-29T09:15:00Z",
    attributes: %{"warehouse" => "wh-7"}
  },
  %{
    event_id: "e-1003",
    event_type: "ShipOrder",
    event_time: "2026-08-29T10:30:00Z"
    # :attributes deliberately omitted -- OcelEvent.new/1 only requires
    # :event_id, :event_type, and :event_time.
  }
]

# Build each event via the real BeamPM.Types.OcelEvent.new/1 constructor,
# pattern-matching on its {:ok, event} | {:error, reason} contract.
events =
  Enum.map(raw_events, fn attrs ->
    case OcelEvent.new(attrs) do
      {:ok, %OcelEvent{} = event} ->
        event

      {:error, reason} ->
        IO.puts(:stderr, "error: OcelEvent.new/1 rejected #{inspect(attrs)}: #{inspect(reason)}")
        System.halt(1)
    end
  end)

IO.puts("Built #{length(events)} OcelEvent structs via BeamPM.Types.OcelEvent.new/1:")

Enum.each(events, fn %OcelEvent{event_id: event_id, event_type: event_type} ->
  IO.puts("  #{event_id} :: #{event_type}")
end)
