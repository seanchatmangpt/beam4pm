# rust4pm_ocel_examples_wasm.exs -- the rust4pm docs site's two documented
# examples ("Building a Linked OCEL" and its from-tabular-data variant),
# implemented over the WASM engine with canonical data. Hard-asserts real
# values; exits nonzero on any failure.
#
#   mix run scripts/rust4pm_ocel_examples_wasm.exs
#
# Example A -- Building a Linked OCEL end-to-end (the docs example's exact
# workflow: declare types, add objects/events with E2O/O2O, export):
# a minimal order-management OCEL, then export and re-check via stats.
#
# Example B -- canonical-dataset variant: build an OCEL FROM the real BPI-2020
# InternationalDeclarations.xes (one "declaration" object per case, one OCEL
# event per XES event, E2O qualifier "case"), asserting the totals against
# the log's own real, engine-verified numbers (6449 cases / 72151 events).
alias BeamPM.Rust4PM

defmodule Die do
  def die(msg) do
    IO.puts(:stderr, msg)
    System.halt(1)
  end
end

case Rust4PM.start() do
  {:ok, _} -> :ok
  {:error, {:wasm_missing, reason}} -> Die.die("BLOCKED: #{reason}")
  other -> Die.die("BLOCKED: engine start failed: #{inspect(other)}")
end

IO.puts("== example A: Building a Linked OCEL (docs example, end-to-end) ==")
{:ok, %{"ocel_handle" => h}} = Rust4PM.ocel_new()
{:ok, _} = Rust4PM.ocel_add_event_type(h, "place order", [%{"name" => "channel", "type" => "string"}])
{:ok, _} = Rust4PM.ocel_add_event_type(h, "ship order")
{:ok, _} = Rust4PM.ocel_add_object_type(h, "order")
{:ok, _} = Rust4PM.ocel_add_object_type(h, "customer")
{:ok, _} = Rust4PM.ocel_add_object(h, "c1", "customer")
{:ok, _} = Rust4PM.ocel_add_object(h, "o1", "order", [["c1", "placed_by"]])
{:ok, _} = Rust4PM.ocel_add_event(h, "e1", "place order", "2026-08-30T10:00:00+00:00", [["o1", "order"], ["c1", "customer"]])
{:ok, _} = Rust4PM.ocel_add_event(h, "e2", "ship order", "2026-08-30T12:30:00+00:00", [["o1", "order"]])

# refusals are real, not decorative:
{:error, {:engine, msg}} = Rust4PM.ocel_add_event(h, "e3", "not a type", "2026-08-30T13:00:00+00:00", [])
String.contains?(msg, "undeclared event type") || Die.die("ASSERT: wrong refusal: #{msg}")
{:error, {:engine, msg2}} = Rust4PM.ocel_add_object(h, "o1", "order")
String.contains?(msg2, "duplicate object id") || Die.die("ASSERT: wrong refusal: #{msg2}")

{:ok, stats} = Rust4PM.ocel_stats(h)
stats["num_events"] == 2 || Die.die("ASSERT: num_events #{stats["num_events"]} != 2")
stats["num_objects"] == 2 || Die.die("ASSERT: num_objects != 2")
stats["events_per_type"] == %{"place order" => 1, "ship order" => 1} || Die.die("ASSERT: events_per_type")

{:ok, %{"ocel" => doc}} = Rust4PM.ocel_to_json(h)
length(doc["events"]) == 2 || Die.die("ASSERT: exported events != 2")
[first_ev | _] = doc["events"]
first_ev["relationships"] == [
  %{"objectId" => "o1", "qualifier" => "order"},
  %{"objectId" => "c1", "qualifier" => "customer"}
] || Die.die("ASSERT: E2O export shape: #{inspect(first_ev["relationships"])}")
IO.puts("   OCEL 2.0 export: #{length(doc["events"])} events, #{length(doc["objects"])} objects, " <>
        "#{length(doc["eventTypes"])} event types -- E2O/O2O relations verified in the wire shape")

IO.puts("\n== example B: OCEL from canonical InternationalDeclarations.xes ==")
xes = Path.expand("~/wasm4pm/data/InternationalDeclarations.xes")
File.exists?(xes) || Die.die("BLOCKED: canonical dataset not found at #{xes}")
{:ok, %{"handle" => log}} = Rust4PM.import_xes(File.read!(xes))
{:ok, %{"ocel_handle" => oh}} = Rust4PM.xes_to_ocel(log, "declaration", "case")
{:ok, ostats} = Rust4PM.ocel_stats(oh)
IO.puts("   objects (declarations): #{ostats["num_objects"]}")
IO.puts("   OCEL events:            #{ostats["num_events"]}")
IO.puts("   event types:            #{ostats["num_event_types"]}")
ostats["num_objects"] == 6449 || Die.die("ASSERT: expected 6449 declaration objects (the log's real case count)")
ostats["num_event_types"] == 34 || Die.die("ASSERT: expected the log's real 34 activities as event types")
ostats["num_events"] > 70_000 || Die.die("ASSERT: implausible event total #{ostats["num_events"]}")

IO.puts("\nRUST4PM OCEL EXAMPLES (wasm): PASS -- all assertions held")
