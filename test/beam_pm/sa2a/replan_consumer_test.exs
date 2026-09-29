defmodule BeamPM.SA2A.ReplanConsumerTest do
  use ExUnit.Case, async: true

  alias BeamPM.FerroplanBridge.{ExecutionEnvelope, SemanticEdge}
  alias BeamPM.SA2A.ReplanConsumer

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

  test "Beam4PM delegates provider exclusion and replay identity to SA2A" do
    envelope = %ExecutionEnvelope{subject: "s", evidence: %{id: "e"}, epoch: 1, capability: :hddl}

    edges = [
      %SemanticEdge{id: "e0", provider: :failed, capability: :hddl, consequence: :plan},
      %SemanticEdge{id: "e1", provider: :working, capability: :hddl, consequence: :plan}
    ]

    providers = [failed: FailedProvider, working: WorkingProvider]

    assert {:ok,
            %{
              provider: :working,
              excluded: [:failed],
              replay_key: replay_key,
              candidate: %{subject: "s"}
            }} =
             ReplanConsumer.run(envelope, edges, :hddl_replan, 0, %{},
               sa2a_providers: providers,
               max_attempts: 2
             )

    assert byte_size(replay_key) == 64
  end
end
