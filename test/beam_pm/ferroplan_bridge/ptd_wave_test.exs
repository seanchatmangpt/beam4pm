defmodule BeamPM.FerroplanBridge.EpochWaveTest do
  use ExUnit.Case, async: true
  test "ptd wave exposes its primary runtime primitive" do
    assert Code.ensure_loaded?(BeamPM.FerroplanBridge.Epoch)
  end
end
