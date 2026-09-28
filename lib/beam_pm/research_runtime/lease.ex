defmodule BeamPM.ResearchRuntime.Lease do
  @moduledoc false
  defstruct [:key,:owner,:expires_at]
  def valid?(l,n \\ System.system_time(:millisecond)), do: l.expires_at>n
end
