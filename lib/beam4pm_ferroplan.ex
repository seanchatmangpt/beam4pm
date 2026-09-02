defmodule BeamPM.Ferroplan do
  @moduledoc """
  BEAM-side wrapper over the ferroplan PDDL planning engine
  (`seanchatmangpt/ferroplan`), a second, independent BEAM-hosted WASM
  engine alongside `BeamPM.Rust4PM`'s process-mining engine -- same wasmex
  hosting pattern, same linear-memory JSON ABI shape, different upstream
  and different domain. All planning computation (grounding, search,
  temporal/PDDL3 solving, session-based replanning) happens INSIDE the
  wasm module built from `native/ferroplan` (a git submodule pinned at a
  `seanchatmangpt/ferroplan` commit); this module only frames JSON
  requests and unpacks JSON responses. No planning algorithm is
  reimplemented on the BEAM side -- a real wasm collaborator, Chicago
  discipline, same as `BeamPM.Rust4PM`.

  ## Wire contract (linear-memory JSON ABI)

  The wasm module (`crates/ferroplan-wasm/src/wasi_abi.rs` upstream)
  exports three functions, the same shape as rust4pm-wasm's
  `r4pm_alloc`/`r4pm_call`/`r4pm_dealloc` (named `fp_*` here):

    * `fp_alloc(len) -> ptr` -- allocate a guest buffer for the request.
    * `fp_call(ptr, len) -> packed_u64` -- dispatch one JSON request; the
      return packs the response buffer as `(out_ptr << 32) | out_len`.
    * `fp_dealloc(ptr, len)` -- free the RESPONSE buffer after reading.

  Per-call sequence, memory-ownership rule, and crash-recovery semantics
  are IDENTICAL to `BeamPM.Rust4PM`'s (see that module's moduledoc for the
  full 8-step wire sequence and the Q1-F1..F5 guard rationale) -- only the
  export names and the op catalog differ. This module's private `call/2`
  is a straight copy of that sequence against `fp_*` instead of `r4pm_*`.

  ## Ops

  One public function per engine op (see each function's doc for its
  exact request shape):

  `plan/4`, `plan_production/3`, `readiness/1`, `version/1`, `explain/4`
  (stateless solves), and the session-lifecycle set --
  `session_new/3`, `session_fork/2`, `session_free/2`, `session_set_goal/3`,
  `session_restrict_prefix_claims/4`, `session_restrict_contains/3`,
  `session_think/4`, `session_valid?/2`, `session_step/2`, `session_suffix/2`,
  `session_advance/2`, `session_drop_plan/2`, `session_has_plan?/2`,
  `session_set_fact/4`, `session_set_timed_fact/5`, `session_observe/3`,
  `session_goal_met?/2`, `session_fact/3`, `session_apply_start/3`,
  `session_elapse/3`, `session_set_fluent/4`, `session_fluent/3`,
  `session_plan_valid?/4`, `session_world_bytes/2`, `session_mind_bytes/2`
  -- mirroring the native `ferroplan::Session` surface (`WasmSession` in
  the browser adapter) one-for-one, reachable here through an integer
  handle scoped to this engine process's wasm linear memory, exactly like
  `BeamPM.Rust4PM`'s log/net handles.

  ## Process model and crash semantics

  ONE named Wasmex GenServer (`BeamPM.Ferroplan.Engine`) serves all
  callers -- a second, independent engine instance from
  `BeamPM.Rust4PM.Engine`; the two wasm modules never share a store.
  Restart-on-trap, handle invalidation on restart, WASI defaults, and the
  singleton store-queue serialization are all identical to
  `BeamPM.Rust4PM`'s contract.

  Degradation when the wasm artifact is absent is a NAMED reason (see
  `wasm_built?/0` / `wasm_missing_reason/0`), not a fake -- the same
  documented pattern as `BeamPM.Rust4PM`.
  """

  import Bitwise

  @engine_name BeamPM.Ferroplan.Engine
  @pt_key {__MODULE__, :engine_handles}

  @wasm_rel "native/ferroplan/target/wasm32-wasip1/release/ferroplan_wasm.wasm"

  # Heavy ops: plan/plan_production/explain (a real search), session_think
  # (bounded, but by evals/memory, not wall clock -- give it room). Cheap
  # ops: handle-local state queries, fact/fluent mutation, cursor walking.
  @heavy_timeout 120_000
  @cheap_timeout 30_000

  @typedoc "Decoded string-keyed JSON response from the engine."
  @type resp :: map()

  @typedoc """
  `{:engine, msg}` = the wasm engine returned `{"error": {...}}` (an
  unknown op, an unknown session handle, a refused production request);
  `{:wasmex, term}` = a host-level failure (engine not started, wasmex
  call/alloc/write failure, or a call timeout/exit).
  """
  @type err :: {:engine, String.t()} | {:wasmex, term()}

  @type result :: {:ok, resp()} | {:error, err()}

  # ---------------------------------------------------------------------
  # Engine lifecycle
  # ---------------------------------------------------------------------

  @doc "Repo-root-relative wasm artifact path, expanded (rust4pm-wasm's wasm_path/0 idiom)."
  @spec wasm_path() :: String.t()
  def wasm_path, do: Path.expand(@wasm_rel)

  @doc "Whether the wasm engine artifact has been built."
  @spec wasm_built?() :: boolean()
  def wasm_built?, do: File.exists?(wasm_path())

  @doc "Named reason used by the tests' skip tag when the wasm artifact is absent."
  @spec wasm_missing_reason() :: String.t()
  def wasm_missing_reason do
    "ferroplan_wasm.wasm not built at #{wasm_path()} -- run " <>
      "scripts/ferroplan_wasm_build.sh first (after `git submodule update " <>
      "--init --recursive` if native/ferroplan is empty), and run mix test " <>
      "from the project root"
  end

  @doc """
  Starts (or reuses) the one named engine instance. Idempotent:
  `{:error, {:already_started, pid}}` is normalized to `{:ok, pid}`.

  Restarting after a crash yields a fresh store -- every session handle
  previously returned by `session_new/3` is invalid afterwards.
  """
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

  @doc """
  Raw `Wasmex.start_link/1` under the engine name -- the `child_spec/1`
  start function for use in a supervision tree. Prefer `start/0` for
  direct/test use.
  """
  @spec start_link_raw() :: {:ok, pid()} | {:error, term()}
  def start_link_raw do
    Wasmex.start_link(%{
      bytes: File.read!(wasm_path()),
      wasi: %Wasmex.Wasi.WasiOptions{},
      name: @engine_name
    })
  end

  @doc "Supervision-tree shim (not auto-installed; beam4pm has no Application module)."
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
  # Ops -- stateless solves
  # ---------------------------------------------------------------------

  @doc """
  `{"op":"plan","domain":d,"problem":p[,"mode":m,"flags":f,"search":s]}` --
  the compatibility solve surface (lenient mode/search parsing, single
  threaded). Returns `{:ok, <Solution map>}`.
  """
  @spec plan(String.t(), String.t(), map(), keyword()) :: result()
  def plan(domain, problem, extra \\ %{}, opts \\ [])
      when is_binary(domain) and is_binary(problem) and is_map(extra) do
    %{"op" => "plan", "domain" => domain, "problem" => problem}
    |> Map.merge(extra)
    |> call(timeout(opts, @heavy_timeout))
  end

  @doc """
  `{"op":"plan_production","domain":d,"problem":p[,"mode":m,"search":s,
  "max_evaluated":n,"max_plan_steps":n,"max_output_bytes":n,
  "request_id":id]}` -- bounded production solve: strict mode/search
  parsing, a versioned `OperationEnvelope` response, always candidate-only.
  """
  @spec plan_production(String.t(), String.t(), map(), keyword()) :: result()
  def plan_production(domain, problem, extra \\ %{}, opts \\ [])
      when is_binary(domain) and is_binary(problem) and is_map(extra) do
    %{"op" => "plan_production", "domain" => domain, "problem" => problem}
    |> Map.merge(extra)
    |> call(timeout(opts, @heavy_timeout))
  end

  @doc "`{\"op\":\"readiness\"}` -- capability manifest + deterministic fingerprint."
  @spec readiness(keyword()) :: result()
  def readiness(opts \\ []) do
    call(%{"op" => "readiness"}, timeout(opts, @cheap_timeout))
  end

  @doc "`{\"op\":\"version\"}` -- `{:ok, %{\"version\" => \"0.26.0\"}}`."
  @spec version(keyword()) :: result()
  def version(opts \\ []) do
    call(%{"op" => "version"}, timeout(opts, @cheap_timeout))
  end

  @doc """
  `{"op":"explain","domain":d,"problem":p,"plan":plan}` -- `plan` is a
  decoded Plan map (not a JSON string). Returns the explanation JSON.
  """
  @spec explain(String.t(), String.t(), map(), keyword()) :: result()
  def explain(domain, problem, plan, opts \\ [])
      when is_binary(domain) and is_binary(problem) and is_map(plan) do
    call(
      %{"op" => "explain", "domain" => domain, "problem" => problem, "plan" => plan},
      timeout(opts, @heavy_timeout)
    )
  end

  # ---------------------------------------------------------------------
  # Ops -- session lifecycle
  # ---------------------------------------------------------------------

  @doc """
  `{"op":"session_new","domain":d,"problem":p}` -- grounds a new session.
  Returns `{:ok, %{"handle" => n}}`.
  """
  @spec session_new(String.t(), String.t(), keyword()) :: result()
  def session_new(domain, problem, opts \\ []) when is_binary(domain) and is_binary(problem) do
    call(
      %{"op" => "session_new", "domain" => domain, "problem" => problem},
      timeout(opts, @heavy_timeout)
    )
  end

  @doc "`{\"op\":\"session_fork\",\"handle\":h}` -- a cheap fork sharing the grounded world."
  @spec session_fork(non_neg_integer(), keyword()) :: result()
  def session_fork(handle, opts \\ []) when is_integer(handle) do
    call(%{"op" => "session_fork", "handle" => handle}, timeout(opts, @cheap_timeout))
  end

  @doc "`{\"op\":\"session_free\",\"handle\":h}` -- releases the session handle."
  @spec session_free(non_neg_integer(), keyword()) :: result()
  def session_free(handle, opts \\ []) when is_integer(handle) do
    call(%{"op" => "session_free", "handle" => handle}, timeout(opts, @cheap_timeout))
  end

  @doc "`{\"op\":\"session_set_goal\",\"handle\":h,\"goal\":g}`."
  @spec session_set_goal(non_neg_integer(), String.t(), keyword()) :: result()
  def session_set_goal(handle, goal, opts \\ []) when is_integer(handle) and is_binary(goal) do
    call(%{"op" => "session_set_goal", "handle" => handle, "goal" => goal}, timeout(opts, @cheap_timeout))
  end

  @doc """
  `{"op":"session_restrict_prefix_claims","handle":h,"prefix":pre,
  "claimed":csv}` -- the bazaar's op-display-prefix-plus-claims-blackout
  scoping (`claimed` is a comma-separated string, as the wasm ABI expects).
  """
  @spec session_restrict_prefix_claims(non_neg_integer(), String.t(), String.t(), keyword()) ::
          result()
  def session_restrict_prefix_claims(handle, prefix, claimed, opts \\ [])
      when is_integer(handle) and is_binary(prefix) and is_binary(claimed) do
    call(
      %{
        "op" => "session_restrict_prefix_claims",
        "handle" => handle,
        "prefix" => prefix,
        "claimed" => claimed
      },
      timeout(opts, @cheap_timeout)
    )
  end

  @doc "`{\"op\":\"session_restrict_contains\",\"handle\":h,\"filter\":f}`."
  @spec session_restrict_contains(non_neg_integer(), String.t(), keyword()) :: result()
  def session_restrict_contains(handle, filter, opts \\ [])
      when is_integer(handle) and is_binary(filter) do
    call(
      %{"op" => "session_restrict_contains", "handle" => handle, "filter" => filter},
      timeout(opts, @cheap_timeout)
    )
  end

  @doc """
  `{"op":"session_think","handle":h,"evals":n,"mem_mb":n}` -- a bounded
  replan; stashes the resulting plan (if solved) and resets the cursor.
  Returns the Solution map.
  """
  @spec session_think(non_neg_integer(), non_neg_integer(), non_neg_integer(), keyword()) ::
          result()
  def session_think(handle, evals, mem_mb, opts \\ [])
      when is_integer(handle) and is_integer(evals) and is_integer(mem_mb) do
    call(
      %{"op" => "session_think", "handle" => handle, "evals" => evals, "mem_mb" => mem_mb},
      timeout(opts, @heavy_timeout)
    )
  end

  @doc "`{\"op\":\"session_valid\",\"handle\":h}` -- free replay check, no search spent."
  @spec session_valid?(non_neg_integer(), keyword()) :: result()
  def session_valid?(handle, opts \\ []) when is_integer(handle) do
    call(%{"op" => "session_valid", "handle" => handle}, timeout(opts, @cheap_timeout))
  end

  @doc "`{\"op\":\"session_step\",\"handle\":h}` -- the step under the cursor, or `null`."
  @spec session_step(non_neg_integer(), keyword()) :: result()
  def session_step(handle, opts \\ []) when is_integer(handle) do
    call(%{"op" => "session_step", "handle" => handle}, timeout(opts, @cheap_timeout))
  end

  @doc "`{\"op\":\"session_suffix\",\"handle\":h}` -- the remaining plan steps."
  @spec session_suffix(non_neg_integer(), keyword()) :: result()
  def session_suffix(handle, opts \\ []) when is_integer(handle) do
    call(%{"op" => "session_suffix", "handle" => handle}, timeout(opts, @cheap_timeout))
  end

  @doc "`{\"op\":\"session_advance\",\"handle\":h}` -- advances the cursor by one step."
  @spec session_advance(non_neg_integer(), keyword()) :: result()
  def session_advance(handle, opts \\ []) when is_integer(handle) do
    call(%{"op" => "session_advance", "handle" => handle}, timeout(opts, @cheap_timeout))
  end

  @doc "`{\"op\":\"session_drop_plan\",\"handle\":h}` -- clears the stashed plan and cursor."
  @spec session_drop_plan(non_neg_integer(), keyword()) :: result()
  def session_drop_plan(handle, opts \\ []) when is_integer(handle) do
    call(%{"op" => "session_drop_plan", "handle" => handle}, timeout(opts, @cheap_timeout))
  end

  @doc "`{\"op\":\"session_has_plan\",\"handle\":h}`."
  @spec session_has_plan?(non_neg_integer(), keyword()) :: result()
  def session_has_plan?(handle, opts \\ []) when is_integer(handle) do
    call(%{"op" => "session_has_plan", "handle" => handle}, timeout(opts, @cheap_timeout))
  end

  @doc "`{\"op\":\"session_set_fact\",\"handle\":h,\"name\":n,\"value\":bool}`."
  @spec session_set_fact(non_neg_integer(), String.t(), boolean(), keyword()) :: result()
  def session_set_fact(handle, name, value, opts \\ [])
      when is_integer(handle) and is_binary(name) and is_boolean(value) do
    call(
      %{"op" => "session_set_fact", "handle" => handle, "name" => name, "value" => value},
      timeout(opts, @cheap_timeout)
    )
  end

  @doc "`{\"op\":\"session_set_timed_fact\",\"handle\":h,\"dt\":f,\"name\":n,\"value\":bool}`."
  @spec session_set_timed_fact(non_neg_integer(), number(), String.t(), boolean(), keyword()) ::
          result()
  def session_set_timed_fact(handle, dt, name, value, opts \\ [])
      when is_integer(handle) and is_number(dt) and is_binary(name) and is_boolean(value) do
    call(
      %{
        "op" => "session_set_timed_fact",
        "handle" => handle,
        "dt" => dt,
        "name" => name,
        "value" => value
      },
      timeout(opts, @cheap_timeout)
    )
  end

  @doc """
  `{"op":"session_observe","handle":h,"sight":[[name,value],...]}` -- a
  batch of observed (fact, value) pairs. Returns the resulting news/deltas.
  """
  @spec session_observe(non_neg_integer(), [{String.t(), boolean()}], keyword()) :: result()
  def session_observe(handle, sight, opts \\ []) when is_integer(handle) and is_list(sight) do
    call(
      %{"op" => "session_observe", "handle" => handle, "sight" => Enum.map(sight, &Tuple.to_list/1)},
      timeout(opts, @cheap_timeout)
    )
  end

  @doc "`{\"op\":\"session_goal_met\",\"handle\":h}`."
  @spec session_goal_met?(non_neg_integer(), keyword()) :: result()
  def session_goal_met?(handle, opts \\ []) when is_integer(handle) do
    call(%{"op" => "session_goal_met", "handle" => handle}, timeout(opts, @cheap_timeout))
  end

  @doc "`{\"op\":\"session_fact\",\"handle\":h,\"name\":n}` -- `{:ok, %{\"value\" => bool|nil}}`."
  @spec session_fact(non_neg_integer(), String.t(), keyword()) :: result()
  def session_fact(handle, name, opts \\ []) when is_integer(handle) and is_binary(name) do
    call(%{"op" => "session_fact", "handle" => handle, "name" => name}, timeout(opts, @cheap_timeout))
  end

  @doc "`{\"op\":\"session_apply_start\",\"handle\":h,\"name\":n}` -- durative-action start."
  @spec session_apply_start(non_neg_integer(), String.t(), keyword()) :: result()
  def session_apply_start(handle, name, opts \\ []) when is_integer(handle) and is_binary(name) do
    call(
      %{"op" => "session_apply_start", "handle" => handle, "name" => name},
      timeout(opts, @cheap_timeout)
    )
  end

  @doc "`{\"op\":\"session_elapse\",\"handle\":h,\"dt\":f}` -- advances simulated time."
  @spec session_elapse(non_neg_integer(), number(), keyword()) :: result()
  def session_elapse(handle, dt, opts \\ []) when is_integer(handle) and is_number(dt) do
    call(%{"op" => "session_elapse", "handle" => handle, "dt" => dt}, timeout(opts, @cheap_timeout))
  end

  @doc "`{\"op\":\"session_set_fluent\",\"handle\":h,\"name\":n,\"value\":f}`."
  @spec session_set_fluent(non_neg_integer(), String.t(), number(), keyword()) :: result()
  def session_set_fluent(handle, name, value, opts \\ [])
      when is_integer(handle) and is_binary(name) and is_number(value) do
    call(
      %{"op" => "session_set_fluent", "handle" => handle, "name" => name, "value" => value},
      timeout(opts, @cheap_timeout)
    )
  end

  @doc "`{\"op\":\"session_fluent\",\"handle\":h,\"name\":n}` -- `{:ok, %{\"value\" => f64|nil}}`."
  @spec session_fluent(non_neg_integer(), String.t(), keyword()) :: result()
  def session_fluent(handle, name, opts \\ []) when is_integer(handle) and is_binary(name) do
    call(%{"op" => "session_fluent", "handle" => handle, "name" => name}, timeout(opts, @cheap_timeout))
  end

  @doc """
  `{"op":"session_plan_valid","handle":h,"plan":plan,"from":n}` -- checks
  an externally-supplied plan is still valid from step index `from`,
  without mutating session state.
  """
  @spec session_plan_valid?(non_neg_integer(), map(), non_neg_integer(), keyword()) :: result()
  def session_plan_valid?(handle, plan, from, opts \\ [])
      when is_integer(handle) and is_map(plan) and is_integer(from) do
    call(
      %{"op" => "session_plan_valid", "handle" => handle, "plan" => plan, "from" => from},
      timeout(opts, @cheap_timeout)
    )
  end

  @doc "`{\"op\":\"session_world_bytes\",\"handle\":h}`."
  @spec session_world_bytes(non_neg_integer(), keyword()) :: result()
  def session_world_bytes(handle, opts \\ []) when is_integer(handle) do
    call(%{"op" => "session_world_bytes", "handle" => handle}, timeout(opts, @cheap_timeout))
  end

  @doc "`{\"op\":\"session_mind_bytes\",\"handle\":h}`."
  @spec session_mind_bytes(non_neg_integer(), keyword()) :: result()
  def session_mind_bytes(handle, opts \\ []) when is_integer(handle) do
    call(%{"op" => "session_mind_bytes", "handle" => handle}, timeout(opts, @cheap_timeout))
  end

  # ---------------------------------------------------------------------
  # Core private call -- the wire sequence documented in the moduledoc,
  # a straight copy of BeamPM.Rust4PM's against fp_* instead of r4pm_*
  # ---------------------------------------------------------------------

  defp call(req, timeout) when is_map(req) do
    data = JSON.encode!(req)
    len = byte_size(data)

    with {:ok, {pid, store, memory}} <- engine(),
         {:ok, [raw_ptr]} <- call_export(pid, "fp_alloc", [len], timeout),
         ptr = band(raw_ptr, 0xFFFF_FFFF),
         :ok <- if(ptr == 0, do: {:error, :guest_alloc_failed}, else: :ok),
         :ok <- write_request(pid, store, memory, ptr, len, data),
         {:ok, [packed]} <- call_export(pid, "fp_call", [ptr, len], timeout) do
      # fp_call has consumed (and freed) the request buffer at `ptr` --
      # deallocating it here would be a double free. Only the response
      # buffer below is host-owned.
      read_response(pid, store, memory, packed, timeout)
    else
      {:error, {:call_exit, _} = reason} ->
        # A timeout/trap may have interrupted the guest mid-compute; the
        # guest's registries can't be trusted afterwards. Restart the
        # engine: converts "possibly wedged" into the documented "restart
        # invalidates all handles" contract.
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
        _ = call_export(pid, "fp_dealloc", [ptr, len], @cheap_timeout)
        err
    end
  end

  defp read_response(pid, store, memory, packed, timeout) do
    packed = band(packed, 0xFFFF_FFFF_FFFF_FFFF)
    out_ptr = bsr(packed, 32)
    out_len = band(packed, 0xFFFF_FFFF)

    out = Wasmex.Memory.read_binary(store, memory, out_ptr, out_len)
    _ = call_export(pid, "fp_dealloc", [out_ptr, out_len], timeout)

    case JSON.decode!(out) do
      # A bare `{"error": <string-or-object>}` response (exactly one key)
      # is a genuine op-level failure -- unknown op, unknown handle, a
      # parse/serialize failure inside the engine. Collapse it to an
      # {:error, {:engine, _}} tuple, same convention as BeamPM.Rust4PM.
      #
      # A response that carries an "error" key ALONGSIDE other top-level
      # keys (e.g. plan_production's OperationEnvelope refusal shape --
      # schema_version/outcome/authority/payload/error) is NOT an op
      # failure: it is a legitimate, structured "refused" answer the
      # caller needs the whole envelope of, so it passes through as
      # {:ok, decoded} untouched -- collapsing it here would silently
      # discard outcome/authority/payload for every strict-mode refusal.
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
        {:error, {:engine_not_started, "call BeamPM.Ferroplan.start/0 first"}}

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

