defmodule BeamPM.FerroplanBridge.IntentWaveTest do
  use ExUnit.Case, async: true
  test "doctrine wave exposes its primary runtime primitive" do
    assert Code.ensure_loaded?(BeamPM.FerroplanBridge.Intent)
  end
end
