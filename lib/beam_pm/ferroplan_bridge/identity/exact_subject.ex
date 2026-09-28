defmodule BeamPM.FerroplanBridge.ExactSubject do
  @moduledoc "Bounded ExactSubject primitive for the Ferroplan provider composition runtime."
  def bind(repo, sha), do: %{repo: repo, sha: sha}
  def same?(%{sha: a}, %{sha: b}), do: a == b
end
