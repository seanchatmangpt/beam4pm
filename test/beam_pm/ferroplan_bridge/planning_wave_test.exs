defmodule BeamPM.FerroplanBridge.HddlTaskWaveTest do
  use ExUnit.Case, async: true
  test "planning wave exposes its primary runtime primitive" do
    assert Code.ensure_loaded?(BeamPM.FerroplanBridge.HddlTask)
  end
end
