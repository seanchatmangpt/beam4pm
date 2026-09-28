defmodule BeamPM.FerroplanBridge.ContextWindowWaveTest do
  use ExUnit.Case, async: true
  test "trimtab wave exposes its primary runtime primitive" do
    assert Code.ensure_loaded?(BeamPM.FerroplanBridge.ContextWindow)
  end
end
