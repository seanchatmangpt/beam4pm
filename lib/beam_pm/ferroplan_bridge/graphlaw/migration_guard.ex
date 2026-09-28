defmodule BeamPM.FerroplanBridge.MigrationGuard do
  def admit(%{subject: s, receipts: r1}, %{subject: s, receipts: r2}) when is_list(r1) and is_list(r2), do: if(MapSet.subset?(MapSet.new(r1), MapSet.new(r2)), do: :ok, else: {:error, :receipt_loss})
  def admit(_, _), do: {:error, :subject_changed}
end
