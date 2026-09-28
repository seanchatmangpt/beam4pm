defmodule BeamPM.FerroplanBridge.OcelEventWaveTest do
  use ExUnit.Case, async: true
  test "ocel wave exposes its primary runtime primitive" do
    assert Code.ensure_loaded?(BeamPM.FerroplanBridge.OcelEvent)
  end
end
