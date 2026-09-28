defmodule BeamPM.FerroplanBridge.EvidenceAdmissionWaveTest do
  use ExUnit.Case, async: true
  test "evidence wave exposes its primary runtime primitive" do
    assert Code.ensure_loaded?(BeamPM.FerroplanBridge.EvidenceAdmission)
  end
end
