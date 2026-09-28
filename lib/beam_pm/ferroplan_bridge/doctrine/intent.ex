defmodule BeamPM.FerroplanBridge.Intent do
  @enforce_keys [:id, :goal]
  defstruct [:id, :goal, authority: :none]
  def new(id, goal) when id != "" and goal != "", do: %__MODULE__{id: id, goal: goal}
end
