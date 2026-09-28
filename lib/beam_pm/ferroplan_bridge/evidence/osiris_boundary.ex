defmodule BeamPM.FerroplanBridge.OsirisBoundary do
  @role %{observe: true, construct: false, do: false}
  def role, do: @role
  def bound(items, max) when max >= 0, do: Enum.take(items, -max)
  def consequential?(_), do: false
end
