defmodule BeamPM.FerroplanBridge.Coordinator do
  use GenServer
  alias BeamPM.FerroplanBridge.{ExecutionEnvelope, FondRecovery, RecoveryReceipt}
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
  def execute(pid, envelope, edges), do: GenServer.call(pid, {:execute, envelope, edges})
  def init(opts), do: {:ok, %{attempts: %{}, max_attempts: Keyword.get(opts, :max_attempts, 3)}}
  def handle_call({:execute, %ExecutionEnvelope{} = env, edges}, _from, state) do
    failed = List.first(env.failed_edges)
    edge = if failed, do: FondRecovery.recover(edges, failed, env.capability), else: Enum.find(edges, &(&1.enabled and &1.capability == env.capability))
    case edge do
      nil -> {:reply, {:error, :no_lawful_provider}, state}
      edge -> {:reply, {:ok, edge, if(failed, do: RecoveryReceipt.new(env.subject, %{id: failed}, edge), else: nil)}, state}
    end
  end
end
