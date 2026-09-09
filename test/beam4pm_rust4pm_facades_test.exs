defmodule BeamPM.Rust4PMFacadesTest do
  @moduledoc """
  Facade-parity qualification for the two thin BEAM facades over the ONE
  rust4pm wasm engine (`process_mining` =0.6.2 compiled to wasm32-wasip1,
  hosted by `BeamPM.Rust4PM` / wasmex):

    * Erlang  -- `src/beam4pm_rust4pm.erl` (module `:beam4pm_rust4pm`)
    * Gleam   -- `gleam/src/beam4pm/rust4pm.gleam` (Erlang module
      `:beam4pm@rust4pm`, `@external` bindings)

  Both facades are delegation-only (zero process-mining computation in
  Erlang/Gleam, per the one-engine directive), so their entire contract is:
  same function names, correctly-bound arities, results passed through
  unchanged. This suite therefore asserts exact `==` PARITY of facade
  results against the Elixir wrapper's results on the same engine handles
  and the same real running-example fixtures -- parity, not re-derivation.
  Engine-level ground truth (differentials vs the rf1/rf2 native oracles,
  hand-computed pm4py semantics) is qualified separately in
  test/beam4pm_rust4pm_test.exs; a few tiny real anchors here (num_cases 6,
  cost 0, mapping "check ticket" => "A") only guard against the vacuous
  case of both sides returning an identical wrong/error term.

  Why the Erlang facade has no beam4pm_rust4pm_tests.erl under eunit:
  eunit in this repo runs under rebar3 (root rebar.config), which compiles
  src/ WITHOUT Mix dependencies -- wasmex is a hex dep of the Mix project
  only, so it is not on rebar3's code path and an eunit test could never
  start the engine. The Erlang facade is exercised for real here, in the
  Mix context, instead. Documented, not faked.

  Why Gleam runtime parity is NOT always asserted: `gleam build` only
  compile-checks the facade (`@external` declarations are not resolved at
  compile time), and `gleam test`/gleeunit runs on gleam's own toolchain
  without wasmex or the compiled wasm on its code path, so the Gleam
  toolchain CANNOT exercise the facade at runtime at all. Runtime parity is
  asserted only here, from the Mix context, by appending
  gleam/build/dev/erlang/beam4pm/ebin to the code path -- and ONLY when
  that build output exists. When it does not, the gleam describe block is a
  NAMED skip ("gleam facade not built -- run (cd gleam && gleam build)
  first"), so unbuilt-gleam runs report the un-asserted parity honestly
  rather than passing silently or faking the calls.

  Chicago-style throughout: the real wasm engine, real checked-in
  byte-identical pm4py fixtures (qualification/fixtures/pm4py/README.md for
  provenance), no mocks. A missing wasm binary is a NAMED module-level skip
  (deliberate, documented divergence from rf1's raise, per this feature's
  directive); missing fixtures still raise, rf1-style.
  """

  use ExUnit.Case, async: false

  if not BeamPM.Rust4PM.wasm_built?() do
    @moduletag skip: BeamPM.Rust4PM.wasm_missing_reason()
  end

  # Byte-identical checked-in copies of pm4py's canonical fixtures (see
  # qualification/fixtures/pm4py/README.md) -- repo-root-relative, same
  # "run mix test from the project root" convention as rf1.
  @running_example_xes Path.expand("qualification/fixtures/pm4py/running-example.xes")
  @running_example_pnml Path.expand("qualification/fixtures/pm4py/running-example.pnml")

  @gleam_ebin Path.expand("gleam/build/dev/erlang/beam4pm/ebin")

  # The first <trace> of running-example.xes (case "3") -- the same trace
  # the pm4py alignment-example port aligns; running-example.pnml fits it
  # perfectly, so the optimal alignment costs 0.
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

  # The gleam-built Erlang module for gleam/src/beam4pm/rust4pm.gleam. Calls
  # go through apply/3 so this test module compiles warning-free when the
  # gleam build output (and thus the module) is absent -- resolution is
  # deferred to runtime, matching the conditional named skip below.
  @gleam_mod :beam4pm@rust4pm
  defp gleam(fun, args), do: apply(@gleam_mod, fun, args)

  defp real_fixture!(path) do
    unless File.exists?(path) do
      raise "real canonical pm4py fixture not found at #{path} -- this suite requires the " <>
              "byte-identical checked-in copies of pm4py's tests/input_data fixtures " <>
              "(qualification/fixtures/pm4py/README.md), and mix test must run from the " <>
              "project root"
    end

    path
  end

  setup_all do
    {:ok, engine_pid} = BeamPM.Rust4PM.start()

    if File.exists?(@gleam_ebin) do
      true = Code.append_path(@gleam_ebin)
    end

    xes_content = File.read!(real_fixture!(@running_example_xes))
    pnml_content = File.read!(real_fixture!(@running_example_pnml))

    # One shared log handle + one shared net handle, imported through the
    # Elixir wrapper; parity tests call BOTH facades on these SAME handles
    # (handles are engine-global, so every facade sees the same objects).
    # Tests that free anything import their own private handles instead.
    {:ok, %{"handle" => log_h}} = BeamPM.Rust4PM.import_xes(xes_content)

    {:ok, %{"net_handle" => net_h, "summary" => net_summary}} =
      BeamPM.Rust4PM.import_pnml(pnml_content)

    %{
      engine_pid: engine_pid,
      xes_content: xes_content,
      pnml_content: pnml_content,
      log_h: log_h,
      net_h: net_h,
      net_summary: net_summary
    }
  end

  describe "erlang facade (:beam4pm_rust4pm, src/beam4pm_rust4pm.erl)" do
    test "start/0 resolves to the same named engine process as the elixir wrapper", ctx do
      assert {:ok, pid} = :beam4pm_rust4pm.start()
      assert {:ok, ^pid} = BeamPM.Rust4PM.start()
      assert pid == ctx.engine_pid
    end

    test "import_xes, import_xes_path, import_xes_gz: all land on identical, facade-parity logs",
         ctx do
      # import_xes: same wire shape, fresh handle, identical stats to the
      # elixir import.
      assert {:ok, %{"handle" => erl_h}} = :beam4pm_rust4pm.import_xes(ctx.xes_content)
      assert is_integer(erl_h)
      assert erl_h != ctx.log_h

      # Same handle through both facades: exact term equality.
      assert :beam4pm_rust4pm.log_stats(erl_h) == BeamPM.Rust4PM.log_stats(erl_h)

      # Erlang-imported log vs elixir-imported log of the same content:
      # identical stats (non-vacuity anchors: the real running-example
      # constants, 6 cases / 6 variants / 8 activities).
      assert {:ok, erl_stats} = :beam4pm_rust4pm.log_stats(erl_h)
      assert {:ok, ex_stats} = BeamPM.Rust4PM.log_stats(ctx.log_h)
      assert erl_stats == ex_stats
      assert erl_stats["num_cases"] == 6
      assert erl_stats["num_variants"] == 6
      assert erl_stats["num_activities"] == 8

      assert {:ok, %{"freed" => true}} = :beam4pm_rust4pm.free_log(erl_h)

      # import_xes_path and import_xes_gz: the identical underlying
      # property (stats parity against the elixir-imported baseline) over
      # two more log-import entry points.
      assert {:ok, %{"handle" => path_h}} =
               :beam4pm_rust4pm.import_xes_path(@running_example_xes)

      assert {:ok, %{"handle" => gz_h}} =
               :beam4pm_rust4pm.import_xes_gz(:zlib.gzip(ctx.xes_content))

      base = BeamPM.Rust4PM.log_stats(ctx.log_h)
      assert :beam4pm_rust4pm.log_stats(path_h) == base
      assert :beam4pm_rust4pm.log_stats(gz_h) == base

      assert {:ok, %{"freed" => true}} = :beam4pm_rust4pm.free_log(path_h)
      assert {:ok, %{"freed" => true}} = :beam4pm_rust4pm.free_log(gz_h)
    end

    test "read ops on the same log handle: erlang == elixir, exact", ctx do
      h = ctx.log_h

      assert :beam4pm_rust4pm.log_stats(h) == BeamPM.Rust4PM.log_stats(h)
      assert :beam4pm_rust4pm.discover_dfg(h) == BeamPM.Rust4PM.discover_dfg(h)
      assert :beam4pm_rust4pm.top_n_variants(h, 2) == BeamPM.Rust4PM.top_n_variants(h, 2)
      assert :beam4pm_rust4pm.activities_to_alphabet(h) == BeamPM.Rust4PM.activities_to_alphabet(h)

      assert :beam4pm_rust4pm.activity_position(h, "decide") ==
               BeamPM.Rust4PM.activity_position(h, "decide")

      # Non-vacuity: these parities are over real {:ok, _} results.
      assert {:ok, %{"edges" => edges}} = :beam4pm_rust4pm.discover_dfg(h)
      assert length(edges) > 0

      assert {:ok, %{"mapping" => %{"check ticket" => "A"}}} =
               :beam4pm_rust4pm.activities_to_alphabet(h)

      assert {:ok, %{"positions" => [[3, 6] | _], "total" => 9}} =
               :beam4pm_rust4pm.activity_position(h, "decide")
    end

    test "import_pnml + align_trace: erlang == elixir on the same net, real optimal alignment", ctx do
      assert {:ok, %{"net_handle" => erl_net, "summary" => erl_summary}} =
               :beam4pm_rust4pm.import_pnml(ctx.pnml_content)

      # Same PNML content => same summary as the setup_all elixir import.
      assert erl_summary == ctx.net_summary
      assert {:ok, %{"freed" => true}} = :beam4pm_rust4pm.free_net(erl_net)

      # Same net handle through both facades: exact term equality.
      erl_aligned = :beam4pm_rust4pm.align_trace(ctx.net_h, @case3_trace)
      assert erl_aligned == BeamPM.Rust4PM.align_trace(ctx.net_h, @case3_trace)

      # Real anchor: running-example.pnml perfectly fits case "3" -- cost 0,
      # every move sync [a, a] or silent [">>", nil], no log moves, and the
      # log-side subsequence is exactly the input trace.
      assert {:ok, %{"cost" => 0, "moves" => moves}} = erl_aligned

      assert Enum.all?(moves, fn
               [a, a] when is_binary(a) -> true
               [">>", nil] -> true
               _ -> false
             end)

      log_side = for [l, _] <- moves, l != ">>", do: l
      assert log_side == @case3_trace
    end

    test "the UNSUPPORTED discounted-cost guard is identical through both facades", ctx do
      opts = %{"exponent" => 1.1}

      erl_err = :beam4pm_rust4pm.align_trace(ctx.net_h, @case3_trace, opts)
      assert erl_err == BeamPM.Rust4PM.align_trace(ctx.net_h, @case3_trace, opts)
      assert {:error, {:engine, msg}} = erl_err
      assert msg =~ "unsupported: discounted cost model"
    end

    test "discover_alphappp + align_variants + compute_fitness parity on the same handles", ctx do
      assert {:ok, %{"net_handle" => erl_net, "summary" => _}} =
               :beam4pm_rust4pm.discover_alphappp(ctx.log_h)

      assert :beam4pm_rust4pm.align_variants(ctx.log_h, erl_net) ==
               BeamPM.Rust4PM.align_variants(ctx.log_h, erl_net)

      fitness = :beam4pm_rust4pm.compute_fitness(ctx.log_h, erl_net)
      assert fitness == BeamPM.Rust4PM.compute_fitness(ctx.log_h, erl_net)

      # Non-vacuity: real aggregates over the real 6 variants.
      assert {:ok, %{"log_fitness" => lf, "num_variants_aligned" => 6}} = fitness
      assert is_float(lf)

      assert {:ok, %{"alignments" => alignments}} =
               :beam4pm_rust4pm.align_variants(ctx.log_h, erl_net)

      assert length(alignments) == 6

      assert {:ok, %{"freed" => true}} = :beam4pm_rust4pm.free_net(erl_net)
    end

    test "free_log + unknown-handle error path is identical through both facades", ctx do
      assert {:ok, %{"handle" => h}} = :beam4pm_rust4pm.import_xes(ctx.xes_content)
      assert {:ok, %{"freed" => true}} = :beam4pm_rust4pm.free_log(h)

      erl_err = :beam4pm_rust4pm.log_stats(h)
      assert erl_err == BeamPM.Rust4PM.log_stats(h)
      assert {:error, {:engine, "unknown log handle " <> _}} = erl_err
    end
  end

  describe "gleam facade (:beam4pm@rust4pm, gleam/src/beam4pm/rust4pm.gleam)" do
    # Runtime parity is only assertable when gleam build output exists on
    # disk (see moduledoc); otherwise this whole block is a NAMED skip --
    # gleam parity is then explicitly NOT asserted, not silently green.
    if not File.exists?(@gleam_ebin) do
      @describetag skip: "gleam facade not built -- run (cd gleam && gleam build) first"
    end

    test "read ops on the same log handle: gleam == elixir, exact", ctx do
      h = ctx.log_h

      # Gleam's Result(Dynamic, Dynamic) IS the runtime {:ok, _}/{:error, _}
      # tuple, so exact term equality against the Elixir wrapper is the
      # correct (and complete) parity check.
      assert gleam(:log_stats, [h]) == BeamPM.Rust4PM.log_stats(h)
      assert gleam(:discover_dfg, [h]) == BeamPM.Rust4PM.discover_dfg(h)
      assert gleam(:top_n_variants, [h, 3]) == BeamPM.Rust4PM.top_n_variants(h, 3)
      assert gleam(:activities_to_alphabet, [h]) == BeamPM.Rust4PM.activities_to_alphabet(h)

      assert gleam(:activity_position, [h, "decide"]) ==
               BeamPM.Rust4PM.activity_position(h, "decide")

      # Non-vacuity: parity is over a real {:ok, map} with the real
      # running-example constants.
      assert {:ok, %{"num_cases" => 6, "num_variants" => 6}} = gleam(:log_stats, [h])

      assert {:ok, %{"positions" => [[3, 6] | _], "total" => 9}} =
               gleam(:activity_position, [h, "decide"])
    end

    test "align_trace through the gleam extern returns the same optimal alignment", ctx do
      gleam_aligned = gleam(:align_trace, [ctx.net_h, @case3_trace])
      assert gleam_aligned == BeamPM.Rust4PM.align_trace(ctx.net_h, @case3_trace)
      assert {:ok, %{"cost" => 0, "moves" => moves}} = gleam_aligned
      assert length(moves) >= length(@case3_trace)
    end

    test "compute_fitness through the gleam extern matches the elixir wrapper", ctx do
      assert {:ok, %{"net_handle" => net, "summary" => _}} = gleam(:discover_alphappp, [ctx.log_h])

      fitness = gleam(:compute_fitness, [ctx.log_h, net])
      assert fitness == BeamPM.Rust4PM.compute_fitness(ctx.log_h, net)
      assert {:ok, %{"num_variants_aligned" => 6}} = fitness

      assert {:ok, %{"freed" => true}} = gleam(:free_net, [net])
    end
  end
end
