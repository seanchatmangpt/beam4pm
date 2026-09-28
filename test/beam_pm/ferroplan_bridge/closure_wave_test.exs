defmodule BeamPM.FerroplanBridge.ClosureWaveTest do
  use ExUnit.Case
  alias BeamPM.FerroplanBridge.{Coordinator, ExecutionEnvelope, SemanticEdge}
  test "coordinator selects surviving provider" do
    {:ok,pid}=Coordinator.start_link(max_attempts: 2)
    e=%ExecutionEnvelope{subject:"s",evidence:"e",epoch:1,capability:"plan",failed_edges:["bad"]}
    edges=[%SemanticEdge{id:"bad",capability:"plan",provider:"p1",consequence:"c"},%SemanticEdge{id:"good",capability:"plan",provider:"p2",consequence:"c"}]
    assert {:ok,%{id:"good"},%{replacement_edge:"good"}}=Coordinator.execute(pid,e,edges)
  end
end
