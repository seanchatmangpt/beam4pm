defmodule BeamPM.FerroplanBridge.Receipt do
  @moduledoc "Bounded Receipt primitive for the Ferroplan provider composition runtime."
  def bind(subject,evidence,epoch,edge), do: %{subject:subject,evidence:evidence,epoch:epoch,edge:edge}
end
