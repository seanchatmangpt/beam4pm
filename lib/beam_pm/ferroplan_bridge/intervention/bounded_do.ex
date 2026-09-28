defmodule BeamPM.FerroplanBridge.BoundedDo do
  alias BeamPM.FerroplanBridge.{AuthorityFence, CommandBudget}
  def authorize(order) do
    with :ok <- AuthorityFence.require(order.authority, :construct),
         {:ok, next} <- CommandBudget.consume(order), do: {:ok, next}
  end
end
