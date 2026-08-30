# ecosystem_process_mine.exs -- beam4pm as the process-intelligence suite FOR
# the ggen-ecosystem/ggen-marketplace container: mine the container's OWN
# manufacture rail from its real CI event log.
#
# Run via the fetcher (which produces tmp/ecosystem-mine/rail-events.json from
# real GitHub Actions step data first):
#
#     bash scripts/ecosystem_process_mine.sh
#
# What this script does, all through the REAL generated modules (never
# reimplemented, never mocked -- same discipline as dogfood_selfmine.exs):
#
#   1. Admit every fetched step event through BeamPM.Types.OcelEvent.new/1
#      (the validating constructor): case = the real run id, activity = the
#      real step name, time = the step's real started_at.
#   2. BeamPM.Discovery.traces_from_events/2 -> one trace per real rail run.
#   3. BeamPM.Discovery.variants_from_traces/1 -> the rail's real process
#      variants (the green path plus each distinct real failure shape --
#      today's log genuinely contains the safe.directory refusal shape and
#      the stale-ggen.lock refusal shape alongside the green path).
#   4. dfg_from_traces over the GREEN runs only -> the reference model of a
#      healthy manufacture, then conformance/2 (fitness + real ETC precision
#      via the generated BeamPM.Precision) of EVERY run against it -- failed
#      runs are expected to fit the green model's prefix (fitness 1.0: they
#      do nothing off-model, they just stop early), which is itself a real
#      process-intelligence finding: the rail fails by refusal, not by
#      divergence.
#   5. Cross-evidence conformance: if the downloaded rail replay-receipt
#      (tmp/ecosystem-mine/rail-artifact/*/ecosystem-sync-receipt.json) is
#      present, hard-assert its marketplace_sha equals this checkout's real
#      vendor/ggen-marketplace gitlink, its sync_exit_code is "0", and its
#      patch_sha256 is the empty-patch digest (zero manufacturing drift).
#
# Hard-asserts (exits nonzero on any failure) the green rail's load-bearing
# lifecycle edges, grounded in the reusable workflow's real step names.

