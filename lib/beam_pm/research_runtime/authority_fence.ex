defmodule BeamPM.ResearchRuntime.AuthorityFence do
  @moduledoc false
  def admit(%{authority:a,capability:c}) when not is_nil(a) and not is_nil(c), do: :ok
  def admit(_), do: {:refused,:authority_missing}
end
