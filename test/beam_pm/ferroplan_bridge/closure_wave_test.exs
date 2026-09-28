defmodule BeamPM.FerroplanBridge.ExecutionEnvelopeWaveTest do
  use ExUnit.Case, async: true
  test "closure wave exposes its primary runtime primitive" do
    assert Code.ensure_loaded?(BeamPM.FerroplanBridge.ExecutionEnvelope)
  end
end