defmodule Beam4PM.EcosystemMine do
  @moduledoc false

  @events_path "tmp/ecosystem-mine/rail-events.json"
  @receipt_glob "tmp/ecosystem-mine/rail-artifact/*/ecosystem-sync-receipt.json"
  @case_key "manufacture_run"
  # sha256 of the empty string == an empty ggen-sync.patch == zero drift
  @empty_patch_sha256 "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

  def main do
    for {mod, hint} <- [
          {BeamPM.Discovery, "lib must be on elixirc_paths"},
          {BeamPM.Precision, "lib must be on elixirc_paths"},
          {BeamPM.Types.OcelEvent, "lib must be on elixirc_paths"}
        ] do
      Code.ensure_loaded?(mod) || die("BLOCKED: #{inspect(mod)} not loadable (#{hint})")
    end

    File.exists?(@events_path) ||
      die("BLOCKED: #{@events_path} not found -- run bash scripts/ecosystem_process_mine.sh")

    raw = @events_path |> File.read!() |> JSON.decode!()
    raw != [] || die("REFUSED: empty event log")

    # Mine the SEMANTIC manufacture lifecycle: only the rail's construct job
    # ("Deterministic ecosystem manufacture"), with runner housekeeping steps
    # (Set up/Complete/Initialize/Stop/Post-*) excluded -- those are GitHub's
    # scaffolding around the process, not the process. The resolve job is the
    # caller's preflight, not the rail.
    raw =
      Enum.filter(raw, fn e ->
        String.contains?(e["job"], "Deterministic ecosystem manufacture") and
          not Enum.any?(
            ["Set up job", "Complete job", "Initialize containers", "Stop containers"],
            &(&1 == e["activity"])
          ) and not String.starts_with?(e["activity"], "Post ")
      end)

    raw != [] || die("REFUSED: no construct-job lifecycle events in the log")

    run_conclusions =
      raw
      |> Enum.group_by(& &1["case_id"], & &1["run_conclusion"])
      |> Map.new(fn {case_id, cs} -> {case_id, hd(cs)} end)

    # 1. Admit every real step event through the validating constructor.
    events =
      Enum.map(raw, fn e ->
        {:ok, ev} =
          BeamPM.Types.OcelEvent.new(%{
            # GitHub step timestamps are second-granular, so same-second steps
            # tie on event_time; traces_from_events breaks ties by event_id,
            # so the job-authoritative step number is zero-padded in FIRST.
            event_id:
              "#{String.pad_leading(to_string(e["number"]), 3, "0")}:#{e["case_id"]}:#{e["activity"]}",
            event_type: e["activity"],
            event_time: e["time"],
            attributes: %{
              @case_key => e["case_id"],
              "step_conclusion" => e["step_conclusion"],
              "job" => e["job"]
            }
          })

        ev
      end)

    IO.puts("== #{length(events)} real step events admitted through OcelEvent.new/1 ==")

    # 2. One trace per real rail run.
    traces = BeamPM.Discovery.traces_from_events(events, @case_key)
    IO.puts("== #{length(traces)} manufacture-run trace(s) ==")

    for t <- traces do
      c = run_conclusions[t.case_id] || "?"
      IO.puts("   run #{t.case_id} (#{c}): #{length(t.activity_sequence)} steps")
    end

    # 3. The rail's real process variants.
    variants = BeamPM.Discovery.variants_from_traces(traces)
    IO.puts("\n== #{length(variants)} real process variant(s) of the manufacture rail ==")

    for v <- variants do
      IO.puts("   variant #{v.variant_id} (x#{v.frequency}):")
      for a <- v.activity_sequence, do: IO.puts("      - #{a}")
    end

    # 4. Green-path reference model + conformance of every run against it.
    green_traces =
      Enum.filter(traces, fn t -> run_conclusions[t.case_id] == "success" end)

    green_traces != [] ||
      die("REFUSED: no successful rail run in the log -- no reference model to mine")

    model = BeamPM.Discovery.dfg_from_traces(green_traces)
    IO.puts("\n== green-path DFG model: #{length(model)} edge(s) ==")
    for e <- model, do: IO.puts("   #{e.source_activity} -> #{e.target_activity} (x#{e.frequency})")

    IO.puts("\n== conformance of every real run against the green model ==")

    for t <- traces do
      r = BeamPM.Discovery.conformance(model, t)
      c = run_conclusions[t.case_id] || "?"

      IO.puts(
        "   run #{t.case_id} (#{c}): fitness=#{Float.round(r.fitness * 1.0, 4)} " <>
          "precision=#{Float.round(r.precision * 1.0, 4)}"
      )
    end

    # Hard assertions: the green rail's load-bearing lifecycle edges.
    green_model_pairs =
      MapSet.new(model, fn e -> {e.source_activity, e.target_activity} end)

    required_edges = [
      {"Checkout exact candidate", "Admit immutable producer and pack identities"},
      {"Admit immutable producer and pack identities",
       "Restore untrusted native GGen pack cache"},
      {"Manufacture with ggen sync run (ggen preinstalled in the composed container)",
       "Bind generated consequence into replay receipt"},
      {"Bind generated consequence into replay receipt",
       "Upload deterministic replay evidence"},
      {"Upload deterministic replay evidence", "Enforce GGen sync standing"}
    ]

    for {src, dst} = edge <- required_edges do
      MapSet.member?(green_model_pairs, edge) ||
        die("ASSERT FAILED: green model is missing lifecycle edge #{src} -> #{dst}")
    end

    IO.puts("\nASSERT OK: all #{length(required_edges)} green lifecycle edges present")

    # Green runs must fit their own model perfectly.
    for t <- green_traces do
      r = BeamPM.Discovery.conformance(model, t)

      r.fitness == 1.0 ||
        die("ASSERT FAILED: green run #{t.case_id} does not fit the green model")
    end

    IO.puts("ASSERT OK: every green run fits the green model (fitness 1.0)")

    # 5. Cross-evidence conformance against the rail's own replay receipt.
    case Path.wildcard(@receipt_glob) do
      [] ->
        IO.puts("\n(receipt cross-check skipped: no downloaded rail artifact under tmp/)")

      [receipt_path | _] ->
        receipt = receipt_path |> File.read!() |> JSON.decode!()
        {gitlink, 0} = System.cmd("git", ["rev-parse", "HEAD:vendor/ggen-marketplace"])
        gitlink = String.trim(gitlink)

        receipt["marketplace_sha"] == gitlink ||
          die(
            "ASSERT FAILED: receipt marketplace_sha #{receipt["marketplace_sha"]} " <>
              "!= checkout gitlink #{gitlink}"
          )

        receipt["sync_exit_code"] == "0" ||
          die("ASSERT FAILED: receipt sync_exit_code #{receipt["sync_exit_code"]}")

        receipt["patch_sha256"] == @empty_patch_sha256 ||
          die(
            "ASSERT FAILED: receipt patch_sha256 is not the empty-patch digest -- " <>
              "the rail observed real manufacturing drift"
          )

        IO.puts(
          "\nASSERT OK: replay receipt binds marketplace_sha=#{String.slice(gitlink, 0, 12)}..., " <>
            "sync_exit_code=0, patch=EMPTY (zero manufacturing drift)"
        )
    end

    IO.puts("\nECOSYSTEM PROCESS MINE: PASS")
  end

  defp die(msg) do
    IO.puts(:stderr, msg)
    System.halt(1)
  end
end

Beam4PM.EcosystemMine.main()
