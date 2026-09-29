defmodule BeamPM.FerroplanBridge.Coordinator do
  use GenServer

  alias BeamPM.FerroplanBridge.{EdgeSet, ExecutionEnvelope, RecoveryReceipt}
  alias BeamPM.ReplanRouter
  alias BeamPM.SA2A.{RecoveryReceiptAdapter, ReplanConsumer}

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  def execute(pid, envelope, edges),
    do: GenServer.call(pid, {:execute, envelope, edges})

  def run(pid, envelope, edges, decision, handle, inputs, opts \\ []),
    do: GenServer.call(pid, {:run, envelope, edges, decision, handle, inputs, opts})

  def replan(pid, envelope, edges, router_state, handle, sight, context, inputs, opts \\ []) do
    with {:ok, observation} <- ReplanRouter.observe(handle, sight, context) do
      {decision, evidence, next_router_state} = ReplanRouter.route(observation, router_state)

      case run(
             pid,
             envelope,
             edges,
             decision,
             handle,
             Map.put(inputs, :evidence, evidence),
             opts
           ) do
        {:ok, dispatch} ->
          {:ok,
           %{
             decision: decision,
             evidence: evidence,
             router_state: next_router_state,
             dispatch: dispatch
           }}

        {:error, reason} ->
          {:error,
           %{
             decision: decision,
             evidence: evidence,
             router_state: next_router_state,
             dispatch_error: reason
           }}
      end
    end
  end

  @impl true
  def init(opts) do
    {:ok, %{max_attempts: opts |> Keyword.get(:max_attempts, 3) |> max(1)}}
  end

  @impl true
  def handle_call({:execute, %ExecutionEnvelope{} = env, edges}, _from, state) do
    case select_edge(edges, env.capability, env.failed_edges) do
      nil ->
        {:reply, {:error, :no_lawful_provider}, state}

      edge ->
        receipt =
          case env.failed_edges do
            [failed | _] -> RecoveryReceipt.new(env.subject, %{id: failed}, edge)
            [] -> nil
          end

        {:reply, {:ok, edge, receipt}, state}
    end
  end

  @impl true
  def handle_call(
        {:run, %ExecutionEnvelope{} = env, edges, decision, handle, inputs, opts},
        _from,
        state
      ) do
    opts = Keyword.put_new(opts, :max_attempts, state.max_attempts)

    reply =
      case ReplanConsumer.run(env, edges, decision, handle, inputs, opts) do
        {:ok, result} ->
          edge = RecoveryReceiptAdapter.edge_for_provider(edges, result.provider)

          {:ok,
           %{
             edge: edge,
             result: result.candidate,
             failed_edges: result.excluded,
             replay_key: result.replay_key,
             recovery_receipt: RecoveryReceiptAdapter.from_loop(env.subject, result, edges)
           }}

        {:error, reason} ->
          {:error, reason}
      end

    {:reply, reply, state}
  end

  defp select_edge(edges, capability, failed_edges) do
    failed_edges
    |> Enum.reduce(edges, fn failed, acc -> EdgeSet.exclude(acc, failed) end)
    |> EdgeSet.select(capability)
  end
end
