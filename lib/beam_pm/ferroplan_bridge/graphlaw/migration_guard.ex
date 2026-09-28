defmodule BeamPM.FerroplanBridge.MigrationGuard do
  @moduledoc "Bounded MigrationGuard primitive for the Ferroplan provider composition runtime."
  def admit(old,new), do: if(Map.get(old,:subject)==Map.get(new,:subject),do: :ok,else: {:error,:subject_changed})
end
