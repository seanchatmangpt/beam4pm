defmodule BeamPM.FerroplanFacadesTest do
  @moduledoc """
  Facade-parity qualification for the two thin BEAM facades over the ONE
  ferroplan wasm engine (native/ferroplan submodule compiled to
  wasm32-wasip1, hosted by `BeamPM.Ferroplan` / wasmex):

    * Erlang -- `src/beam4pm_ferroplan.erl` (module `:beam4pm_ferroplan`)
    * Gleam  -- `gleam/src/beam4pm/ferroplan.gleam` (Erlang module
      `:beam4pm@ferroplan`, `@external` bindings)

  Both facades are delegation-only (zero planning computation in
  Erlang/Gleam, per the one-engine-per-domain directive), so their entire
  contract is: same function names, correctly-bound arities, results
  passed through unchanged. This suite asserts exact `==` PARITY of
  facade results against the Elixir wrapper's results on the SAME session
  handle (handles are engine-global -- every facade sees the same
  session), plus real content assertions so parity does not degenerate
  into "both sides return the same wrong/error term" vacuously.

  Why the Erlang facade has no beam4pm_ferroplan_tests.erl under eunit:
  same reason as beam4pm_rust4pm.erl -- eunit runs under rebar3, which
  compiles src/ WITHOUT Mix dependencies, so wasmex is never on rebar3's
  code path. Exercised for real here instead, in the Mix context.

  Why Gleam runtime parity is NOT always asserted: `gleam build` only
  compile-checks the facade; `gleam test`/gleeunit runs on Gleam's own
  toolchain without wasmex on its path, so runtime parity is asserted
  only here, by appending gleam/build/dev/erlang/beam4pm/ebin to the code
  path -- and ONLY when that build output exists. Absent, the gleam
  describe block is a NAMED skip, same convention as
  BeamPM.Rust4PMFacadesTest.

  Chicago-style throughout: the real wasm engine, a real classical
  planning domain, no mocks.
  """

  use ExUnit.Case, async: false

  if not BeamPM.Ferroplan.wasm_built?() do
    @moduletag skip: BeamPM.Ferroplan.wasm_missing_reason()
  end

  @gleam_ebin Path.expand("gleam/build/dev/erlang/beam4pm/ebin")

  # The same classic rocket/logistics-shaped toy domain used by
  # BeamPM.FerroplanTest -- one-step corridor plan, small and fast enough
  # to run through every facade many times over.
  @domain """
  (define (domain rooms)
    (:requirements :strips :typing :action-costs)
    (:types room)
    (:predicates (at ?r - room) (link ?a - room ?b - room))
    (:functions (score))
    (:action go
      :parameters (?a - room ?b - room)
      :precondition (and (at ?a) (link ?a ?b))
      :effect (and (at ?b) (not (at ?a)))))
  """

  @problem """
  (define (problem two-room)
    (:domain rooms)
    (:objects a b - room)
    (:init (at a) (link a b) (= (score) 0))
    (:goal (at b)))
  """

  # The gleam-built Erlang module for gleam/src/beam4pm/ferroplan.gleam.
  # Calls go through apply/3 so this test module compiles warning-free
  # when the gleam build output (and thus the module) is absent --
  # resolution is deferred to runtime, matching the conditional named
  # skip below.
  @gleam_mod :beam4pm@ferroplan
  defp gleam(fun, args), do: apply(@gleam_mod, fun, args)

  setup_all do
    {:ok, engine_pid} = BeamPM.Ferroplan.start()

    if File.exists?(@gleam_ebin) do
      true = Code.append_path(@gleam_ebin)
    end

    # One shared session handle, minted through the Elixir wrapper; parity
    # tests call ALL THREE facades on this SAME handle (handles are
    # engine-global, so every facade sees the same session). Tests that
    # free anything mint their own private handle instead.
    {:ok, %{"handle" => session_h}} = BeamPM.Ferroplan.session_new(@domain, @problem)

    %{engine_pid: engine_pid, session_h: session_h}
  end

  describe "erlang facade (:beam4pm_ferroplan, src/beam4pm_ferroplan.erl)" do
    test "start/0 resolves to the same named engine process as the elixir wrapper", ctx do
      assert {:ok, pid} = :beam4pm_ferroplan.start()
      assert {:ok, ^pid} = BeamPM.Ferroplan.start()
      assert pid == ctx.engine_pid
    end

    test "plan/2 matches the elixir wrapper's real solve, byte for byte" do
      elixir_result = BeamPM.Ferroplan.plan(@domain, @problem)
      erlang_result = :beam4pm_ferroplan.plan(@domain, @problem)
      assert erlang_result == elixir_result
      assert {:ok, sol} = erlang_result
      assert sol["solved"] == true
      assert sol["plan"]["length"] == 1
    end

    test "plan_production/2 matches the elixir wrapper's real envelope" do
      elixir_result = BeamPM.Ferroplan.plan_production(@domain, @problem)
      erlang_result = :beam4pm_ferroplan.plan_production(@domain, @problem)
      assert erlang_result == elixir_result
      assert {:ok, envelope} = erlang_result
      assert envelope["outcome"] == "solved"
    end

    test "readiness/0 and version/0 match the elixir wrapper" do
      assert :beam4pm_ferroplan.readiness() == BeamPM.Ferroplan.readiness()
      assert :beam4pm_ferroplan.version() == BeamPM.Ferroplan.version()
      assert {:ok, %{"version" => v}} = :beam4pm_ferroplan.version()
      assert v =~ ~r/^\d+\.\d+\.\d+$/
    end

    test "explain/3 matches the elixir wrapper on a real solved plan" do
      {:ok, sol} = BeamPM.Ferroplan.plan(@domain, @problem)
      elixir_result = BeamPM.Ferroplan.explain(@domain, @problem, sol["plan"])
      erlang_result = :beam4pm_ferroplan.explain(@domain, @problem, sol["plan"])
      assert erlang_result == elixir_result
      assert {:ok, _explanation} = erlang_result
    end

    test "session_think/session_step/session_suffix/session_advance parity on the shared handle",
         ctx do
      elixir_think = BeamPM.Ferroplan.session_think(ctx.session_h, 10_000, 64)
      erlang_think = :beam4pm_ferroplan.session_think(ctx.session_h, 10_000, 64)
      assert erlang_think == elixir_think
      assert {:ok, sol} = erlang_think
      assert sol["solved"] == true

      assert :beam4pm_ferroplan.session_valid(ctx.session_h) ==
               BeamPM.Ferroplan.session_valid?(ctx.session_h)

      assert :beam4pm_ferroplan.session_has_plan(ctx.session_h) ==
               BeamPM.Ferroplan.session_has_plan?(ctx.session_h)

      elixir_step = BeamPM.Ferroplan.session_step(ctx.session_h)
      erlang_step = :beam4pm_ferroplan.session_step(ctx.session_h)
      assert erlang_step == elixir_step
      assert {:ok, step} = erlang_step
      refute is_nil(step)

      elixir_suffix = BeamPM.Ferroplan.session_suffix(ctx.session_h)
      erlang_suffix = :beam4pm_ferroplan.session_suffix(ctx.session_h)
      assert erlang_suffix == elixir_suffix

      assert :beam4pm_ferroplan.session_advance(ctx.session_h) ==
               BeamPM.Ferroplan.session_advance(ctx.session_h)
    end

    test "session_set_fact / session_fact parity on a private handle" do
      {:ok, %{"handle" => h}} = BeamPM.Ferroplan.session_new(@domain, @problem)

      elixir_set = BeamPM.Ferroplan.session_set_fact(h, "(at a)", false)
      erlang_set = :beam4pm_ferroplan.session_set_fact(h, "(at a)", false)
      assert erlang_set == elixir_set

      elixir_fact = BeamPM.Ferroplan.session_fact(h, "(at a)")
      erlang_fact = :beam4pm_ferroplan.session_fact(h, "(at a)")
      assert erlang_fact == elixir_fact
      assert {:ok, %{"value" => false}} = erlang_fact
    end

    test "session_world_bytes / session_mind_bytes parity on a private handle, real positive sizes" do
      {:ok, %{"handle" => h}} = BeamPM.Ferroplan.session_new(@domain, @problem)

      assert :beam4pm_ferroplan.session_world_bytes(h) == BeamPM.Ferroplan.session_world_bytes(h)
      assert :beam4pm_ferroplan.session_mind_bytes(h) == BeamPM.Ferroplan.session_mind_bytes(h)
      assert {:ok, %{"bytes" => world}} = :beam4pm_ferroplan.session_world_bytes(h)
      assert world > 0
    end

    test "session_free/1 parity, and a freed handle errors identically on both sides" do
      {:ok, %{"handle" => h}} = BeamPM.Ferroplan.session_new(@domain, @problem)

      elixir_free = BeamPM.Ferroplan.session_free(h)
      erlang_h2 = h
      # Free once via the Elixir wrapper (state-mutating, so this half of
      # the parity check must be sequential, not double-freed).
      assert {:ok, %{"freed" => true}} = elixir_free

      # A second free (via the Erlang facade, on the now-freed handle)
      # must fail identically to a direct Elixir call on the same handle.
      elixir_double_free = BeamPM.Ferroplan.session_free(erlang_h2)
      erlang_double_free = :beam4pm_ferroplan.session_free(erlang_h2)
      assert erlang_double_free == elixir_double_free
      assert {:error, {:engine, msg}} = erlang_double_free
      assert msg =~ "unknown session handle"
    end
  end

  describe "gleam facade (:beam4pm@ferroplan, gleam/src/beam4pm/ferroplan.gleam)" do
    if not File.exists?(Path.expand("gleam/build/dev/erlang/beam4pm/ebin")) do
      @describetag skip: "gleam facade not built -- run (cd gleam && gleam build) first"
    end

    test "start/0 resolves to the same named engine process as the elixir wrapper", ctx do
      assert {:ok, pid} = gleam(:start, [])
      assert pid == ctx.engine_pid
    end

    test "plan/2 matches the elixir wrapper's real solve" do
      elixir_result = BeamPM.Ferroplan.plan(@domain, @problem)
      gleam_result = gleam(:plan, [@domain, @problem])
      assert gleam_result == elixir_result
      assert {:ok, sol} = gleam_result
      assert sol["solved"] == true
    end

    test "plan_production/2 matches the elixir wrapper's real envelope" do
      elixir_result = BeamPM.Ferroplan.plan_production(@domain, @problem)
      gleam_result = gleam(:plan_production, [@domain, @problem])
      assert gleam_result == elixir_result
    end

    test "readiness/0 and version/0 match the elixir wrapper" do
      assert gleam(:readiness, []) == BeamPM.Ferroplan.readiness()
      assert gleam(:version, []) == BeamPM.Ferroplan.version()
    end

    test "session_think/session_valid/session_has_plan parity on the shared handle", ctx do
      elixir_think = BeamPM.Ferroplan.session_think(ctx.session_h, 10_000, 64)
      gleam_think = gleam(:session_think, [ctx.session_h, 10_000, 64])
      assert gleam_think == elixir_think

      assert gleam(:session_valid, [ctx.session_h]) ==
               BeamPM.Ferroplan.session_valid?(ctx.session_h)

      assert gleam(:session_has_plan, [ctx.session_h]) ==
               BeamPM.Ferroplan.session_has_plan?(ctx.session_h)
    end

    test "session_set_fluent / session_fluent parity on a private handle" do
      {:ok, %{"handle" => h}} = BeamPM.Ferroplan.session_new(@domain, @problem)

      elixir_set = BeamPM.Ferroplan.session_set_fluent(h, "(score)", 1.5)
      gleam_set = gleam(:session_set_fluent, [h, "(score)", 1.5])
      assert gleam_set == elixir_set
      assert {:ok, %{"ok" => true}} = elixir_set

      elixir_get = BeamPM.Ferroplan.session_fluent(h, "(score)")
      gleam_get = gleam(:session_fluent, [h, "(score)"])
      assert gleam_get == elixir_get
      assert {:ok, %{"value" => 1.5}} = gleam_get
    end

    test "session_free/1 on a private handle parity, unknown-handle refusal parity" do
      {:ok, %{"handle" => h}} = BeamPM.Ferroplan.session_new(@domain, @problem)
      assert {:ok, %{"freed" => true}} = BeamPM.Ferroplan.session_free(h)

      elixir_result = BeamPM.Ferroplan.session_step(h)
      gleam_result = gleam(:session_step, [h])
      assert gleam_result == elixir_result
      assert {:error, {:engine, _msg}} = gleam_result
    end
  end
end
