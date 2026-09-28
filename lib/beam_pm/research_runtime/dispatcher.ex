defmodule BeamPM.ResearchRuntime.Dispatcher do
  @moduledoc false
  def dispatch(p,r,c \\ %{}) do try do p.execute(r,c) rescue e->{:error,{:local,e}} catch :exit,x->{:error,{:edge,x}} end end
end
