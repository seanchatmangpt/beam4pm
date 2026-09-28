defmodule BeamPM.FerroplanBridge.GraphInvariantWaveTest do
  use ExUnit.Case, async: true
  test "graphlaw wave exposes its primary runtime primitive" do
    assert Code.ensure_loaded?(BeamPM.FerroplanBridge.GraphInvariant)
  end
end
