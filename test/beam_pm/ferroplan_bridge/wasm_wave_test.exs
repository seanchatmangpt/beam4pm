defmodule BeamPM.FerroplanBridge.PortableContractWaveTest do
  use ExUnit.Case, async: true
  test "wasm wave exposes its primary runtime primitive" do
    assert Code.ensure_loaded?(BeamPM.FerroplanBridge.PortableContract)
  end
end
