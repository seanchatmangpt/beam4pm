defmodule BeamPM.FerroplanBridge.SourceBindingWaveTest do
  use ExUnit.Case, async: true
  test "federation wave exposes its primary runtime primitive" do
    assert Code.ensure_loaded?(BeamPM.FerroplanBridge.SourceBinding)
  end
end
