defmodule BeamPM.FerroplanBridge.SemanticEdgeWaveTest do
  use ExUnit.Case, async: true
  test "interchange wave exposes its primary runtime primitive" do
    assert Code.ensure_loaded?(BeamPM.FerroplanBridge.SemanticEdge)
  end
end
