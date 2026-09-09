defmodule BeamPM.TractFacadesTest do
  @moduledoc """
  Facade-parity qualification for the two thin BEAM facades over the ONE
  tract wasm engine (`src/beam4pm_tract.erl`,
  `gleam/src/beam4pm/tract.gleam`), same shape as
  `BeamPM.FerroplanFacadesTest`/`BeamPM.PetgraphFacadesTest`: every op
  called through Elixir, Erlang, and Gleam against the SAME real ONNX
  fixture (`qualification/fixtures/tract/linear_2x_plus_1.onnx`),
  asserting exact `==` parity plus real inference-content checks. Named
  skip when the wasm artifact or the gleam build output is absent.
  """

  use ExUnit.Case, async: false

  if not BeamPM.Tract.wasm_built?() do
    @moduletag skip: BeamPM.Tract.wasm_missing_reason()
  end

  @moduletag timeout: 60_000

  @linear_model Path.expand("qualification/fixtures/tract/linear_2x_plus_1.onnx")
  @gleam_ebin Path.expand("gleam/build/dev/erlang/beam4pm/ebin")
  @gleam_mod :beam4pm@tract
  defp gleam(fun, args), do: apply(@gleam_mod, fun, args)

  setup_all do
    {:ok, engine_pid} = BeamPM.Tract.start()

    if File.exists?(@gleam_ebin) do
      true = Code.append_path(@gleam_ebin)
    end

    unless File.exists?(@linear_model) do
      raise "real ONNX fixture not found at #{@linear_model} -- mix test must run from the project root"
    end

    %{engine_pid: engine_pid, model_bytes: File.read!(@linear_model)}
  end

  describe "erlang facade (:beam4pm_tract, src/beam4pm_tract.erl)" do
    test "start/0 resolves to the same named engine process as the elixir wrapper", ctx do
      assert {:ok, pid} = :beam4pm_tract.start()
      assert pid == ctx.engine_pid
    end

    test "load_model/1 matches the elixir wrapper's real reported shapes", ctx do
      elixir_result = BeamPM.Tract.load_model(ctx.model_bytes)
      erlang_result = :beam4pm_tract.load_model(ctx.model_bytes)

      assert {:ok, %{"inputs" => e_in, "outputs" => e_out}} = elixir_result
      assert {:ok, %{"inputs" => r_in, "outputs" => r_out}} = erlang_result
      assert e_in == r_in
      assert e_out == r_out
      assert [%{"shape" => [1, 1]}] = r_in
    end

    test "run/2 computes real inference identically on both sides", ctx do
      {:ok, %{"handle" => handle}} = BeamPM.Tract.load_model(ctx.model_bytes)

      elixir_result = BeamPM.Tract.run(handle, [%{shape: [1, 1], data: [2.5]}])
      erlang_result = :beam4pm_tract.run(handle, [%{shape: [1, 1], data: [2.5]}])
      assert erlang_result == elixir_result

      assert {:ok, %{"outputs" => [%{"data" => [y]}]}} = erlang_result
      assert_in_delta y, 6.0, 1.0e-5
    end

    test "model_info/1 and free_model/1 parity", ctx do
      {:ok, %{"handle" => handle}} = BeamPM.Tract.load_model(ctx.model_bytes)

      assert :beam4pm_tract.model_info(handle) == BeamPM.Tract.model_info(handle)

      elixir_free = BeamPM.Tract.free_model(handle)
      assert {:ok, %{"freed" => true}} = elixir_free

      erlang_double_free = :beam4pm_tract.free_model(handle)
      elixir_double_free = BeamPM.Tract.free_model(handle)
      assert erlang_double_free == elixir_double_free
      assert {:error, {:engine, msg}} = erlang_double_free
      assert msg =~ "unknown model handle"
    end
  end

  describe "gleam facade (:beam4pm@tract, gleam/src/beam4pm/tract.gleam)" do
    if not File.exists?(Path.expand("gleam/build/dev/erlang/beam4pm/ebin")) do
      @describetag skip: "gleam facade not built -- run (cd gleam && gleam build) first"
    end

    test "start/0 resolves to the same named engine process as the elixir wrapper", ctx do
      assert {:ok, pid} = gleam(:start, [])
      assert pid == ctx.engine_pid
    end

    test "load_model matches the elixir wrapper's real reported shapes", ctx do
      # Each load_model call mints its own model handle -- compare the
      # reported input/output shapes (the real content under test), not
      # the handle integer, which legitimately differs between two
      # independent loads of the same model.
      {:ok, elixir_result} = BeamPM.Tract.load_model(ctx.model_bytes)
      {:ok, gleam_result} = gleam(:load_model, [ctx.model_bytes])
      assert gleam_result["inputs"] == elixir_result["inputs"]
      assert gleam_result["outputs"] == elixir_result["outputs"]
    end

    test "run computes real inference identically on both sides across several inputs", ctx do
      {:ok, %{"handle" => handle}} = BeamPM.Tract.load_model(ctx.model_bytes)

      for x <- [0.0, 1.0, -3.0] do
        # Gleam's `run/2` takes `inputs: Dynamic` (erased at runtime — see
        # tract.gleam's moduledoc), so this test passes the identical
        # atom-keyed map shape `BeamPM.Tract.run/3` itself pattern-matches
        # on (`%{shape: _, data: _}`), same as the Erlang facade test.
        elixir_result = BeamPM.Tract.run(handle, [%{shape: [1, 1], data: [x]}])
        gleam_result = gleam(:run, [handle, [%{shape: [1, 1], data: [x]}]])
        assert gleam_result == elixir_result
      end
    end

    test "free_model on a private handle, unknown-handle refusal parity", ctx do
      {:ok, %{"handle" => handle}} = BeamPM.Tract.load_model(ctx.model_bytes)
      assert {:ok, %{"freed" => true}} = BeamPM.Tract.free_model(handle)

      elixir_result = BeamPM.Tract.model_info(handle)
      gleam_result = gleam(:model_info, [handle])
      assert gleam_result == elixir_result
      assert {:error, {:engine, _msg}} = gleam_result
    end
  end
end
