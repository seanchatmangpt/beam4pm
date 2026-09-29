defmodule BeamPM.FerroplanBridge.SA2ACoordinatorTest do
  use ExUnit.Case, async: true

  alias BeamPM.FerroplanBridge.{Coordinator, ExecutionEnvelope, RecoveryReceipt, SemanticEdge}

  defmodule FailedProvider do
    def supports?(:hddl), do: true
    def supports?(_), do: false
    def propose(_request, _opts), do: {:error, :provider_down}
  end

  defmodule WorkingProvider do
    def supports?(:hddl), do: true
    def supports?(_), do: false
    def propose(request, _opts), do: {:ok, %{subject: request.subject, plan: [:candidate]}}
  end

  test "existing coordinator receipt shape is preserved while SA2A owns failover" do
    {:ok, pid} = Coordinator.start_link(max_attempts: 2)

    envelope = %ExecutionEnvelope{subject: "s", evidence: %{id: "ev"}, epoch: 3, capability: :hddl}

    edges = [
      %SemanticEdge{id: "e0", provider: :failed, capability: :hddl, consequence: :plan},
      %SemanticEdge{id: "e1", provider: :working, capability: :hddl, consequence: :plan}
    ]

    assert {:ok,
            %{
              edge: %{id: "e1"},
              failed_edges: [:failed],
              result: %{subject: "s"},
              recovery_receipt: %RecoveryReceipt{
                subject: "s",
                failed_edge: "e0",
                replacement_edge: "e1",
                provider: :working
              }
            }} =
             Coordinator.run(pid, envelope, edges, :hddl_replan, 0, %{},
               sa2a_providers: [failed: FailedProvider, working: WorkingProvider]
             )
  end
end
