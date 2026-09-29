defmodule BeamPM.ResearchRuntime.AttemptBudget do
  @moduledoc false
  defstruct used:0,max:3
  def take(%__MODULE__{used:u,max:m}=b) when u<m, do: {:ok,%{b|used:u+1}}
  def take(b), do: {:error,:exhausted,b}
end
