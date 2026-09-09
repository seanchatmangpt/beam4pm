defmodule BeamPM.Petgraph do
  @moduledoc """
  BEAM-side wrapper over a real graph-algorithms engine (petgraph: Dijkstra
  via A*, Tarjan strongly-connected-components, topological sort, cycle
  detection) -- a third BEAM-hosted WASM engine alongside `BeamPM.Rust4PM`
  (process mining) and `BeamPM.Ferroplan` (PDDL planning), same wasmex
  hosting pattern, same linear-memory JSON ABI shape. Built to run real
  algorithms over the DFGs and Petri nets `BeamPM.Rust4PM.discover_dfg/2`
  and friends already produce, without reimplementing any graph algorithm
  on the BEAM side.

  ## Wire contract

  The wasm module (`native/petgraph-wasm/src/lib.rs`) exports
  `pg_alloc`/`pg_call`/`pg_dealloc`, the same shape as `r4pm_*`/`fp_*`. Wire
  sequence, memory-ownership rule, and crash-recovery semantics are
  IDENTICAL to `BeamPM.Rust4PM`'s (see that module's moduledoc).

  ## Ops

  `graph_new/1`, `add_node/3`, `add_edge/4` (weight optional, default
  1.0), `shortest_path/3` (real A*-as-Dijkstra; `nil` result, not an
  error, when unreachable; refuses negative edge weights honestly rather
  than mishandling them), `scc/2` (Tarjan, deterministically sorted),
  `toposort/2` (`{:ok, %{"acyclic" => bool, "order" => [...] | nil}}` --
  a cycle is a real answer, never an error), `is_cyclic?/2`,
  `node_count/2`, `edge_count/2`, `free_graph/2`.

  ## Process model and crash semantics

  ONE named Wasmex GenServer (`BeamPM.Petgraph.Engine`) -- a third,
  independent engine instance, never sharing a store with
  `BeamPM.Rust4PM.Engine` or `BeamPM.Ferroplan.Engine`. Restart-on-trap,
  handle invalidation on restart, WASI defaults, singleton store-queue
  serialization: all identical to the other two engines' contracts.
  """

  import Bitwise

  @engine_name BeamPM.Petgraph.Engine
  @pt_key {__MODULE__, :engine_handles}

  @wasm_rel "native/petgraph-wasm/target/wasm32-wasip1/release/petgraph_wasm.wasm"

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
    "petgraph_wasm.wasm not built at #{wasm_path()} -- run " <>
      "scripts/petgraph_wasm_build.sh first, and run mix test from the " <>
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

  @doc "`{\"op\":\"graph_new\"}` -- a new, empty directed graph. `{:ok, %{\"handle\" => n}}`."
  @spec graph_new(keyword()) :: result()
  def graph_new(opts \\ []) do
    call(%{"op" => "graph_new"}, timeout(opts, @cheap_timeout))
  end

  @doc "`{\"op\":\"add_node\",\"handle\":h,\"name\":n}` -- idempotent."
  @spec add_node(non_neg_integer(), String.t(), keyword()) :: result()
  def add_node(handle, name, opts \\ []) when is_integer(handle) and is_binary(name) do
    call(%{"op" => "add_node", "handle" => handle, "name" => name}, timeout(opts, @cheap_timeout))
  end

  @doc """
  `{"op":"add_edge","handle":h,"from":f,"to":t,"weight":w}` -- auto-adds
  `from`/`to` as nodes if absent. `weight` defaults to 1.0.
  """
  @spec add_edge(non_neg_integer(), String.t(), String.t(), keyword()) :: result()
  def add_edge(handle, from, to, opts \\ [])
      when is_integer(handle) and is_binary(from) and is_binary(to) do
    weight = Keyword.get(opts, :weight, 1.0)

    call(
      %{"op" => "add_edge", "handle" => handle, "from" => from, "to" => to, "weight" => weight},
      timeout(opts, @cheap_timeout)
    )
  end

  @doc """
  `{"op":"shortest_path","handle":h,"from":f,"to":t}` -- real A*-as-Dijkstra.
  `{:ok, %{"path" => [names], "cost" => f64}}` on a real path, or
  `{:ok, %{"path" => nil, "cost" => nil}}` when unreachable or a name is
  unknown -- "no path" is an answer, not an error. Negative edge weights
  are refused with a real `{:error, {:engine, _}}`, never silently
  mishandled.
  """
  @spec shortest_path(non_neg_integer(), String.t(), String.t(), keyword()) :: result()
  def shortest_path(handle, from, to, opts \\ [])
      when is_integer(handle) and is_binary(from) and is_binary(to) do
    call(
      %{"op" => "shortest_path", "handle" => handle, "from" => from, "to" => to},
      timeout(opts, @cheap_timeout)
    )
  end

  @doc """
  `{"op":"scc","handle":h}` -- Tarjan strongly-connected-components,
  deterministically sorted (each component's node list sorted, components
  sorted by their sorted list).
  """
  @spec scc(non_neg_integer(), keyword()) :: result()
  def scc(handle, opts \\ []) when is_integer(handle) do
    call(%{"op" => "scc", "handle" => handle}, timeout(opts, @cheap_timeout))
  end

  @doc """
  `{"op":"toposort","handle":h}` -- `{:ok, %{"acyclic" => true, "order" =>
  [names]}}` or `{:ok, %{"acyclic" => false, "order" => nil}}`. A cycle is
  a real, named answer, never an error.
  """
  @spec toposort(non_neg_integer(), keyword()) :: result()
  def toposort(handle, opts \\ []) when is_integer(handle) do
    call(%{"op" => "toposort", "handle" => handle}, timeout(opts, @cheap_timeout))
  end

  @doc "`{\"op\":\"is_cyclic\",\"handle\":h}` -- `{:ok, %{\"cyclic\" => bool}}`."
  @spec is_cyclic?(non_neg_integer(), keyword()) :: result()
  def is_cyclic?(handle, opts \\ []) when is_integer(handle) do
    call(%{"op" => "is_cyclic", "handle" => handle}, timeout(opts, @cheap_timeout))
  end

  @spec node_count(non_neg_integer(), keyword()) :: result()
  def node_count(handle, opts \\ []) when is_integer(handle) do
    call(%{"op" => "node_count", "handle" => handle}, timeout(opts, @cheap_timeout))
  end

  @spec edge_count(non_neg_integer(), keyword()) :: result()
  def edge_count(handle, opts \\ []) when is_integer(handle) do
    call(%{"op" => "edge_count", "handle" => handle}, timeout(opts, @cheap_timeout))
  end

  @spec free_graph(non_neg_integer(), keyword()) :: result()
  def free_graph(handle, opts \\ []) when is_integer(handle) do
    call(%{"op" => "free_graph", "handle" => handle}, timeout(opts, @cheap_timeout))
  end

  # ---------------------------------------------------------------------
  # Core private call -- identical wire sequence to BeamPM.Rust4PM/
  # BeamPM.Ferroplan, against pg_* exports
  # ---------------------------------------------------------------------

  defp call(req, timeout) when is_map(req) do
    data = JSON.encode!(req)
    len = byte_size(data)

    with {:ok, {pid, store, memory}} <- engine(),
         {:ok, [raw_ptr]} <- call_export(pid, "pg_alloc", [len], timeout),
         ptr = band(raw_ptr, 0xFFFF_FFFF),
         :ok <- if(ptr == 0, do: {:error, :guest_alloc_failed}, else: :ok),
         :ok <- write_request(pid, store, memory, ptr, len, data),
         {:ok, [packed]} <- call_export(pid, "pg_call", [ptr, len], timeout) do
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
        _ = call_export(pid, "pg_dealloc", [ptr, len], @cheap_timeout)
        err
    end
  end

  defp read_response(pid, store, memory, packed, timeout) do
    packed = band(packed, 0xFFFF_FFFF_FFFF_FFFF)
    out_ptr = bsr(packed, 32)
    out_len = band(packed, 0xFFFF_FFFF)

    out = Wasmex.Memory.read_binary(store, memory, out_ptr, out_len)
    _ = call_export(pid, "pg_dealloc", [out_ptr, out_len], timeout)

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
        {:error, {:engine_not_started, "call BeamPM.Petgraph.start/0 first"}}

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

