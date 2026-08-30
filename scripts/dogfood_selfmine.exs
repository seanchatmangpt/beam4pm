# dogfood_selfmine.exs -- beam4pm mines its OWN manufacturing process.
#
# Run from the beam4pm repo root:
#
#     mix run scripts/dogfood_selfmine.exs
#
# The whole loop, live, in one BEAM:
#
#   1. Attach a real :telemetry handler on ggen_igniter's OCEL event name
#      (GgenIgniter.Telemetry.OcelEmitter.telemetry_event/0 ==
#      [:ggen_igniter, :reconcile, :ocel]).
#   2. Run ONE real `mix ggen_igniter.sync` of the beam4pm-process-model-pack's
#      Ash recipe (ontology.ttl + igniter/queries/*.rq +
#      igniter/templates/beam4pm_ash.ex.eex -> generated/elixir/lib/beam4pm_ash.ex)
#      in-process via Mix.Task.run/2 -- the exact recipe scripts/igniter_sync.sh
#      step 1 runs. ggen_igniter's Reactor pipeline (always attempted first
#      since AR-9, ggen_igniter >= 26.8.30) emits one OCEL event per lifecycle
#      stage; :verify really runs `mix compile --warnings-as-errors` against
#      this repo as a subprocess, so this script takes tens of seconds.
#   3. Collect the emitted events, convert each into a beam4pm
#      BeamPM.Types.OcelEvent through the real validating new/1 constructor
#      (event_id <- "id", event_type <- "activity", event_time <- "time",
#      attributes <- the event's own attributes + a "manufacturing_run" case
#      key stamped at the capture boundary -- the emitter itself carries no
#      uniform per-run correlation attribute; one handler session == one case).
#   4. Mine the manufacturing process with the real generated
#      BeamPM.Discovery.traces_from_events/2 + dfg_from_traces/1.
#   5. Print the mined DFG and HARD-ASSERT the expected lifecycle edges
#      (grounded in the events ggen_igniter 26.8.30 really emits -- captured
#      and verified 2026-08-29; see docs/jira/v26.8.29/18-dogfood-selfmine-loop.md).
#   6. Cross-check against the durable evidence: the GgenIgniter.Receipt this
#      same run appended under .ggen_igniter/receipts/ embeds the first 9 of
#      the 10 events (STANDING_SET fires after the receipt snapshots the sink).
#
# Exits nonzero on any assertion failure. Side effects: the sync is beam4pm's
# own real manufacturing step -- it (re)writes generated/elixir/lib/beam4pm_ash.ex
# (a no-op "unchanged (skipped, identical content)" when the ontology is
# unchanged), updates .ggen_igniter/manifest.json, and appends one receipt
# line under .ggen_igniter/receipts/.

defmodule Beam4PM.Dogfood.Capture do
  @moduledoc false
  # Module-based telemetry handler (a plain named function -- avoids
  # :telemetry's local-function performance warning). Forwards every OCEL
  # event map to the collector process, tagged with a monotonic timestamp so
  # arrival order is independently recorded.
  def handle(_event_name, _measurements, event, %{collector: pid}) do
    send(pid, {:ocel_event, System.monotonic_time(:microsecond), event})
  end
end

