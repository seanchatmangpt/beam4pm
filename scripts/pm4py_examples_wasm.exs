# pm4py_examples_wasm.exs -- three pm4py example workflows, ported end-to-end
# onto the ONE rust4pm wasm engine (process_mining =0.6.2 compiled to
# wasm32-wasip1, hosted by wasmex, wrapped by BeamPM.Rust4PM). No process-mining
# computation happens in Elixir here: every result below comes out of the wasm
# linear-memory JSON ABI.
#
# Run from the beam4pm repo root (after scripts/rust4pm_wasm_build.sh):
#
#     mix run scripts/pm4py_examples_wasm.exs
#
# The three upstream examples being ported (pm4py checkout at
# /Users/sac/chatmangpt/pm4py):
#
#   1. examples/alignment_discounted_a_star.py -- import running-example.xes +
#      running-example.pnml, align the log's FIRST trace (case "3") against the
#      net, print the alignment moves + cost. HONEST DEVIATION, stated loudly
#      below and asserted against the engine's own refusal: pm4py's
#      VERSION_DISCOUNTED_A_STAR exponent (1.1) is UNSUPPORTED by
#      process_mining 0.6.2 -- the crate has only the per-move-kind
#      CostFunction {model,log,sync,silent} -- so this port shows the STANDARD
#      optimal alignment and never fakes a discounted one.
#   2. examples/activities_to_alphabet.py -- remap activity names to A..Z,AA...
#      by descending total event count (ties pinned to first-seen order in the
#      log; pandas value_counts tie order is version-unstable, the wasm op pins
#      it -- see docs/reference/rust4pm-wasm-beam.md).
#   3. examples/activity_position.py -- per-activity histogram of 0-based
#      within-trace positions, on the receipt dataset (the repo's committed
#      qualification/fixtures/receipt.xes -- same dataset the pm4py example
#      queries as receipt.csv), for the example's exact two activities.
#
# Every printed number is HARD-ASSERTED against ground truth pinned at
# authoring time: examples 1-2 against hand-derivable facts of
# running-example.xes/.pnml (perfect fit, 9-event case "3", the 8-activity
# count table), example 3 against an independent host-side XML scan of
# receipt.xes (xml.etree walk, 2026-08-30: 1434 cases; "Confirmation of
# receipt" opens every case). A failed assertion raises -> `mix run` exits
# nonzero.

