defmodule BeamPM.FerroplanBridge.PlanningWaveTest do
  use ExUnit.Case, async: true
  alias BeamPM.FerroplanBridge.{FondRecovery, SemanticEdge}
  test "FOND recovery removes only failed provider edge" do
    edges=[%SemanticEdge{id:"bad",capability:"plan",provider:"p1",consequence:"c"},%SemanticEdge{id:"good",capability:"plan",provider:"p2",consequence:"c"}]
    assert FondRecovery.recover(edges,"bad","plan").id=="good"
  end
end
