defmodule BeamPM.FerroplanBridge.SurvivalEvidenceWaveTest do
  use ExUnit.Case, async: true
  test "evolution wave exposes its primary runtime primitive" do
    assert Code.ensure_loaded?(BeamPM.FerroplanBridge.SurvivalEvidence)
  end
end
