defmodule BeamPM.TractTest do
  @moduledoc """
  Chicago-style qualification of `BeamPM.Tract`: a real ONNX model
  (`qualification/fixtures/tract/linear_2x_plus_1.onnx` -- a genuine,
  checker-validated ONNX graph computing `y = 2x + 1` via a real MatMul +
  Add, generated with the reference `onnx` Python package, not
  hand-crafted bytes) is loaded and run through the actual wasm32-wasip1
  tract engine -- no mocks, real inference math.

  Absence semantics mirror the other three engines: a missing wasm
  artifact is a NAMED SKIP.
  """

  use ExUnit.Case, async: false

  alias BeamPM.Tract

  if not BeamPM.Tract.wasm_built?() do
    @moduletag skip: BeamPM.Tract.wasm_missing_reason()
  end

  @moduletag timeout: 60_000

  @linear_model Path.expand("qualification/fixtures/tract/linear_2x_plus_1.onnx")

  setup do
    {:ok, _pid} = Tract.start()

    unless File.exists?(@linear_model) do
      raise "real ONNX fixture not found at #{@linear_model} -- mix test must run from the project root"
    end

    :ok
  end

  describe "load_model" do
    test "loads a real ONNX model and reports its real input/output shapes" do
      assert {:ok, %{"handle" => handle, "inputs" => inputs, "outputs" => outputs}} =
               Tract.load_model_path(@linear_model)

      assert is_integer(handle)
      assert [%{"name" => _, "shape" => [1, 1]}] = inputs
      assert [%{"name" => _, "shape" => [1, 1]}] = outputs

      assert {:ok, %{"freed" => true}} = Tract.free_model(handle)
    end

    test "model_info matches load_model's own reported shapes" do
      {:ok, %{"handle" => handle, "inputs" => load_inputs, "outputs" => load_outputs}} =
        Tract.load_model_path(@linear_model)

      assert {:ok, %{"inputs" => info_inputs, "outputs" => info_outputs}} = Tract.model_info(handle)
      assert info_inputs == load_inputs
      assert info_outputs == load_outputs
    end
  end

  describe "run -- real inference" do
    test "y = 2x + 1 on real single-value inputs, computed by the actual model" do
      {:ok, %{"handle" => handle}} = Tract.load_model_path(@linear_model)

      for {x, expected_y} <- [{0.0, 1.0}, {1.0, 3.0}, {2.5, 6.0}, {-3.0, -5.0}] do
        assert {:ok, %{"outputs" => [%{"shape" => [1, 1], "data" => [y]}]}} =
                 Tract.run(handle, [%{shape: [1, 1], data: [x]}])

        assert_in_delta y, expected_y, 1.0e-5, "tract computed y=#{y} for x=#{x}, expected #{expected_y}"
      end
    end

    test "a shape/data length mismatch is refused, not silently truncated or padded" do
      {:ok, %{"handle" => handle}} = Tract.load_model_path(@linear_model)

      assert {:error, {:engine, msg}} =
               Tract.run(handle, [%{shape: [1, 1], data: [1.0, 2.0, 3.0]}])

      assert msg =~ "implies" or msg =~ "shape"
    end
  end

  describe "handle discipline" do
    test "an unknown model handle is a named engine error, not a crash" do
      assert {:error, {:engine, msg}} = Tract.model_info(999_999)
      assert msg =~ "unknown model handle"
    end

    test "a freed handle cannot be reused for inference" do
      {:ok, %{"handle" => handle}} = Tract.load_model_path(@linear_model)
      assert {:ok, %{"freed" => true}} = Tract.free_model(handle)
      assert {:error, {:engine, msg}} = Tract.run(handle, [%{shape: [1, 1], data: [1.0]}])
      assert msg =~ "unknown model handle"
    end
  end

  describe "malformed model input" do
    test "garbage bytes are refused with a real parse error, not a crash" do
      assert {:error, {:engine, msg}} = Tract.load_model(:crypto.strong_rand_bytes(64))
      assert msg =~ "ONNX parse failed" or msg =~ "parse"
    end
  end
end
