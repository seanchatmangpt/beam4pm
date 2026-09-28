defmodule BeamPM.FerroplanBridge.GraphlawWaveTest do
  use ExUnit.Case, async: true
  alias BeamPM.FerroplanBridge.{GraphInvariant, MigrationGuard, SemanticPart}
  test "migration preserves subject and prior receipts" do
    assert :ok=MigrationGuard.admit(%{subject:"s",receipts:["r1"]},%{subject:"s",receipts:["r1","r2"]})
    p=%SemanticPart{id:"x",source:"o",digest:"d",consequence:"c"}; assert SemanticPart.same?(p,p)
    assert {:ok,1}=GraphInvariant.enforce("positive",1,&(&1>0))
  end
end
