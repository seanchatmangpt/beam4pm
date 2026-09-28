defmodule BeamPM.FerroplanBridge.Coordinator do
  use GenServer

  alias BeamPM.FerroplanBridge.{
    EdgeSet,
    ExecutionEnvelope,
    ProviderAdapter,
    RecoveryReceipt
  }

  alias BeamPM.ReplanRouter

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
    result =
      dispatch(
        env,
        edges,
        decision,
        handle,
        inputs,
        opts,
        state.max_attempts,
        Enum.reverse(env.failed_edges)
      )

    {:reply, result, state}
  end

  defp dispatch(_env, _edges, _decision, _handle, _inputs, _opts, 0, failed) do
    {:error, %{reason: :attempt_budget_exhausted, failed_edges: failed}}
  end

  defp dispatch(env, edges, decision, handle, inputs, opts, remaining, failed) do
    case select_edge(edges, env.capability, failed) do
      nil ->
        {:error, %{reason: :no_lawful_provider, failed_edges: failed}}

      edge ->
        case ProviderAdapter.invoke(edge.provider, decision, handle, inputs, opts) do
          {:ok, result} ->
            receipt =
              case List.last(failed) do
                nil -> nil
                failed_edge -> RecoveryReceipt.new(env.subject, %{id: failed_edge}, edge)
              end

            {:ok,
             %{
               edge: edge,
               result: result,
               failed_edges: failed,
               recovery_receipt: receipt
             }}

          {:error, provider_error} ->
            dispatch(
              env,
              edges,
              decision,
              handle,
              inputs,
              opts,
              remaining - 1,
              failed ++ [edge.id]
            )
            |> attach_provider_error(edge, provider_error)
        end
    end
  end

  defp attach_provider_error({:ok, result}, _failed_edge, _error), do: {:ok, result}

  defp attach_provider_error({:error, result}, failed_edge, error) do
    {:error,
     Map.merge(result, %{
       last_failed_edge: failed_edge.id,
       provider_error: error
     })}
  end

  defp select_edge(edges, capability, failed_edges) do
    failed_edges
    |> Enum.reduce(edges, fn failed, acc -> EdgeSet.exclude(acc, failed) end)
    |> EdgeSet.select(capability)
  end
end
