defmodule BeamPM.ResearchRuntime.Provider do
  @moduledoc false
  @callback execute(map(),map()) :: {:ok,term()} | {:error,term()}
end
