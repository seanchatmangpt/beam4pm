defmodule BeamPM.ResearchRuntime.ProviderRegistry do
  @moduledoc false
  use GenServer
  def start_link(o \\ []), do: GenServer.start_link(__MODULE__,%{},Keyword.put_new(o,:name,__MODULE__))
  def init(s), do: {:ok,s}
  def put(n,m), do: GenServer.call(__MODULE__,{:put,n,m})
  def get(n), do: GenServer.call(__MODULE__,{:get,n})
  def handle_call({:put,n,m},_,s), do: {:reply,:ok,Map.put(s,n,m)}
  def handle_call({:get,n},_,s), do: {:reply,Map.fetch(s,n),s}
end
