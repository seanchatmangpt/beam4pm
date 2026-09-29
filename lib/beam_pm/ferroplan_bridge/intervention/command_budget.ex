defmodule BeamPM.FerroplanBridge.CommandBudget do
  def consume(%{attempt: a, max_attempts: m} = order) when a < m, do: {:ok, %{order | attempt: a + 1}}
  def consume(_), do: {:error, :budget_exhausted}
end
