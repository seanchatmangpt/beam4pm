defmodule BeamPM.FerroplanBridge.WorkOrderWaveTest do
  use ExUnit.Case, async: true
  test "intervention wave exposes its primary runtime primitive" do
    assert Code.ensure_loaded?(BeamPM.FerroplanBridge.WorkOrder)
  end
end
