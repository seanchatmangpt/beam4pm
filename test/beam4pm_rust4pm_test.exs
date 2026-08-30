defmodule BeamPM.Rust4PMTest do
  @moduledoc """
  Chicago-style qualification of `BeamPM.Rust4PM`: the ONE rust4pm
  (`process_mining` =0.6.2) engine compiled to wasm32-wasip1 and hosted in
  BEAM via wasmex, exercised for real against real canonical fixtures and
  differentially against the two real native oracle binaries built from the
  SAME crate version:

    * T1 -- `log_stats` + `discover_dfg` vs `rf1-dfg-oracle` on the real
      29MB InternationalDeclarations.xes: byte-level decoded-JSON equality
      (same crate, two compilation targets -- no tolerance).
    * T2 -- `discover_alphappp` + `compute_fitness` vs
      `rf2-conformance-oracle` on running-example.xes: fitness aggregates
      within rf2's own 1.0e-9 float tolerance, counts exact.
    * T3 -- the pm4py `alignment_discounted_a_star.py` workflow port:
      `import_pnml` + `align_trace` on the file's first trace (case "3"),
      standard optimal alignment (cost 0, sync/silent moves only), plus the
      honest UNSUPPORTED guard for the discounted-cost exponent
      (process_mining 0.6.2 has only the per-move-kind CostFunction).
    * T4 -- `align_variants` shape on running-example.xes vs the PNML.
      NOTE (correction to the reference design's expectation, verified by
      parsing the real fixture): running-example.xes has 6 traces that are
      ALL DISTINCT variants (frequency 1 each) -- e.g. case 2 is
      `register request, check ticket, examine casually, ...` while case 6
      is `register request, examine casually, check ticket, ...` -- so the
      assertions here pin 6 variants x frequency 1, multiset equality (tie
      order among equal frequencies is not part of the wire contract).
    * T5 -- `activities_to_alphabet`, hand-computed from the real XES
      (descending event count, ties broken by first occurrence -- the
      port's documented determinism pin), plus the bijective base-26
      overflow (`"AA".."AH"`) on InternationalDeclarations' 34 activities.
    * T6 -- `activity_position`, hand-computed 0-based per-trace position
      histograms for every activity in running-example.xes.
    * T7 -- handle discipline + the memory-ownership contract (unknown
      handles, log-handle-in-net-slot, real import failure text, and a
      200-cycle import/free leak smoke).
    * T8 -- `import_xes_gz` round-trip equivalence with the uncompressed
      import.

  Absence semantics: a missing wasm artifact is a NAMED SKIP (deliberate,
  documented divergence from rf1's raise, per this feature's directive);
  missing fixtures/oracle binaries still RAISE with rf1's exact wording --
  fixture absence is an environment defect, never a silent pass. No mocks
  anywhere: every assertion runs the real wasm engine, real oracle
  binaries, and real fixtures.
  """

  use ExUnit.Case, async: false

  alias BeamPM.Rust4PM

  if not BeamPM.Rust4PM.wasm_built?() do
    @moduletag skip: BeamPM.Rust4PM.wasm_missing_reason()
  end

  # Real work on a real 29MB log + real optimal alignments: give every test
  # in this module headroom past ExUnit's 60s default.
  @moduletag timeout: 300_000

  # The real canonical scale dataset (spike-proven: 6449 cases / 753
  # variants / 34 activities / 196 DFG edges) -- machine-local by design,
  # same dataset the spike and rf1's oracle qualification used.
  @intl_xes Path.expand("~/wasm4pm/data/InternationalDeclarations.xes")

  # Byte-identical checked-in copies of the pm4py canonical fixtures
  # (provenance: /Users/sac/chatmangpt/pm4py/tests/input_data/, see
  # qualification/fixtures/pm4py/README.md).
  @running_example_xes Path.expand("qualification/fixtures/pm4py/running-example.xes")
  @running_example_pnml Path.expand("qualification/fixtures/pm4py/running-example.pnml")

  # The first <trace> in running-example.xes is case "3" -- verified by
  # parsing the real file, not assumed.
  @first_trace [
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

  # All 6 variants of running-example.xes (each occurs exactly once),
  # hand-extracted from the real file.
  @all_variants [
    [
      "register request",
      "examine casually",
      "check ticket",
      "decide",
      "reinitiate request",
      "examine thoroughly",
      "check ticket",
      "decide",
      "pay compensation"
    ],
    ["register request", "check ticket", "examine casually", "decide", "pay compensation"],
    ["register request", "examine thoroughly", "check ticket", "decide", "reject request"],
    ["register request", "examine casually", "check ticket", "decide", "pay compensation"],
    [
      "register request",
      "examine casually",
      "check ticket",
      "decide",
      "reinitiate request",
      "check ticket",
      "examine casually",
      "decide",
      "reinitiate request",
      "examine casually",
      "check ticket",
      "decide",
      "reject request"
    ],
    ["register request", "check ticket", "examine thoroughly", "decide", "reject request"]
  ]

  defp rf1_oracle_bin do
    path = Path.expand("native/rf1-dfg-oracle/target/release/rf1-dfg-oracle")

    unless File.exists?(path) do
      raise "rf1-dfg-oracle binary not found at #{path} -- run " <>
              "`cargo build --release` in native/rf1-dfg-oracle/ first, and run mix test " <>
              "from the project root"
    end

    path
  end

  defp rf2_oracle_bin do
    path = Path.expand("native/rf2-conformance-oracle/target/release/rf2-conformance-oracle")

    unless File.exists?(path) do
      raise "rf2-conformance-oracle binary not found at #{path} -- run " <>
              "`cargo build --release` in native/rf2-conformance-oracle/ first, and run " <>
              "mix test from the project root"
    end

    path
  end

  defp real_fixture!(path) do
    unless File.exists?(path) do
      raise "real canonical XES fixture not found at #{path} -- this stream requires the " <>
              "real wasm4pm canonical datasets"
    end

    path
  end

  # Same payload-file + shell-redirect shape as rf1's own qualification
  # suite: the oracle reads stdin to EOF, Erlang ports have no stdin
  # half-close, and this is the verified-robust invocation.
  defp shell_invoke_oracle!(oracle_bin, payload_map) do
    payload_file =
      Path.join(
        System.tmp_dir!(),
        "rust4pm-diff-probe-#{System.unique_integer([:positive])}.json"
      )

    File.write!(payload_file, JSON.encode!(payload_map))
    {raw, 0} = System.shell("#{oracle_bin} < #{payload_file}")
    File.rm(payload_file)
    JSON.decode!(String.trim_trailing(raw, "\n"))
  end

  setup_all do
    if Rust4PM.wasm_built?() do
      {:ok, _pid} = Rust4PM.start()

      {:ok, %{"handle" => intl_h}} = Rust4PM.import_xes_path(real_fixture!(@intl_xes))

      {:ok, %{"handle" => run_h}} = Rust4PM.import_xes_path(real_fixture!(@running_example_xes))

      {:ok, %{"net_handle" => pnml_h, "summary" => pnml_summary}} =
        Rust4PM.import_pnml_path(real_fixture!(@running_example_pnml))

      on_exit(fn ->
        # Best-effort: return the shared handles' memory to the engine's
        # allocator (the named engine process outlives this module).
        Rust4PM.free_log(intl_h)
        Rust4PM.free_log(run_h)
        Rust4PM.free_net(pnml_h)
      end)

      {:ok, intl: intl_h, run: run_h, pnml: pnml_h, pnml_summary: pnml_summary}
    else
      :ok
    end
  end

  test "T1: engine log_stats + discover_dfg vs the real rf1-dfg-oracle on the real 29MB " <>
         "InternationalDeclarations.xes -- decoded-JSON exact equality, same crate two targets",
       %{intl: intl_h} do
    assert {:ok, stats} = Rust4PM.log_stats(intl_h)
    assert {:ok, dfg} = Rust4PM.discover_dfg(intl_h)

    oracle =
      shell_invoke_oracle!(rf1_oracle_bin(), %{
        "op" => "dfg_discover",
        "xes_path" => real_fixture!(@intl_xes)
      })

    # Spike-proven anchors first (guards against BOTH sides drifting
    # together), then engine == oracle exact equality.
    assert stats["num_cases"] == 6449
    assert stats["num_variants"] == 753
    assert stats["num_activities"] == 34
    assert stats["top_variant_count"] == 1369
    assert length(dfg["edges"]) == 196

    assert stats["num_cases"] == oracle["num_cases"]
    assert stats["num_variants"] == oracle["num_variants"]
    assert stats["top_variant"] == oracle["top_variant"]

    # Both sides emit ALL activity names sorted lexicographically (byte
    # order) -- exact list equality, no set-normalization.
    assert stats["activities"] == oracle["activities"]
    assert stats["activities"] == Enum.sort(stats["activities"])

    # Both sides sort edges by (source, target): exact list equality
    # INCLUDING order.
    assert dfg["edges"] == oracle["edges"]
  end

  test "T2: engine discover_alphappp + compute_fitness vs the real rf2-conformance-oracle on " <>
         "running-example.xes -- fitness aggregates within rf2's 1.0e-9 tolerance, counts exact",
       %{run: run_h} do
    assert {:ok, %{"net_handle" => net_h, "summary" => summary}} =
             Rust4PM.discover_alphappp(run_h)

    assert {:ok, fitness} = Rust4PM.compute_fitness(run_h, net_h)

    oracle =
      shell_invoke_oracle!(rf2_oracle_bin(), %{
        "op" => "conformance",
        "xes_path" => real_fixture!(@running_example_xes),
        "case_attr_key" => "concept:name"
      })

    assert_in_delta fitness["log_fitness"], oracle["fitness"]["log_fitness"], 1.0e-9
    assert_in_delta fitness["average_fitness"], oracle["fitness"]["average_fitness"], 1.0e-9

    assert_in_delta fitness["perfectly_fitting_frac"],
                    oracle["fitness"]["perfectly_fitting_frac"],
                    1.0e-9

    assert fitness["total_costs"] == oracle["fitness"]["total_costs"]
    assert fitness["num_variants_aligned"] == oracle["num_variants_aligned"]

    # Ground truth from the fixture itself: 6 traces, all distinct variants.
    assert fitness["num_variants_aligned"] == 6

    assert summary["places"] == oracle["model_place_count"]
    assert summary["transitions"] == oracle["model_transition_count"]

    assert {:ok, %{"freed" => true}} = Rust4PM.free_net(net_h)
  end

  test "T3: pm4py alignment_discounted_a_star workflow port -- align_trace of case \"3\" " <>
         "against the real running-example.pnml is the cost-0 standard optimal alignment, " <>
         "and the discount exponent is honestly UNSUPPORTED",
       %{pnml: pnml_h, pnml_summary: summary} do
    # Honest preconditions read straight off the real PNML: 9 places, 10
    # transitions of which 2 are silent ($invisible$ taus), 22 arcs, and
    # BOTH markings present (alignment fails without them).
    assert summary["places"] == 9
    assert summary["transitions"] == 10
    assert summary["silent_transitions"] == 2
    assert summary["arcs"] == 22
    assert summary["has_initial_marking"] == true
    assert summary["num_final_markings"] == 1

    assert {:ok, %{"moves" => moves, "cost" => cost, "states_visited" => states_visited}} =
             Rust4PM.align_trace(pnml_h, @first_trace)

    # running-example.pnml perfectly fits this log: optimal cost 0.
    assert cost == 0
    assert is_integer(states_visited) and states_visited > 0

    # No log moves at all (a log move renders as [activity, ">>"]).
    refute Enum.any?(moves, fn [_log_side, model_side] -> model_side == ">>" end)

    # Every move is either a sync move [a, a] or a silent model move
    # [">>", nil] (pm4py renders silent model moves as ('>>', None)).
    assert Enum.all?(moves, fn
             [a, a] when is_binary(a) -> a != ">>"
             [">>", nil] -> true
             _other -> false
           end)

    # The log-side non-">>" subsequence IS the input trace: 9 sync moves in
    # trace order.
    log_side_activities =
      moves
      |> Enum.map(fn [log_side, _model_side] -> log_side end)
      |> Enum.reject(&(&1 == ">>"))

    assert log_side_activities == @first_trace

    # The UNSUPPORTED guard: pm4py's VERSION_DISCOUNTED_A_STAR exponent has
    # no counterpart in process_mining 0.6.2's per-move-kind CostFunction.
    # Never silently ignored, never faked.
    assert {:error, {:engine, msg}} =
             Rust4PM.align_trace(pnml_h, @first_trace, %{"exponent" => 1.1})

    assert msg =~ "unsupported: discounted cost model"
  end

  test "T4: align_variants over running-example.xes vs the PNML -- 6 distinct variants " <>
         "(frequency 1 each, verified from the real file), all perfectly fitting at cost 0",
       %{run: run_h, pnml: pnml_h} do
    assert {:ok, %{"alignments" => alignments}} = Rust4PM.align_variants(run_h, pnml_h)

    # The real fixture has 6 traces that are ALL distinct variants (this
    # corrects the reference design's 4-variant expectation; see moduledoc).
    assert length(alignments) == 6
    assert Enum.map(alignments, & &1["frequency"]) |> Enum.sum() == 6
    assert Enum.all?(alignments, &(&1["frequency"] == 1))

    # Every variant aligned successfully -- an "alignment" on every entry,
    # never an "error".
    assert Enum.all?(alignments, &Map.has_key?(&1, "alignment"))
    refute Enum.any?(alignments, &Map.has_key?(&1, "error"))

    # The PNML perfectly fits the whole log: every optimal cost is 0.
    assert Enum.all?(alignments, &(&1["alignment"]["cost"] == 0))

    # Multiset equality with the 6 real variant sequences (tie order among
    # equal frequencies is not part of the wire contract, so compare
    # sorted, not positionally).
    assert Enum.sort(Enum.map(alignments, & &1["activities"])) == Enum.sort(@all_variants)
  end

  test "T5: activities_to_alphabet -- pm4py semantics (descending event count, first-seen " <>
         "tie-break) hand-computed from the real running-example.xes, plus base-26 overflow " <>
         "on InternationalDeclarations",
       %{run: run_h, intl: intl_h} do
    assert {:ok, %{"mapping" => mapping, "order" => order, "num_activities" => 8}} =
             Rust4PM.activities_to_alphabet(run_h)

    # Hand-computed from the real file: check ticket 9, decide 9,
    # register request 6, examine casually 6, then the four 3-count
    # activities in first-seen order.
    assert mapping == %{
             "check ticket" => "A",
             "decide" => "B",
             "register request" => "C",
             "examine casually" => "D",
             "reinitiate request" => "E",
             "examine thoroughly" => "F",
             "pay compensation" => "G",
             "reject request" => "H"
           }

    assert order == [
             ["check ticket", 9],
             ["decide", 9],
             ["register request", 6],
             ["examine casually", 6],
             ["reinitiate request", 3],
             ["examine thoroughly", 3],
             ["pay compensation", 3],
             ["reject request", 3]
           ]

    # Bijective base-26 overflow on the 34-activity intl log: order indexes
    # 26..33 map to "AA".."AH" (index 26 == "AA" exactly, per the pinned
    # pm4py chr-prepend loop).
    assert {:ok, %{"mapping" => intl_mapping, "order" => intl_order, "num_activities" => 34}} =
             Rust4PM.activities_to_alphabet(intl_h)

    assert length(intl_order) == 34

    for {letter, idx} <- Enum.with_index(~w(AA AB AC AD AE AF AG AH), 26) do
      [activity, _count] = Enum.at(intl_order, idx)
      assert intl_mapping[activity] == letter
    end
  end

  test "T6: activity_position -- pm4py get_activity_position_summary semantics (full 0-based " <>
         "position histogram), hand-computed for every activity in running-example.xes",
       %{run: run_h} do
    positions = fn activity ->
      assert {:ok, %{"activity" => ^activity, "positions" => pos, "total" => total}} =
               Rust4PM.activity_position(run_h, activity)

      assert total == pos |> Enum.map(fn [_idx, count] -> count end) |> Enum.sum()
      pos
    end

    assert positions.("register request") == [[0, 6]]
    assert positions.("decide") == [[3, 6], [7, 2], [11, 1]]
    assert positions.("check ticket") == [[1, 2], [2, 4], [5, 1], [6, 1], [10, 1]]
    assert positions.("examine casually") == [[1, 3], [2, 1], [6, 1], [9, 1]]
    assert positions.("examine thoroughly") == [[1, 1], [2, 1], [5, 1]]
    assert positions.("reinitiate request") == [[4, 2], [8, 1]]
    assert positions.("pay compensation") == [[4, 2], [8, 1]]
    assert positions.("reject request") == [[4, 2], [12, 1]]

    # Unknown activity is an honest empty histogram (pm4py returns {}),
    # never an error.
    assert {:ok, %{"activity" => "nonexistent", "positions" => [], "total" => 0}} =
             Rust4PM.activity_position(run_h, "nonexistent")
  end

  test "T7: handle discipline + memory contract -- unknown handles, typed handle spaces, " <>
         "real import failure text, and a 200-cycle import/free leak smoke" do
    content = File.read!(real_fixture!(@running_example_xes))

    # free_log genuinely invalidates the handle.
    assert {:ok, %{"handle" => h}} = Rust4PM.import_xes(content)
    assert {:ok, %{"freed" => true}} = Rust4PM.free_log(h)
    assert {:error, {:engine, msg}} = Rust4PM.log_stats(h)
    assert msg =~ "unknown log handle"

    # Handle spaces are typed: a LOG handle in the NET slot is an unknown
    # NET handle, never an alias.
    assert {:ok, %{"handle" => h2}} = Rust4PM.import_xes(content)
    assert {:error, {:engine, net_msg}} = Rust4PM.align_variants(h2, h2)
    assert net_msg =~ "unknown net handle"
    assert {:ok, %{"freed" => true}} = Rust4PM.free_log(h2)

    # A real parse failure surfaces the engine's real error text, never a
    # handle to an empty log.
    assert {:error, {:engine, import_msg}} = Rust4PM.import_xes("not xml")
    assert import_msg =~ "xes import failed"

    # Leak smoke over the fixed memory-ownership contract (r4pm_call
    # consumes the request buffer; the host frees the response buffer):
    # 200 sequential import+free cycles must all complete.
    for _cycle <- 1..200 do
      assert {:ok, %{"handle" => hc}} = Rust4PM.import_xes(content)
      assert {:ok, %{"freed" => true}} = Rust4PM.free_log(hc)
    end
  end

  test "T8: import_xes_gz -- gzipped running-example.xes imports to a log with identical " <>
         "log_stats to the uncompressed import",
       %{run: run_h} do
    content = File.read!(real_fixture!(@running_example_xes))

    assert {:ok, %{"handle" => gz_h}} = Rust4PM.import_xes_gz(:zlib.gzip(content))
    assert {:ok, gz_stats} = Rust4PM.log_stats(gz_h)
    assert {:ok, plain_stats} = Rust4PM.log_stats(run_h)

    assert gz_stats == plain_stats
    assert gz_stats["num_cases"] == 6

    assert {:ok, %{"freed" => true}} = Rust4PM.free_log(gz_h)
  end
end
