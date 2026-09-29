defmodule BeamPM.FerroplanBridge.ExactSubject do
  @enforce_keys [:repo, :sha, :task]
  defstruct [:repo, :sha, :task]
  def bind(repo, sha, task) when is_binary(repo) and is_binary(sha) and is_binary(task) do
    if String.contains?(repo, "/") and byte_size(sha) == 40 and task != "", do: {:ok, %__MODULE__{repo: repo, sha: sha, task: task}}, else: {:error, :invalid_exact_subject}
  end
  def same?(%__MODULE__{repo: r, sha: s}, %__MODULE__{repo: r, sha: s}), do: true
  def same?(_, _), do: false
end
