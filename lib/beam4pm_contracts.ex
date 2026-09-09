defmodule BeamPM.Contracts do
  @moduledoc """
  Real hashed manifest of beam4pm's own admitted manufacturing artifacts --
  beam4pm's equivalent of `Ex4pm.contracts/0`.

  Not ggen-generated: hand-written, same convention as `BeamPM.Ocel`/
  `BeamPM.PowlDiscovery` (a wrapper/algorithm module over already-admitted
  artifacts on disk, not a projection of the ontology graph itself). Reuses
  `BeamPM.ReceiptChain.hash_file!/1`'s already-established
  `File.read!/1 |> :crypto.hash(:sha256, ...) |> Base.encode16(case: :lower)`
  idiom rather than reimplementing it.

  Scope, stated precisely: ex4pm's `Ex4pm.contracts/0` hashes FOUR admitted
  artifacts (ontology, SHACL shapes, WIT component-world contract, JSON
  Schema). beam4pm has no SHACL and no WIT file anywhere in this repo
  (confirmed by repo-wide search) -- its real, current admitted-artifact
  set is THREE files: `ontology.ttl` and its two real generated JSON
  Schema outputs. This manifest hashes exactly those three, not a fourth
  and fifth that don't exist.
  """

  alias BeamPM.ReceiptChain

  @artifacts %{
    ontology: "ontology.ttl",
    types_schema: "schema/beam4pm_types.schema.json",
    ai_contracts_schema: "schema/beam4pm_ai_contracts.schema.json"
  }

  @typedoc "One admitted artifact's real path plus its real sha256 hex digest."
  @type artifact :: %{path: String.t(), sha256: String.t()}

  @typedoc "The full manifest: per-artifact digests plus one combined contract hash."
  @type t :: %{
          version: String.t(),
          artifacts: %{atom() => artifact()},
          contract_hash: String.t()
        }

  @doc "The three real artifact ids this manifest hashes, and their real repo-relative paths."
  @spec artifacts() :: %{atom() => String.t()}
  def artifacts, do: @artifacts

  @doc """
  Reads and hashes every artifact in `artifacts/0` for real (no cached/
  precomputed value -- always the exact bytes on disk right now), then
  combines all three digests (sorted by artifact id for determinism) into
  one real sha256 `contract_hash` over their concatenation. Raises
  `File.Error` if an admitted artifact is missing from disk -- never
  silently omits it from the manifest.
  """
  @spec manifest() :: t()
  def manifest do
    artifact_manifests =
      Map.new(@artifacts, fn {id, path} ->
        {id, %{path: path, sha256: ReceiptChain.hash_file!(path)}}
      end)

    combined =
      artifact_manifests
      |> Enum.sort_by(fn {id, _} -> id end)
      |> Enum.map_join(fn {_id, %{sha256: sha}} -> sha end)

    contract_hash =
      combined
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    %{
      version: to_string(Application.spec(:beam4pm, :vsn)),
      artifacts: artifact_manifests,
      contract_hash: contract_hash
    }
  end
end
