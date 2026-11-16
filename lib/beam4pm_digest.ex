defmodule BeamPM.Digest do
  @moduledoc """
  Injectable digest seam (YX/Y14, v26.11.9-integration).

  Internal content-digest call sites resolve their hash function through this
  seam instead of hardcoding `:crypto.hash(:sha256, _)`. The default is
  `BeamPM.Digest.SHA256`, so behavior is byte-identical with no
  configuration. Don't-convert surfaces stay out of scope by law (YX
  per-class verdicts, `repop docs/jira/v26.11.9-integration/resolutions.md`):
  the zcode OCEL verifier (port law, sha256 until zcode-cli locksteps),
  pinned formulas, wire passthroughs, and the license HMAC.

  The behaviour contract mirrors `AshPPlan.Digest` exactly (`hash/1`
  callback, binary -> binary), so a single blake3 module can satisfy both
  repos' seams when the NIF decision lands.

  Canonical BLAKE3 known-answer vectors:
  `repop kernel/crates/repop-kernel/tests/digest_kat.rs` (R1 receipt:
  `repop docs/jira/v26.11.9-integration/receipts/r1-blake3-kat.md` — upstream
  `blake3` crate proven against official vectors; the vendored
  `keyed_blake3.rs` failed multi-chunk vectors, which is the vendor-drift
  witness cited by YX).

  A custom module only needs `hash/1` (binary -> binary). A test-only module
  can be configured via `Application.put_env(:beam4pm, :digest_module, Mod)`.
  """

  @callback hash(input :: iodata()) :: binary()

  @doc "Hash `input` (binary or iolist) through the configured digest module."
  @spec hash(iodata()) :: binary()
  def hash(input), do: config().hash(input)

  @doc "Hex-encode a digest the way every call site already does (lowercase)."
  @spec hex(binary()) :: String.t()
  def hex(digest), do: Base.encode16(digest, case: :lower)

  defp config,
    do: Application.get_env(:beam4pm, :digest_module, BeamPM.Digest.SHA256)

  defmodule SHA256 do
    @moduledoc "Default digest module: sha256, identical to the former hardcoded calls."
    @behaviour BeamPM.Digest

    @impl true
    def hash(input), do: :crypto.hash(:sha256, IO.iodata_to_binary(input))
  end
end
