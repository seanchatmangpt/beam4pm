defmodule BeamPM.Tract do
  @moduledoc """
  BEAM-side wrapper over a real ONNX-inference engine (sonos/tract -- the
  same crate Wasmtime's own WASI-NN implementation uses for this exact
  target) -- a fourth BEAM-hosted WASM engine alongside `BeamPM.Rust4PM`
  (process mining), `BeamPM.Ferroplan` (PDDL planning), and
  `BeamPM.Petgraph` (graph algorithms), same wasmex hosting pattern, same
  linear-memory JSON ABI shape. All inference math (graph optimization,
  the compiled runnable plan, the actual tensor ops) happens INSIDE the
  wasm module (`native/tract-wasm/src/lib.rs`); this module only frames
  base64 ONNX bytes and JSON tensor descriptors. No inference is
  reimplemented on the BEAM side.

  This is the natural third leg of the pipeline the other two engines
  build toward: `BeamPM.Rust4PM` discovers the real process, `BeamPM.Tract`
  predicts an outcome from a trained model, `BeamPM.Ferroplan` plans the
  remediation -- discover, predict, plan, all inside BEAM.

  ## Wire contract

  The wasm module exports `tr_alloc`/`tr_call`/`tr_dealloc`, the same
  shape as the other three engines' `r4pm_*`/`fp_*`/`pg_*`. Wire sequence,
  memory-ownership rule, and crash-recovery semantics are IDENTICAL to
  `BeamPM.Rust4PM`'s (see that module's moduledoc).

  ## Ops

  `load_model/2` (base64-encodes the ONNX bytes host-side -- JSON strings
  cannot carry raw protobuf), `run/3` (one f32 tensor per declared model
  input, in order; only f32 is supported -- a non-f32 model input/output
  is refused explicitly, never silently coerced), `model_info/2`,
  `free_model/2`.

  A model is compiled to a runnable plan at `load_model/2` time, not
  lazily on first `run/3` -- a malformed or unsupported-op ONNX file fails
  loudly at load, never on first inference.

  ## Process model and crash semantics

  ONE named Wasmex GenServer (`BeamPM.Tract.Engine`) -- a fourth,
  independent engine instance, never sharing a store with the other three
  engines. Restart-on-trap, handle invalidation on restart, WASI defaults,
  singleton store-queue serialization: identical to the other engines'
  contracts. `run/3`'s per-op timeout defaults heavier than the other
  engines' cheap ops -- real tensor inference, even on a tiny model, is
  not a cheap handle-local query.
  """

  import Bitwise

  @engine_name BeamPM.Tract.Engine
  @pt_key {__MODULE__, :engine_handles}

  @wasm_rel "native/tract-wasm/target/wasm32-wasip1/release/tract_wasm.wasm"

  @heavy_timeout 60_000
  @cheap_timeout 30_000

  @type resp :: map()
  @type err :: {:engine, String.t()} | {:wasmex, term()}
  @type result :: {:ok, resp()} | {:error, err()}

  # ---------------------------------------------------------------------
  # Engine lifecycle
  # ---------------------------------------------------------------------

  @spec wasm_path() :: String.t()
  def wasm_path, do: Path.expand(@wasm_rel)

  @spec wasm_built?() :: boolean()
  def wasm_built?, do: File.exists?(wasm_path())

  @spec wasm_missing_reason() :: String.t()
  def wasm_missing_reason do
    "tract_wasm.wasm not built at #{wasm_path()} -- run " <>
      "scripts/tract_wasm_build.sh first, and run mix test from the " <>
      "project root"
  end

  @spec start() :: {:ok, pid()} | {:error, term()}
  def start do
    case start_link_raw() do
      {:ok, pid} ->
        _ = handles!(pid)
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:ok, pid}

      other ->
        other
    end
  end

  @spec start_link_raw() :: {:ok, pid()} | {:error, term()}
  def start_link_raw do
    Wasmex.start_link(%{
      bytes: File.read!(wasm_path()),
      wasi: %Wasmex.Wasi.WasiOptions{},
      name: @engine_name
    })
  end

  @spec child_spec(term()) :: Supervisor.child_spec()
  def child_spec(_opts) do
    %{
      id: @engine_name,
      start: {__MODULE__, :start_link_raw, []},
      restart: :permanent,
      type: :worker
    }
  end

  # ---------------------------------------------------------------------
  # Ops
  # ---------------------------------------------------------------------

  @doc """
  `{"op":"load_model","model_b64":...}` -- `model_bytes` is the raw ONNX
  protobuf (base64-encoded host-side). Optimizes and compiles to a
  runnable plan immediately. `{:ok, %{"handle" => n, "inputs" =>
  [%{"name" => s, "shape" => [dims|nil]}], "outputs" => [...]}}` -- a
  `nil` dim is a symbolic/dynamic axis tract could not fully resolve at
  load time, reported honestly rather than guessed.
  """
  @spec load_model(binary(), keyword()) :: result()
  def load_model(model_bytes, opts \\ []) when is_binary(model_bytes) do
    call(
      %{"op" => "load_model", "model_b64" => Base.encode64(model_bytes)},
      timeout(opts, @heavy_timeout)
    )
  end

  @doc "`File.read!/1` host-side, then `load_model/2` (raises if the path is absent)."
  @spec load_model_path(Path.t(), keyword()) :: result()
  def load_model_path(path, opts \\ []) do
    load_model(File.read!(path), opts)
  end

  @doc """
  `{"op":"run","handle":h,"inputs":[{"shape":[dims],"data":[f32,...]}]}`
  -- one f32 tensor per declared model input, in order (`inputs` a list
  of `%{shape: [dims], data: [floats]}`, converted to the wire's
  string-keyed shape here). `{:ok, %{"outputs" => [%{"shape" => [dims],
  "data" => [floats]}]}}`, one per declared model output, in order.
  """
  @spec run(non_neg_integer(), [%{shape: [non_neg_integer()], data: [number()]}], keyword()) ::
          result()
  def run(handle, inputs, opts \\ []) when is_integer(handle) and is_list(inputs) do
    wire_inputs =
      Enum.map(inputs, fn %{shape: shape, data: data} ->
        %{"shape" => shape, "data" => data}
      end)

    call(
      %{"op" => "run", "handle" => handle, "inputs" => wire_inputs},
      timeout(opts, @heavy_timeout)
    )
  end

  @doc "`{\"op\":\"model_info\",\"handle\":h}` -- same input/output fact shape as `load_model/2`."
  @spec model_info(non_neg_integer(), keyword()) :: result()
  def model_info(handle, opts \\ []) when is_integer(handle) do
    call(%{"op" => "model_info", "handle" => handle}, timeout(opts, @cheap_timeout))
  end

  @spec free_model(non_neg_integer(), keyword()) :: result()
  def free_model(handle, opts \\ []) when is_integer(handle) do
    call(%{"op" => "free_model", "handle" => handle}, timeout(opts, @cheap_timeout))
  end

  # ---------------------------------------------------------------------
  # Core private call -- identical wire sequence to the other three
  # engines, against tr_* exports
  # ---------------------------------------------------------------------

  defp call(req, timeout) when is_map(req) do
    data = JSON.encode!(req)
    len = byte_size(data)

    with {:ok, {pid, store, memory}} <- engine(),
         {:ok, [raw_ptr]} <- call_export(pid, "tr_alloc", [len], timeout),
         ptr = band(raw_ptr, 0xFFFF_FFFF),
         :ok <- if(ptr == 0, do: {:error, :guest_alloc_failed}, else: :ok),
         :ok <- write_request(pid, store, memory, ptr, len, data),
         {:ok, [packed]} <- call_export(pid, "tr_call", [ptr, len], timeout) do
      read_response(pid, store, memory, packed, timeout)
    else
      {:error, {:call_exit, _} = reason} ->
        restart_engine()
        {:error, {:wasmex, {:engine_restarted, reason}}}

      {:error, reason} ->
        {:error, {:wasmex, reason}}
    end
  end

  defp call_export(pid, export, args, timeout) do
    Wasmex.call_function(pid, export, args, timeout)
  catch
    :exit, reason -> {:error, {:call_exit, reason}}
  end

  defp write_request(pid, store, memory, ptr, len, data) do
    case Wasmex.Memory.write_binary(store, memory, ptr, data) do
      :ok ->
        :ok

      {:error, _} = err ->
        _ = call_export(pid, "tr_dealloc", [ptr, len], @cheap_timeout)
        err
    end
  end

  defp read_response(pid, store, memory, packed, timeout) do
    packed = band(packed, 0xFFFF_FFFF_FFFF_FFFF)
    out_ptr = bsr(packed, 32)
    out_len = band(packed, 0xFFFF_FFFF)

    out = Wasmex.Memory.read_binary(store, memory, out_ptr, out_len)
    _ = call_export(pid, "tr_dealloc", [out_ptr, out_len], timeout)

    case JSON.decode!(out) do
      %{"error" => err} = decoded when map_size(decoded) == 1 ->
        {:error, {:engine, inspect(err)}}

      decoded ->
        {:ok, decoded}
    end
  end

  defp restart_engine do
    case Process.whereis(@engine_name) do
      nil -> :ok
      pid -> GenServer.stop(pid, :kill)
    end
  catch
    :exit, _ -> :ok
  end

  defp engine do
    case Process.whereis(@engine_name) do
      nil ->
        {:error, {:engine_not_started, "call BeamPM.Tract.start/0 first"}}

      pid ->
        {:ok, handles!(pid)}
    end
  end

  defp handles!(pid) do
    case :persistent_term.get(@pt_key, nil) do
      {^pid, _store, _memory} = cached ->
        cached

      _stale_or_missing ->
        {:ok, store} = Wasmex.store(pid)
        {:ok, memory} = Wasmex.memory(pid)
        entry = {pid, store, memory}
        :persistent_term.put(@pt_key, entry)
        entry
    end
  end

  defp timeout(opts, default), do: Keyword.get(opts, :timeout, default)
