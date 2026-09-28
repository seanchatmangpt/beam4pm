defmodule BeamPM.ResearchRuntime.ExactSubject do
  @moduledoc false
  defstruct [:repo,:sha,:task]
  def bind(r,s,t) when byte_size(s)==40, do: {:ok,%__MODULE__{repo:r,sha:s,task:t}}
  def bind(_,_,_), do: {:error,:invalid_subject}
end