defmodule Beam4PM.Dogfood.SelfMine do
  @moduledoc false

  @handler_id "beam4pm-dogfood-selfmine"

  def main do
    for {mod, hint} <- [
          {BeamPM.Discovery, "generated/elixir/lib must be on elixirc_paths"},
          {BeamPM.Types.OcelEvent, "generated/elixir/lib must be on elixirc_paths"},
          {GgenIgniter.Telemetry.OcelEmitter,
           "{:ggen_igniter, \"~> 26.8\"} must be a (dev) dependency"}
        ] do
      Code.ensure_loaded?(mod) ||
        die("BLOCKED: module #{inspect(mod)} is not loadable (#{hint})")
    end

    pack = System.get_env("PACK", "vendor/ggen-marketplace/packs/beam4pm-process-model-pack")
    ign = Path.join(pack, "igniter")

    for rel <- [
          "ontology.ttl",
          Path.join(ign, "queries/records.rq"),
          Path.join(ign, "queries/fields.rq"),
          Path.join(ign, "templates/beam4pm_ash.ex.eex")
        ] do
      File.exists?(rel) || die("BLOCKED: required input #{rel} not found (run from repo root)")
    end

    {:ok, _} = Application.ensure_all_started(:telemetry)

    run_id = "selfmine-" <> (DateTime.utc_now() |> DateTime.to_iso8601())

    :ok =
      :telemetry.attach(
        @handler_id,
        GgenIgniter.Telemetry.OcelEmitter.telemetry_event(),
        &Beam4PM.Dogfood.Capture.handle/4,
        %{collector: self()}
      )

    args = [
      "--ontology", "ontology.ttl",
      "--query", "records=#{ign}/queries/records.rq",
      "--query", "fields=#{ign}/queries/fields.rq",
      "--template", "#{ign}/templates/beam4pm_ash.ex.eex",
      "--out", "generated/elixir/lib/beam4pm_ash.ex"
    ]

    IO.puts("== dogfood self-mine: running real manufacturing step ==")
    IO.puts("   mix ggen_igniter.sync #{Enum.join(args, " ")}")

    try do
      Mix.Task.run("ggen_igniter.sync", args)
    after
      # Detach BEFORE draining: no event can arrive mid-drain.
      :telemetry.detach(@handler_id)
    end

    raw_events = drain([])

    IO.puts("== captured #{length(raw_events)} OCEL telemetry events ==")

    raw_events == [] &&
      die(
        "FAIL: zero OCEL events captured -- the sync did not route through " <>
          "ggen_igniter's Reactor pipeline (expected \"(via reactor)\" in its notice)"
      )

    # -- Convert: emitter wire shape -> beam4pm ocel_event wire shape --------
    events =
      Enum.map(raw_events, fn ev ->
        {:ok, ocel} =
          BeamPM.Types.OcelEvent.new(%{
            event_id: Map.fetch!(ev, "id"),
            event_type: Map.fetch!(ev, "activity"),
            event_time: Map.fetch!(ev, "time"),
            attributes: Map.put(ev["attributes"] || %{}, "manufacturing_run", run_id)
          })

        ocel
      end)

    for e <- events do
      IO.puts("   #{e.event_time}  #{e.event_type}")
    end

    # Discovery orders by event_time (ISO8601 lexicographic) with event_id
    # tie-break; the emitter's ids are random hex, so a same-microsecond tie
    # would make adjacent-edge order genuinely nondeterministic. Refuse to
    # assert on top of that instead of going silently flaky.
    times = Enum.map(events, & &1.event_time)

    times == Enum.sort(times) ||
      die("FAIL: captured event_times are not in arrival order: #{inspect(times)}")

    length(Enum.uniq(times)) == length(times) ||
      die(
        "FAIL: duplicate event_time values captured (#{inspect(times)}) -- " <>
          "discovery's event_id tie-break would be nondeterministic over random ids"
      )

    # -- Mine: the product's own generated discovery over its factory's log --
    traces = BeamPM.Discovery.traces_from_events(events, "manufacturing_run")
    dfg = BeamPM.Discovery.dfg_from_traces(traces)

    IO.puts("== mined manufacturing DFG ==")

    for edge <- dfg do
      IO.puts("   #{edge.source_activity} -> #{edge.target_activity} x#{edge.frequency}")
    end

    edges_json =
      Enum.map(dfg, fn e ->
        %{
          "source_activity" => e.source_activity,
          "target_activity" => e.target_activity,
          "frequency" => e.frequency
        }
      end)

    IO.puts("MINED_DFG_JSON: " <> Jason.encode!(%{"edges" => edges_json}))

    # -- Assertions (grounded in ggen_igniter 26.8.30's real happy path) -----
    expected_sequence = [
      "RECONCILIATION_STARTED",
      "PLAN_CONSTRUCTED",
      "ADMISSION_ACCEPTED",
      "ACTUATION_STARTED",
      "FILES_CHANGED",
      "VERIFICATION_SUCCEEDED",
      "ADMITTED",
      "EVIDENCE_FINALIZED",
      "RECONCILIATION_ALIVE",
      "STANDING_SET"
    ]

    expected_edges =
      expected_sequence
      |> Enum.zip(Enum.drop(expected_sequence, 1))
      |> Enum.sort()
      |> Enum.map(fn {s, t} -> {s, t, 1} end)

    failures =
      []
      |> check(
        "exactly one trace mined, case_id == #{inspect(run_id)}",
        match?([%BeamPM.Types.LogTrace{case_id: ^run_id}], traces)
      )
      |> check(
        "mined activity_sequence is the full alive-path lifecycle " <>
          "(#{Enum.join(expected_sequence, " -> ")})",
        List.first(traces) && List.first(traces).activity_sequence == expected_sequence
      )
      |> check(
        "mined DFG is exactly the #{length(expected_edges)} expected edges, each x1, " <>
          "sorted by source then target",
        Enum.map(dfg, &{&1.source_activity, &1.target_activity, &1.frequency}) ==
          expected_edges
      )
      |> check(
        "no failure/compensation activity present (VERIFICATION_FAILED, GUARD_REFUSED, " <>
          "COMPENSATION_STARTED, COMPENSATION_FAILED, FILES_RESTORED)",
        (List.first(traces) &&
           Enum.all?(
             ~w(VERIFICATION_FAILED GUARD_REFUSED COMPENSATION_STARTED COMPENSATION_FAILED FILES_RESTORED),
             fn bad -> bad not in List.first(traces).activity_sequence end
           )) || false
      )
      |> check(
        "conformance of the mined trace against its own DFG has fitness 1.0",
        traces != [] and
          BeamPM.Discovery.conformance(dfg, List.first(traces)).fitness == 1.0
      )
      |> check_receipt(Enum.map(events, & &1.event_type))

    case failures do
      [] ->
        IO.puts("== dogfood self-mine: ALIVE (all assertions passed) ==")

      _ ->
        IO.puts(:stderr, "== dogfood self-mine: FAILED ==")
        Enum.each(failures, &IO.puts(:stderr, "   FAIL: #{&1}"))
        System.halt(1)
    end
  end

  # Cross-check the durable evidence trail: the same run appended a real
  # GgenIgniter.Receipt line whose embedded events are the sink's snapshot --
  # taken inside :finalize_evidence, i.e. BEFORE STANDING_SET fires -- so the
  # receipt's activity list must be a strict prefix of what telemetry saw.
  defp check_receipt(failures, captured_activities) do
    receipts_dir = ".ggen_igniter/receipts"

    with {:ok, names} <- File.ls(receipts_dir),
         [file | _] <- names |> Enum.filter(&String.ends_with?(&1, ".jsonl")) |> Enum.sort(:desc),
         {:ok, raw} <- File.read(Path.join(receipts_dir, file)),
         last_line when is_binary(last_line) <-
           raw |> String.split("\n", trim: true) |> List.last(),
         {:ok, receipt} <- Jason.decode(last_line) do
      receipt_activities = Enum.map(receipt["events"] || [], & &1["activity"])

      failures
      |> check(
        "this run's persisted receipt (#{receipts_dir}/#{file}) has standing \"alive\"",
        receipt["standing"] == "alive"
      )
      |> check(
        "receipt's embedded events (#{length(receipt_activities)}) are a strict prefix " <>
          "of the #{length(captured_activities)} telemetry-captured events",
        receipt_activities != [] and
          receipt_activities == Enum.take(captured_activities, length(receipt_activities)) and
          length(receipt_activities) < length(captured_activities)
      )
    else
      _ ->
        ["no readable GgenIgniter.Receipt line found under #{receipts_dir}/" | failures]
    end
  end

  defp check(failures, _label, true), do: failures
  defp check(failures, label, _falsy), do: failures ++ [label]

  defp drain(acc) do
    receive do
      {:ocel_event, _mono, event} -> drain(acc ++ [event])
    after
      0 -> acc
    end
  end

  defp die(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

Beam4PM.Dogfood.SelfMine.main()