end

defmodule BeamPM.Tract.Health do
  @moduledoc """
  A single-candidate engine-health status probe for the tract inference
  engine, the same shape as the other three engines' `.Health` modules.
  """

  @type standing :: :alive | :blocked
  @type status :: %{
          id: :tract_wasm,
          kind: :engine,
          standing: standing(),
          reason: String.t() | nil,
          evidence: %{wasm_path: String.t(), artifact_present: boolean(), engine_started: boolean() | nil}
        }

  @spec status() :: status()
  def status do
    artifact_present = BeamPM.Tract.wasm_built?()

    if artifact_present do
      case BeamPM.Tract.start() do
        {:ok, _pid} ->
          %{
            id: :tract_wasm,
            kind: :engine,
            standing: :alive,
            reason: nil,
            evidence: %{
              wasm_path: BeamPM.Tract.wasm_path(),
              artifact_present: true,
              engine_started: true
            }
          }

        {:error, reason} ->
          %{
            id: :tract_wasm,
            kind: :engine,
            standing: :blocked,
            reason: "artifact present but engine failed to start: #{inspect(reason)}",
            evidence: %{
              wasm_path: BeamPM.Tract.wasm_path(),
              artifact_present: true,
              engine_started: false
            }
          }
      end
    else
      %{
        id: :tract_wasm,
        kind: :engine,
        standing: :blocked,
        reason: BeamPM.Tract.wasm_missing_reason(),
        evidence: %{
          wasm_path: BeamPM.Tract.wasm_path(),
          artifact_present: false,
          engine_started: nil
        }
      }
    end
  end
end
