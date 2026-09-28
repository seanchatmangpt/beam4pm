defmodule BeamPM.FerroplanBridge.ModelRole do
  @permissions %{context: true, select: false, construct: false, do: false}
  def permissions, do: @permissions
  def allowed?(:context), do: true
  def allowed?(_), do: false
end
