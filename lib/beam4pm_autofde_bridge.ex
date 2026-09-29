defmodule BeamPM.AutofdeBridge do
  @moduledoc """
  Persistent stdio JSON-lines port bridge to autofde-lab's BEAM port
  bridge (`src/autofde_lab/beam/beam_port_bridge.py`, lab master @
  fe81a552).

  One long-lived OS interpreter serves many requests over a single
  BEAM `Port` (stdio), so every request after the first skips the
  ~1s Python/import boot the one-shot Typer CLI path (`BeamPM.Dfcm`'s
  `priv/bin/autofde` trampoline) pays per call.

  ## Protocol contract (witnessed against the lab implementation)

  Framing: newline-delimited single-line JSON objects over the port's
  stdio; exactly one reply line per request line, in request order;
  blank request lines are ignored by the bridge. The bridge never
  exits on a bad request: every failure becomes an
  `{"ok": false, "error": ..., "exception_type": ...}` envelope line.

  Requests (this client surfaces the bridge's full op set):

    * `{"op": "ping"}` -> `{"ok": true, "pong": true}`
    * `{"op": "cmca_allocate", "plan_id": str, "budget": {...},
       "candidates": [...]}` -> `{"ok": true, "plan": {...}}`
    * `{"op": "calculate_salience", "branch": {...}}` ->
      `{"ok": true, "salience": float}`
    * any other op -> `{"ok": false, "error": "unknown_op: <op>"}`

  `cmca_allocate` is the lab's certified multifractal cascade
  allocation solve. The lab's `fabric` commands are NOT exposed over
  the bridge (no such ops exist in `beam_port_bridge.py` -- recorded
  failed edge; fabric parity runs through the CLI wrapper instead).

  ## Return values

    * `{:ok, map()}` -- decoded reply line with `"ok": true`
    * `{:error, {:bridge_error, map()}}` -- decoded reply line with
      `"ok": false` (the bridge process itself stayed up)
    * `{:error, :bridge_down}` -- the port process died or could not
      be started; the GenServer restarts the interpreter lazily on
      the next request (`restart/1` forces it eagerly)
    * `{:error, :request_timeout}` -- no reply line within the
      timeout; because replies are strictly ordered, ordering can no
      longer be trusted, so the port is closed, remaining waiters are
      failed, and the interpreter restarts on the next request
  """

  use GenServer

  @default_timeout 30_000
  @registered_name __MODULE__

  ## --- client API ---

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @registered_name)

    GenServer.start_link(__MODULE__, Map.new(Keyword.take(opts, [:lab_root])), name: name)
  end

  @doc "Ping the bridge interpreter (cheapest high-information gate)."
  @spec ping(GenServer.server(), non_neg_integer()) :: {:ok, map()} | {:error, term()}
  def ping(server \\ @registered_name, timeout \\ @default_timeout) do
    request(server, %{"op" => "ping"}, timeout)
  end

  @doc """
  Run one real CMCA multifractal cascade allocation solve through the
  persistent bridge. `budget` keys: `:total_ticks`, `:memory_bytes`,
  `:max_verification_depth`, `:consequence_risk_budget`,
  `:concurrency_lanes`. Candidates are maps with `:branch_id`,
  `:option_entropy`, `:estimated_cost`, `:historical_yield` (plus
  optional `:operator_id`, `:world_id`, `:state_id`, `:metadata`).
  """
  @spec cmca_allocate(GenServer.server(), String.t(), map(), [map()], non_neg_integer()) ::
          {:ok, map()} | {:error, term()}
  def cmca_allocate(server \\ @registered_name, plan_id, budget, candidates, timeout \\ @default_timeout) do
    request(
      server,
      %{
        "op" => "cmca_allocate",
        "plan_id" => plan_id,
        "budget" => stringify_keys(budget),
        "candidates" => Enum.map(candidates, &stringify_keys/1)
      },
      timeout
    )
  end

  @doc "Compute the exact Q16.16 salience measure for one candidate branch."
  @spec calculate_salience(GenServer.server(), map(), non_neg_integer()) ::
          {:ok, map()} | {:error, term()}
  def calculate_salience(server \\ @registered_name, branch, timeout \\ @default_timeout) do
    request(server, %{"op" => "calculate_salience", "branch" => stringify_keys(branch)}, timeout)
  end

  @doc "Send one raw request map (must carry an \"op\") and await its reply line."
  @spec request(GenServer.server(), map(), non_neg_integer()) :: {:ok, map()} | {:error, term()}
  def request(server \\ @registered_name, req, timeout \\ @default_timeout) when is_map(req) do
    try do
      GenServer.call(server, {:request, req, timeout}, timeout + 5_000)
    catch
      :exit, {:timeout, _} -> {:error, :request_timeout}
      :exit, {:noproc, _} -> {:error, :bridge_down}
      :exit, _ -> {:error, :bridge_down}
    end
  end

  @doc """
  Force-close the current port (if any); the interpreter restarts
  lazily on the next request. Returns :ok regardless of prior state.
  """
  @spec restart(GenServer.server()) :: :ok
  def restart(server \\ @registered_name) do
    GenServer.call(server, :restart, @default_timeout)
  end

  @doc "The OS pid of the bridge interpreter process (integer or charlist), when the port is up."
  @spec os_pid(GenServer.server()) :: integer() | charlist() | nil
  def os_pid(server \\ @registered_name) do
    GenServer.call(server, :os_pid, 5_000)
  end

  @doc """
  Same call, one-shot: spawn a fresh interpreter per call through the
  CLI path, exactly like `BeamPM.Dfcm.run_autofde_cli/1` (app env
  `:autofde_cli_path` -> `AUTOFDE_CLI_PATH` -> `priv/bin/autofde`
  trampoline), falling back to the lab venv's python
  `-m autofde_lab.cli` directly when the trampoline is absent. Pays
  the interpreter boot on EVERY call.
  """
  @spec oneshot_cmca_allocate(String.t(), map(), [map()], non_neg_integer()) ::
          {:ok, map()} | {:error, term()}
  def oneshot_cmca_allocate(plan_id, budget, candidates, timeout \\ 120_000) do
    args = [
      "cmca",
      "allocate",
      JSON.encode!(Enum.map(candidates, &stringify_keys/1)),
      "--plan-id",
      plan_id,
      "--total-ticks",
      to_string(Map.get(budget, :total_ticks, 10_000)),
      "--memory-bytes",
      to_string(Map.get(budget, :memory_bytes, 65_536)),
      "--max-verification-depth",
      to_string(Map.get(budget, :max_verification_depth, 6)),
      "--concurrency-lanes",
      to_string(Map.get(budget, :concurrency_lanes, 8))
    ]

    case run_oneshot(args, timeout) do
      {:ok, %{"ok" => true, "plan" => plan}} -> {:ok, %{"ok" => true, "plan" => plan}}
      {:ok, %{"error" => err}} -> {:error, {:bridge_error, %{"error" => err}}}
      other -> other
    end
  end

  @doc "Resolve the one-shot CLI invocation (trampoline or direct lab python)."
  @spec oneshot_cli() :: {:trampoline, String.t()} | {:direct_python, String.t()}
  def oneshot_cli do
    trampoline =
      Application.get_env(:beam4pm, :autofde_cli_path) ||
        System.get_env("AUTOFDE_CLI_PATH") ||
        Path.expand("priv/bin/autofde")

    if File.exists?(trampoline) do
      {:trampoline, trampoline}
    else
      {:direct_python, python_executable()}
    end
  end

  @doc "Path of the python interpreter used for the persistent bridge."
  @spec python_executable() :: String.t()
  def python_executable do
    venv = lab_root() && Path.join([lab_root(), ".venv", "bin", "python3"])

    if venv && File.exists?(venv) do
      venv
    else
      System.find_executable("python3") || "python3"
    end
  end

  @doc """
  Resolve the autofde-lab checkout: app env `:autofde_lab_root` ->
  `AUTOFDE_LAB_ROOT` -> `<cwd>/../autofde-lab` -> `~/autofde-lab`,
  first candidate that actually contains the lab's src tree.
  """
  @spec lab_root() :: String.t() | nil
  def lab_root do
    candidates = [
      Application.get_env(:beam4pm, :autofde_lab_root),
      System.get_env("AUTOFDE_LAB_ROOT"),
      Path.expand("../autofde-lab", File.cwd!()),
      Path.expand("~/autofde-lab")
    ]

    Enum.find(candidates, fn
      root when is_binary(root) -> File.exists?(Path.join(root, "src/autofde_lab"))
      _ -> false
    end)
  end

  @doc "True when the lab checkout and its bridge entry script can be resolved."
  @spec available?() :: boolean()
  def available? do
    case lab_root() do
      nil -> false
      root -> File.exists?(Path.join(root, "src/autofde_lab/beam/beam_port_bridge.py"))
    end
  end

  @doc "Human-readable reason the bridge is unavailable, or nil when available."
  @spec missing_reason() :: String.t() | nil
  def missing_reason do
    if available?(), do: nil, else: "autofde-lab checkout with src/autofde_lab not resolvable"
  end

  ## --- one-shot internals ---

  defp run_oneshot(args, _timeout) do
    invocation = oneshot_cli()

    env =
      case invocation do
        {:trampoline, _} -> %{}
        {:direct_python, _} -> %{"PYTHONPATH" => Path.join(lab_root(), "src")}
      end

    {cmd, cmd_args} =
      case invocation do
        {:trampoline, bin} -> {bin, args}
        {:direct_python, py} -> {py, ["-u", "-m", "autofde_lab.cli" | args]}
      end

    try do
      case System.cmd(cmd, cmd_args, env: env, stderr_to_stdout: false) do
        {output, 0} ->
          case JSON.decode(output) do
            {:ok, parsed} -> {:ok, parsed}
            {:error, err} -> {:error, {:invalid_json, err, output}}
          end

        {err_output, code} ->
          {:error, {:cli_failed, code, err_output}}
      end
    rescue
      e in ErlangError -> {:error, {:spawn_failed, Exception.message(e)}}
    end
  end

  ## --- GenServer callbacks ---

  @impl true
  def init(opts) do
    {:ok, %{lab_root: Map.get(opts, :lab_root), port: nil, buffer: <<>>,
            waiters: :queue.new(), restarts: 0, replies: 0}}
  end

  @impl true
  def handle_call({:request, req, timeout}, from, state) do
    case ensure_port(state) do
      {:ok, state} ->
        timer_ref = Process.send_after(self(), {:request_timeout, from}, timeout)

        try do
          Port.command(state.port, JSON.encode!(req) <> "\n")

          {:noreply,
           %{state | waiters: :queue.in({from, timer_ref}, state.waiters)}}
        rescue
          ArgumentError ->
            # port died between select and send; report and drop it
            Process.cancel_timer(timer_ref)

            {:reply, {:error, :bridge_down},
             state |> close_port() |> Map.update!(:restarts, &(&1 + 1))}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:restart, _from, state) do
    state =
      state
      |> close_port()
      |> Map.update!(:restarts, &(&1 + 1))

    {:reply, :ok, state}
  end

  def handle_call(:os_pid, _from, state) do
    os_pid =
      case state.port && Port.info(state.port, :os_pid) do
        {:os_pid, pid} -> pid
        _ -> nil
      end

    {:reply, os_pid, state}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    {:noreply, state |> Map.update!(:buffer, &(&1 <> data)) |> drain_lines()}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    :logger.debug("BeamPM.AutofdeBridge port exited (status #{status}); restarting on demand")

    state =
      state
      |> close_port()
      |> Map.update!(:restarts, &(&1 + 1))
      |> fail_all_waiters({:error, :bridge_down})

    {:noreply, state}
  end

  def handle_info({:request_timeout, from}, state) do
    # remove the timed-out waiter wherever it sits; replies are strictly
    # ordered, so ANY timed-out waiter poisons the ordering: fail everyone
    # remaining, drop the port, restart lazily on the next request
    remaining =
      state.waiters
      |> :queue.to_list()
      |> Enum.reject(fn {f, _t} -> f == from end)
      |> :queue.from_list()

    {:noreply,
     %{state | waiters: remaining}
     |> close_port()
     |> Map.update!(:restarts, &(&1 + 1))
     |> fail_all_waiters({:error, :bridge_down})
     |> reply_one(from, {:error, :request_timeout})}
  end

  def handle_info(_other, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    close_port(state)
    :ok
  end

  ## --- port plumbing ---

  defp ensure_port(%{port: port} = state) when port != nil, do: {:ok, state}

  defp ensure_port(state) do
    root = state.lab_root || lab_root()

    bridge_script =
      root && Path.join([root, "src", "autofde_lab", "beam", "beam_port_bridge.py"])

    if is_binary(bridge_script) and File.exists?(bridge_script) do
      py = python_executable()

      env =
        System.get_env()
        |> Map.put("PYTHONPATH", Path.join(root, "src"))
        |> Enum.map(fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)

      port =
        Port.open({:spawn_executable, py}, [
          :binary,
          :exit_status,
          :use_stdio,
          {:args, ["-u", "-m", "autofde_lab.beam.beam_port_bridge"]},
          {:env, env},
          {:cd, root}
        ])

      {:ok, %{state | port: port, buffer: <<>>}}
    else
      {:error, {:bridge_down, "autofde-lab checkout with beam_port_bridge.py not resolvable"}}
    end
  end

  defp close_port(%{port: nil} = state), do: %{state | port: nil, buffer: <<>>}

  defp close_port(%{port: port} = state) do
    try do
      Port.close(port)
    catch
      :error, _ -> :ok
    end

    %{state | port: nil, buffer: <<>>}
  end

  defp drain_lines(state) do
    case :binary.split(state.buffer, "\n") do
      [line, rest] ->
        state = %{state | buffer: rest}
        state = dispatch_reply(line, state)
        drain_lines(state)

      [_incomplete] ->
        state
    end
  end

  defp dispatch_reply(line, state) do
    case :queue.out(state.waiters) do
      {{:value, {from, timer_ref}}, rest} ->
        Process.cancel_timer(timer_ref)

        reply =
          case JSON.decode(line) do
            {:ok, %{"ok" => true} = map} -> {:ok, map}
            {:ok, %{"ok" => false} = map} -> {:error, {:bridge_error, map}}
            {:ok, other} -> {:error, {:bad_envelope, other}}
            {:error, err} -> {:error, {:invalid_json, err, line}}
          end

        GenServer.reply(from, reply)

        %{state | waiters: rest, replies: state.replies + 1}

      {:empty, _} ->
        :logger.warning("BeamPM.AutofdeBridge got unsolicited bridge line: ~ts", [line])
        state
    end
  end

  defp reply_one(state, from, reply) do
    GenServer.reply(from, reply)
    state
  end

  defp fail_all_waiters(state, reply) do
    :queue.to_list(state.waiters)
    |> Enum.each(fn {_from, timer_ref} -> Process.cancel_timer(timer_ref) end)

    Enum.reduce(:queue.to_list(state.waiters), state, fn {from, _t}, acc ->
      GenServer.reply(from, reply)
      acc
    end)

    %{state | waiters: :queue.new()}
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_value(v)}
      {k, v} -> {k, stringify_value(v)}
    end)
  end

  defp stringify_value(v) when is_map(v), do: stringify_keys(v)
  defp stringify_value(v) when is_list(v), do: Enum.map(v, &stringify_value/1)
  defp stringify_value(v), do: v
end
