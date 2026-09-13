defmodule BeamPM.Research.ERC do
  @moduledoc """
  Executable Research Claim (ERC) receipt emitter -- the `beam4pm` side of
  the same minimal EDS-charter `EDSResult` record ash_a2a's
  `AshA2A.Research.ERC` emits (Claim, Artifact, Evidence, Falsifier,
  Execution, Environment, Reproducible state). Independently implemented
  in this repo rather than shared as a dependency, since `ash_a2a` and
  `beam4pm` are deliberately separate services in the PPCX closure this
  bench exercises -- a shared library here would blur the same
  cross-process boundary the receipts are meant to document crossing.

  Records what a real, already-executed test observed; does not itself
  judge or assert anything.
  """

  @erc_dir Path.expand("../research/erc", __DIR__)

  @type evidence_state ::
          :proposed
          | :implemented
          | :executable
          | :observed
          | :verified
          | :reproducible
          | :reproduced
          | :falsified
          | :blocked
          | :unsupported
          | :unknown

  # Full evidence-state enum from the EDS charter -- deliberately not
  # just the states this repo happens to have used so far (:verified).
  @valid_states ~w(proposed implemented executable observed verified reproducible reproduced falsified blocked unsupported unknown)a

  @doc """
  Emit one real ERC receipt. Raises `ArgumentError` for a `:state`
  outside `t:evidence_state/0` -- an unrecognized state emitted silently
  would be the same collapse the charter's evidence-state model forbids.
  """
  @spec emit!(map()) :: {:ok, String.t()}
  def emit!(
        %{id: id, claim: claim, falsifier: falsifier, state: state, evidence: evidence} = attrs
      )
      when is_binary(id) and is_binary(claim) and is_binary(falsifier) and is_atom(state) do
    unless state in @valid_states do
      raise ArgumentError,
            "invalid ERC evidence state #{inspect(state)} -- must be one of #{inspect(@valid_states)}"
    end

    File.mkdir_p!(@erc_dir)

    receipt = %{
      "id" => id,
      "claim" => claim,
      "falsifier" => falsifier,
      "state" => Atom.to_string(state),
      "evidence" => evidence,
      "notes" => Map.get(attrs, :notes),
      "depends_on" => Map.get(attrs, :depends_on, []),
      "artifact" => %{
        "repo" => "beam4pm",
        "git_sha" => git_sha(),
        "git_dirty?" => git_dirty?()
      },
      "environment" => %{
        "elixir" => System.version(),
        "otp" => :erlang.system_info(:otp_release) |> to_string(),
        "hostname" => :inet.gethostname() |> elem(1) |> to_string()
      },
      "execution" => %{
        "emitted_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }

    ts = System.system_time(:millisecond)
    path = Path.join(@erc_dir, "#{id}-#{ts}.json")
    File.write!(path, JSON.encode!(receipt))
    {:ok, path}
  end

  @doc """
  Read every real receipt file under `research/erc/` in this repo,
  decoded, newest-write-first. `[]` (not an error) if none exist yet.
  """
  @spec list_receipts() :: [map()]
  def list_receipts do
    case File.ls(@erc_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.map(&Path.join(@erc_dir, &1))
        |> Enum.sort_by(&File.stat!(&1).mtime, :desc)
        |> Enum.map(&(&1 |> File.read!() |> JSON.decode!()))

      {:error, :enoent} ->
        []
    end
  end

  @doc """
  The ledger: latest real receipt per distinct ERC `id` -- current
  standing, not history (use `list_receipts/0` for full history).
  """
  @spec ledger() :: [map()]
  def ledger do
    list_receipts()
    |> Enum.uniq_by(& &1["id"])
    |> Enum.sort_by(& &1["id"])
  end

  defp git_sha do
    case System.cmd("git", ["rev-parse", "HEAD"], stderr_to_stdout: true) do
      {sha, 0} -> String.trim(sha)
      _ -> "unknown"
    end
  end

  defp git_dirty? do
    case System.cmd("git", ["status", "--porcelain"], stderr_to_stdout: true) do
      {"", 0} -> false
      {_output, 0} -> true
      _ -> :unknown
    end
  end
end
