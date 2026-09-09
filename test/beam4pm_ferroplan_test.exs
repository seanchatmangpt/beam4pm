defmodule BeamPM.FerroplanTest do
  @moduledoc """
  Chicago-style qualification of `BeamPM.Ferroplan`: the ferroplan PDDL
  planning engine, built from the `native/ferroplan` git submodule to
  wasm32-wasip1 and hosted in BEAM via wasmex, exercised for real against a
  real classical-planning domain -- no mocks. Same shape as
  `BeamPM.Rust4PMTest`: real wasm collaborator, state-based assertions on
  the actual decoded response.

  Absence semantics mirror `BeamPM.Rust4PM`'s: a missing wasm artifact is a
  NAMED SKIP (`wasm_missing_reason/0`), not a silent pass and not a raise.
  """

  use ExUnit.Case, async: false

  alias BeamPM.Ferroplan

  if not BeamPM.Ferroplan.wasm_built?() do
    @moduletag skip: BeamPM.Ferroplan.wasm_missing_reason()
  end

  @moduletag timeout: 60_000

  # The classic rocket/logistics-shaped toy domain used throughout
  # ferroplan's own test suite (crates/ferroplan/tests) -- move a package
  # from room a to room b via a two-step corridor plan.
  @domain """
  (define (domain rooms)
    (:requirements :strips :typing)
    (:types room)
    (:predicates (at ?r - room) (link ?a - room ?b - room))
    (:action go
      :parameters (?a - room ?b - room)
      :precondition (and (at ?a) (link ?a ?b))
      :effect (and (at ?b) (not (at ?a)))))
  """

  @problem """
  (define (problem two-room)
    (:domain rooms)
    (:objects a b - room)
    (:init (at a) (link a b))
    (:goal (at b)))
  """

  setup do
    {:ok, _pid} = Ferroplan.start()
    :ok
  end

  describe "stateless solves" do
    test "plan/4 solves the two-room domain in one step" do
      assert {:ok, sol} = Ferroplan.plan(@domain, @problem)
      assert sol["solved"] == true
      assert sol["plan"]["length"] == 1
    end

    test "plan_production/4 returns a versioned candidate-only envelope" do
      assert {:ok, envelope} = Ferroplan.plan_production(@domain, @problem)
      assert envelope["schema_version"] == "ferroplan.operation.v1"
      assert envelope["authority"] == "candidate_only"
      assert envelope["outcome"] == "solved"
    end

    test "plan_production/4 refuses an unknown mode with a structured error" do
      assert {:ok, envelope} =
               Ferroplan.plan_production(@domain, @problem, %{"mode" => "not-a-real-mode"})

      assert envelope["outcome"] == "refused"
      assert envelope["error"]["code"] == "FP_INVALID_REQUEST"
    end

    test "readiness/1 returns a fingerprinted capability manifest" do
      assert {:ok, manifest} = Ferroplan.readiness()
      assert manifest["schema_version"] == "ferroplan.readiness-contract.v1"
      assert manifest["contract_valid"] == true
      assert is_binary(manifest["manifest_fingerprint"])
    end

    test "version/1 reports the crate's own version" do
      assert {:ok, %{"version" => version}} = Ferroplan.version()
      assert is_binary(version)
      assert version =~ ~r/^\d+\.\d+\.\d+$/
    end

    test "explain/4 explains a real solved plan" do
      {:ok, sol} = Ferroplan.plan(@domain, @problem)
      assert {:ok, explanation} = Ferroplan.explain(@domain, @problem, sol["plan"])
      assert is_map(explanation)
    end
  end

  describe "session lifecycle" do
    test "session_new -> session_think -> session_step/suffix/advance walks a real plan" do
      assert {:ok, %{"handle" => handle}} = Ferroplan.session_new(@domain, @problem)
      assert {:ok, sol} = Ferroplan.session_think(handle, 10_000, 64)
      assert sol["solved"] == true

      assert {:ok, %{"has_plan" => true}} = Ferroplan.session_has_plan?(handle)
      assert {:ok, %{"valid" => true}} = Ferroplan.session_valid?(handle)

      assert {:ok, step} = Ferroplan.session_step(handle)
      refute is_nil(step)

      assert {:ok, %{"ok" => true}} = Ferroplan.session_advance(handle)
      assert {:ok, suffix} = Ferroplan.session_suffix(handle)
      assert is_list(suffix)

      assert {:ok, %{"freed" => true}} = Ferroplan.session_free(handle)
    end

    test "session_fork shares the world but keeps independent plan state" do
      {:ok, %{"handle" => parent}} = Ferroplan.session_new(@domain, @problem)
      {:ok, _sol} = Ferroplan.session_think(parent, 10_000, 64)
      assert {:ok, %{"handle" => child}} = Ferroplan.session_fork(parent)
      refute child == parent

      # The fork starts with no stashed plan of its own.
      assert {:ok, %{"has_plan" => false}} = Ferroplan.session_has_plan?(child)
      assert {:ok, %{"has_plan" => true}} = Ferroplan.session_has_plan?(parent)
    end

    test "session_set_fact / session_fact round-trip a real world mutation" do
      {:ok, %{"handle" => handle}} = Ferroplan.session_new(@domain, @problem)
      assert {:ok, %{"ok" => true}} = Ferroplan.session_set_fact(handle, "(at a)", false)
      assert {:ok, %{"value" => value}} = Ferroplan.session_fact(handle, "(at a)")
      assert value == false
    end

    test "session_world_bytes and session_mind_bytes report real positive sizes" do
      {:ok, %{"handle" => handle}} = Ferroplan.session_new(@domain, @problem)
      assert {:ok, %{"bytes" => world}} = Ferroplan.session_world_bytes(handle)
      assert {:ok, %{"bytes" => mind}} = Ferroplan.session_mind_bytes(handle)
      assert world > 0
      assert mind >= 0
    end
  end

  describe "handle discipline" do
    test "an unknown session handle is a named engine error, not a crash" do
      # Case 1: a handle number that was never allocated.
      assert {:error, {:engine, msg}} = Ferroplan.session_step(999_999)
      assert msg =~ "unknown session handle"

      # Case 2: a handle that WAS allocated, then freed -- proves the
      # registry actually removes freed handles rather than leaking them,
      # hitting the same "unknown session handle" error shape via a
      # different call path (session_free instead of session_step).
      {:ok, %{"handle" => handle}} = Ferroplan.session_new(@domain, @problem)
      assert {:ok, %{"freed" => true}} = Ferroplan.session_free(handle)
      assert {:error, {:engine, msg2}} = Ferroplan.session_free(handle)
      assert msg2 =~ "unknown session handle"
    end
  end
end