defmodule BeamPM.Petgraph.Health do
  @moduledoc """
  A single-candidate engine-health status probe for the petgraph engine,
  the same shape as `BeamPM.Rust4PM.Health`/`BeamPM.Ferroplan.Health`.
  """

  @type standing :: :alive | :blocked
  @type status :: %{
          id: :petgraph_wasm,
          kind: :engine,
          standing: standing(),
          reason: String.t() | nil,
          evidence: %{wasm_path: String.t(), artifact_present: boolean(), engine_started: boolean() | nil}
        }

  @spec status() :: status()
  def status do
    artifact_present = BeamPM.Petgraph.wasm_built?()

    if artifact_present do
      case BeamPM.Petgraph.start() do
        {:ok, _pid} ->
          %{
            id: :petgraph_wasm,
            kind: :engine,
            standing: :alive,
            reason: nil,
            evidence: %{
              wasm_path: BeamPM.Petgraph.wasm_path(),
              artifact_present: true,
              engine_started: true
            }
          }

        {:error, reason} ->
          %{
            id: :petgraph_wasm,
            kind: :engine,
            standing: :blocked,
            reason: "artifact present but engine failed to start: #{inspect(reason)}",
            evidence: %{
              wasm_path: BeamPM.Petgraph.wasm_path(),
              artifact_present: true,
              engine_started: false
            }
          }
      end
    else
      %{
        id: :petgraph_wasm,
        kind: :engine,
        standing: :blocked,
        reason: BeamPM.Petgraph.wasm_missing_reason(),
        evidence: %{
          wasm_path: BeamPM.Petgraph.wasm_path(),
          artifact_present: false,
          engine_started: nil
        }
      }
    end
  end
end
