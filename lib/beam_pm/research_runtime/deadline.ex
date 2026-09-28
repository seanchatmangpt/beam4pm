defmodule BeamPM.ResearchRuntime.Deadline do
  @moduledoc false
  def expired?(d,n \\ System.monotonic_time(:millisecond)), do: n>=d
end