defmodule BeamPM.Ferroplan.Health do
  @moduledoc """
  A single-candidate engine-health status probe for the ferroplan planning
  engine, the same shape as `BeamPM.Rust4PM.Health` for the process-mining
  engine -- two independent engines, each with its own health probe rather
  than a shared `select/2`-with-fallback abstraction, matching the standing
  "one real engine per domain" directive.
  """

  @type standing :: :alive | :blocked
  @type status :: %{
          id: :ferroplan_wasm,
          kind: :engine,
          standing: standing(),
          reason: String.t() | nil,
          evidence: %{wasm_path: String.t(), artifact_present: boolean(), engine_started: boolean() | nil}
        }

  @doc """
  Real health check: confirms the wasm artifact exists on disk AND that
  the engine can actually start (or is already started).
  """
  @spec status() :: status()
  def status do
    artifact_present = BeamPM.Ferroplan.wasm_built?()

    if artifact_present do
      case BeamPM.Ferroplan.start() do
        {:ok, _pid} ->
          %{
            id: :ferroplan_wasm,
            kind: :engine,
            standing: :alive,
            reason: nil,
            evidence: %{
              wasm_path: BeamPM.Ferroplan.wasm_path(),
              artifact_present: true,
              engine_started: true
            }
          }

        {:error, reason} ->
          %{
            id: :ferroplan_wasm,
            kind: :engine,
            standing: :blocked,
            reason: "artifact present but engine failed to start: #{inspect(reason)}",
            evidence: %{
              wasm_path: BeamPM.Ferroplan.wasm_path(),
              artifact_present: true,
              engine_started: false
            }
          }
      end
    else
      %{
        id: :ferroplan_wasm,
        kind: :engine,
        standing: :blocked,
        reason: BeamPM.Ferroplan.wasm_missing_reason(),
        evidence: %{
          wasm_path: BeamPM.Ferroplan.wasm_path(),
          artifact_present: false,
          engine_started: nil
        }
      }
    end
  end
end
