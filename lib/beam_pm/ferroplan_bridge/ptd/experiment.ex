defmodule BeamPM.FerroplanBridge.Experiment do
  def pair(control, phased) when control.subject == phased.subject do
    %{control: control, phased: phased, same_semantics: Map.get(control, :semantics) == Map.get(phased, :semantics)}
  end
  def pair(_, _), do: {:error, :subject_drift}
end
