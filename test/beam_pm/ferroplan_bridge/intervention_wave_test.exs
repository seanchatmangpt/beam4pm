defmodule BeamPM.FerroplanBridge.InterventionWaveTest do
  use ExUnit.Case, async: true
  alias BeamPM.FerroplanBridge.{BoundedDo, WorkOrder}
  test "attempt budget is monotonic and bounded" do
    o=WorkOrder.new("w","s","plan",1)
    assert {:ok,o}=BoundedDo.authorize(o)
    assert {:error,:budget_exhausted}=BoundedDo.authorize(o)
  end
end
