defmodule BeamPM.FerroplanBridge.WasmWaveTest do
  use ExUnit.Case, async: true
  alias BeamPM.FerroplanBridge.{ConsumerBoundary, PortableContract, ProviderAdapter}
  test "portable consumer preserves capability and provider identity" do
    a=%PortableContract{capability:"fond",abi:"wasi",digest:"a",version:1}; b=%PortableContract{capability:"fond",abi:"wasi",digest:"b",version:2}
    assert PortableContract.compatible?(a,b)
    assert ConsumerBoundary.request("s","fond",%{}).authority==:none
    assert {:ok,%{provider:"p"}}=ProviderAdapter.normalize({:ok,:x},"p")
  end
end
