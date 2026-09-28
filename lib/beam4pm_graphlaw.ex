# Hand-authored (not ggen-generated). Admitted via bap:hand_authored_lib_beam4pm_graphlaw -- see ontology.ttl
defmodule BeamPM.Graphlaw do
  @moduledoc ~S"""
  Wasmex host for the `graphlaw` WASI module (crates.io `graphlaw`, release
  asset `graphlaw.wasm`): the independent admission court for candidate plans
  and deviations. Exports `gl_alloc`, `gl_call` (consumes the request buffer,
  returns `(out_ptr <<< 32) ||| out_len`) and `gl_free`; requests and
  responses are UTF-8 JSON. Same host shape as `BeamPM.Ferroplan`, one named
  engine instance.

  Unlike the planning engine, an `{"ok": false}` response is always a typed
  refusal here: `{:error, {:refused, %{kind, engine, dialect, message}}}`.
  """

  import Bitwise

  @engine_name BeamPM.Graphlaw.Engine
  @pt_key {__MODULE__, :engine_handles}
  @wasm_rel "native/graphlaw/graphlaw_wasm.wasm"
  @timeout 30_000

  @type refusal :: %{String.t() => term()}
  @type result :: {:ok, map()} | {:error, {:refused, refusal()} | {:wasmex, term()}}

  @doc "Wasm artifact path: `GRAPHLAW_WASM` if set, else `#{@wasm_rel}` from the project root."
  @spec wasm_path() :: String.t()
  def wasm_path, do: System.get_env("GRAPHLAW_WASM") || Path.expand(@wasm_rel)

  @spec wasm_built?() :: boolean()
  def wasm_built?, do: File.exists?(wasm_path())

  @doc "Named reason used by tests' skip tag when the artifact is absent."
  @spec wasm_missing_reason() :: String.t()
  def wasm_missing_reason do
    "graphlaw wasm not found at #{wasm_path()} -- run scripts/graphlaw_wasm_fetch.sh " <>
      "(or set GRAPHLAW_WASM), and run mix test from the project root"
  end

  @doc "Starts (or reuses) the one named engine instance. Idempotent."
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

  @doc """
  Replays a candidate plan over `state` (a list of `{subject, predicate, object}`
  IRI triples). `actions` is a list of `%{name:, pre:, add:, del:}` (triple
  lists); `goal` is a triple list. Returns `{:ok, %{states, receipts, nquads}}`
  (one receipt per action) or `{:error, {:refused, refusal}}` at the first
  unmet precondition / goal.
  """
  @spec admit_plan([tuple()], [map()], [tuple()], keyword()) :: result()
  def admit_plan(state, actions, goal, opts \\ []) when is_list(state) and is_list(actions) do
    plan = %{
      "actions" =>
        Enum.map(actions, fn a ->
          %{
            "name" => to_string(Map.fetch!(a, :name)),
            "pre" => nt(Map.get(a, :pre, [])),
            "add" => nt(Map.get(a, :add, [])),
            "del" => nt(Map.get(a, :del, []))
          }
        end),
      "goal" => nt(goal)
    }

    law(state, [%{"step" => "plan", "plan" => plan}], opts)
  end

  @doc """
  SHACL admission gate: `{:ok, resp}` iff the `state` triples conform to the
  Turtle `shapes_ttl`; otherwise `{:error, {:refused, refusal}}`. Never
  changes the state.
  """
  @spec admit_shacl([tuple()] | String.t(), String.t(), keyword()) :: result()
  def admit_shacl(state, shapes_ttl, opts \\ []) when is_binary(shapes_ttl) do
    law(state, [%{"step" => "shacl", "shapes" => shapes_ttl}], opts)
  end

  @doc "Raw `law` op: `state` is triples or an N-Triples/Turtle string; `steps` per the graphlaw ABI."
  @spec law([tuple()] | String.t(), [map()], keyword()) :: result()
  def law(state, steps, opts \\ []) do
    {text, dialect} =
      if is_binary(state),
        do: {state, Keyword.get(opts, :dialect, "turtle")},
        else: {nt(state), "ntriples"}

    call(
      %{"op" => "law", "data" => %{"text" => text, "dialect" => dialect}, "steps" => steps},
      Keyword.get(opts, :timeout, @timeout)
    )
  end

  @doc "Renders IRI triples as N-Triples text."
  @spec nt([tuple()]) :: String.t()
  def nt(triples) do
    Enum.map_join(triples, fn {s, p, o} -> "<#{s}> <#{p}> <#{o}> .\n" end)
  end

  # -- wire ---------------------------------------------------------------

  defp call(req, timeout) when is_map(req) do
    data = JSON.encode!(req)
    len = byte_size(data)

    with {:ok, {pid, store, memory}} <- engine(),
         {:ok, [raw_ptr]} <- call_export(pid, "gl_alloc", [len], timeout),
         ptr = band(raw_ptr, 0xFFFF_FFFF),
         :ok <- if(ptr == 0, do: {:error, :guest_alloc_failed}, else: :ok),
         :ok <- write_request(pid, store, memory, ptr, len, data),
         {:ok, [packed]} <- call_export(pid, "gl_call", [ptr, len], timeout) do
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
        _ = call_export(pid, "gl_free", [ptr, len], @timeout)
        err
    end
  end

  # gl_call consumes (frees) the request buffer; only the response is freed here.
  defp read_response(pid, store, memory, packed, timeout) do
    packed = band(packed, 0xFFFF_FFFF_FFFF_FFFF)
    out_ptr = bsr(packed, 32)
    out_len = band(packed, 0xFFFF_FFFF)

    out = Wasmex.Memory.read_binary(store, memory, out_ptr, out_len)
    _ = call_export(pid, "gl_free", [out_ptr, out_len], timeout)

    case JSON.decode!(out) do
      %{"ok" => true} = decoded -> {:ok, Map.delete(decoded, "ok")}
      %{"ok" => false, "error" => err} -> {:error, {:refused, err}}
      other -> {:error, {:wasmex, {:unexpected_response, other}}}
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
      nil -> {:error, {:engine_not_started, "call BeamPM.Graphlaw.start/0 first"}}
      pid -> {:ok, handles!(pid)}
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
end