defmodule PM4PyExamplesWasm do
  @moduledoc false

  @running_example_xes "qualification/fixtures/pm4py/running-example.xes"
  @running_example_pnml "qualification/fixtures/pm4py/running-example.pnml"
  @receipt_xes "qualification/fixtures/receipt.xes"

  # The first <trace> in running-example.xes is case "3" (9 events) -- the same
  # trace pm4py's example aligns as log._list[0].
  @case3_trace [
    "register request",
    "examine casually",
    "check ticket",
    "decide",
    "reinitiate request",
    "examine thoroughly",
    "check ticket",
    "decide",
    "pay compensation"
  ]

  def run do
    ensure_wasm!()
    {:ok, _pid} = BeamPM.Rust4PM.start()

    example_1_alignment()
    example_2_activities_to_alphabet()
    example_3_activity_position()

    IO.puts("\nPM4PY EXAMPLES (wasm): PASS -- all assertions held")
  end

  # -- example 1: alignment_discounted_a_star.py (standard optimal port) ------

  defp example_1_alignment do
    IO.puts("== example 1: alignment (port of alignment_discounted_a_star.py) ==")

    {:ok, %{"net_handle" => net_h, "summary" => summary}} =
      BeamPM.Rust4PM.import_pnml_path(fixture!(@running_example_pnml))

    assert!(summary["has_initial_marking"] == true, "pnml import lost the initial marking")
    assert!(summary["num_final_markings"] >= 1, "pnml import lost the final marking(s)")

    IO.puts("   net: #{summary["places"]} places / #{summary["transitions"]} transitions")
    IO.puts("   aligning first trace of running-example.xes (case \"3\", 9 events)")

    {:ok, %{"moves" => moves, "cost" => cost, "states_visited" => states}} =
      BeamPM.Rust4PM.align_trace(net_h, @case3_trace)

    IO.puts("   alignment (log side, model side; \">>\" = no move, nil = silent):")

    Enum.each(moves, fn [log_side, model_side] ->
      IO.puts("     #{inspect({log_side, model_side})}")
    end)

    IO.puts("   cost=#{cost} states_visited=#{states}")

    # running-example.pnml perfectly fits its log: cost 0, no log moves, every
    # move sync [a, a] or silent [">>", nil], sync sequence == the input trace.
    assert!(cost == 0, "expected perfect fit (cost 0), got cost=#{cost}")

    assert!(
      Enum.all?(moves, fn [_log_side, model_side] -> model_side != ">>" end),
      "expected no log moves against the perfectly fitting net"
    )

    assert!(
      Enum.all?(moves, fn
        [a, a] when is_binary(a) -> true
        [">>", nil] -> true
        _ -> false
      end),
      "expected only sync [a, a] or silent [\">>\", nil] moves, got #{inspect(moves)}"
    )

    sync_log_side = for [log_side, _] <- moves, log_side != ">>", do: log_side

    assert!(
      sync_log_side == @case3_trace,
      "sync-move log side must replay the input trace exactly"
    )

    assert!(is_integer(states) and states > 0, "states_visited must be a positive integer")

    # The discounted-exponent knob, probed against the real engine -- refused,
    # never silently ignored, never faked.
    {:error, {:engine, refusal}} =
      BeamPM.Rust4PM.align_trace(net_h, @case3_trace, %{"exponent" => 1.1})

    assert!(
      refusal =~ "unsupported: discounted cost model",
      "engine must refuse the discount exponent by name, got: #{inspect(refusal)}"
    )

    IO.puts("")
    IO.puts("   UNSUPPORTED: pm4py's VERSION_DISCOUNTED_A_STAR exponent (1.1) has no")
    IO.puts("   counterpart in process_mining 0.6.2 (per-move-kind CostFunction only).")
    IO.puts("   The alignment above is the STANDARD optimal one. Probed for real:")
    IO.puts("   engine refusal: #{refusal}")

    {:ok, %{"freed" => true}} = BeamPM.Rust4PM.free_net(net_h)
  end

  # -- example 2: activities_to_alphabet.py -----------------------------------

  defp example_2_activities_to_alphabet do
    IO.puts("\n== example 2: activities_to_alphabet (running-example.xes) ==")

    {:ok, %{"handle" => log_h}} =
      BeamPM.Rust4PM.import_xes_path(fixture!(@running_example_xes))

    {:ok, %{"mapping" => mapping, "order" => order, "num_activities" => num_activities}} =
      BeamPM.Rust4PM.activities_to_alphabet(log_h)

    IO.puts("   letter  activity                count")

    Enum.each(order, fn [activity, count] ->
      letter = Map.get(mapping, activity, "?")

      IO.puts(
        "   #{String.pad_trailing(letter, 7)} #{String.pad_trailing(activity, 23)} #{count}"
      )
    end)

    # Hand-computed from the real running-example.xes (6 traces; descending
    # event count, ties broken by first occurrence in the log -- the pinned
    # determinism rule for pandas value_counts' unstable tie order).
    assert!(num_activities == 8, "expected 8 activities, got #{num_activities}")

    assert!(
      mapping == %{
        "check ticket" => "A",
        "decide" => "B",
        "register request" => "C",
        "examine casually" => "D",
        "reinitiate request" => "E",
        "examine thoroughly" => "F",
        "pay compensation" => "G",
        "reject request" => "H"
      },
      "alphabet mapping deviates from the hand-computed table: #{inspect(mapping)}"
    )

    assert!(
      order == [
        ["check ticket", 9],
        ["decide", 9],
        ["register request", 6],
        ["examine casually", 6],
        ["reinitiate request", 3],
        ["examine thoroughly", 3],
        ["pay compensation", 3],
        ["reject request", 3]
      ],
      "activity order/counts deviate from the hand-computed table: #{inspect(order)}"
    )

    {:ok, %{"freed" => true}} = BeamPM.Rust4PM.free_log(log_h)
  end

  # -- example 3: activity_position.py (receipt dataset) ----------------------

  defp example_3_activity_position do
    IO.puts("\n== example 3: activity_position (receipt.xes) ==")

    {:ok, %{"handle" => log_h}} = BeamPM.Rust4PM.import_xes_path(fixture!(@receipt_xes))

    # Mirrors the pm4py example's two get_activity_position_summary calls.
    # Expected histograms pinned by an independent host-side xml.etree scan of
    # this exact fixture (2026-08-30): 1434 cases; "Confirmation of receipt" is
    # event 0 of every case; "T02 Check confirmation of receipt" occurs 1368
    # times across positions 1..12.
    {:ok, confirmation} = BeamPM.Rust4PM.activity_position(log_h, "Confirmation of receipt")

    {:ok, t02} =
      BeamPM.Rust4PM.activity_position(log_h, "T02 Check confirmation of receipt")

    IO.puts("   #{confirmation["activity"]}:")
    IO.puts("     positions (0-based index, count): #{inspect(confirmation["positions"])}")
    IO.puts("     total occurrences: #{confirmation["total"]}")
    IO.puts("   #{t02["activity"]}:")
    IO.puts("     positions (0-based index, count): #{inspect(t02["positions"])}")
    IO.puts("     total occurrences: #{t02["total"]}")

    assert!(
      confirmation["positions"] == [[0, 1434]] and confirmation["total"] == 1434,
      "\"Confirmation of receipt\" must open all 1434 cases, got #{inspect(confirmation)}"
    )

    assert!(
      t02["positions"] == [
        [1, 1079],
        [2, 74],
        [3, 152],
        [4, 3],
        [5, 26],
        [6, 7],
        [7, 15],
        [8, 1],
        [9, 7],
        [10, 2],
        [11, 1],
        [12, 1]
      ] and t02["total"] == 1368,
      "\"T02 Check confirmation of receipt\" histogram deviates from the " <>
        "independent XML-scan pin, got #{inspect(t02)}"
    )

    # pm4py returns {} for an activity absent from the log; the wasm op mirrors
    # that as an empty histogram, not an error.
    {:ok, %{"positions" => [], "total" => 0}} =
      BeamPM.Rust4PM.activity_position(log_h, "nonexistent activity")

    IO.puts("   (unknown activity -> empty histogram, matching pm4py's {})")

    {:ok, %{"freed" => true}} = BeamPM.Rust4PM.free_log(log_h)
  end

  # -- helpers ----------------------------------------------------------------

  defp ensure_wasm! do
    unless BeamPM.Rust4PM.wasm_built?() do
      raise BeamPM.Rust4PM.wasm_missing_reason()
    end
  end

  defp fixture!(rel_path) do
    path = Path.expand(rel_path)

    unless File.exists?(path) do
      raise "real canonical fixture not found at #{path} -- this script requires the " <>
              "committed qualification fixtures; run mix run from the project root"
    end

    path
  end

  defp assert!(condition, message) do
    unless condition do
      raise "ASSERTION FAILED: #{message}"
    end

    :ok
  end
end

PM4PyExamplesWasm.run()
