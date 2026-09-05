# offline_bundle_check.exs -- real artifact-integrity proof for VISION-2030
# Section 17 ("Air-gapped operation makes process intelligence sovereign
# infrastructure") and its Section 24 falsifier ("air-gapped mode materially
# removes the core product value").
#
# Usage (from the repo root; needs `mix deps.get` already run):
#
#     mix run scripts/offline_bundle_check.exs
#
# Grounding for scope (read in full before writing this script, per this
# increment's own "do not invent a new definition" instruction -- the earlier
# citations to scripts/gate_lint_truth.sh and
# docs/reference/infra-beamops-first-principles.md were WRONG, corrected here):
#
#   - docs/jira/v26.8.29/07-security-airgap-compliance.md ("Zero-egress /
#     air-gap requirements": install from signed offline bundle; SBOM and
#     provenance included with every release; deterministic replay of
#     update/install validation).
#   - contracts/beam4pm-pro/09-signed-offline-bundle.ttl (B4PMP-2103,
#     `pro:requiredEvidence` = "offline bundle contains signature, SBOM,
#     provenance, immutable artifact digests, compatibility metadata, and
#     verifier instructions"; `pro:authorityCeiling "VERIFY"`;
#     `pro:refusalCode "REFUSED[UNSIGNED_OFFLINE_BUNDLE]"`).
#
# What this script REALLY proves (the "immutable artifact digests" leg of
# B4PMP-2103's six-part evidence list, plus a rudimentary "verifier
# instructions" leg -- this script itself, invoked as above, IS the verifier
# instructions):
#
#   1. Builds a real offline bundle: the real, currently-on-disk manufactured
#      surface beam4pm would need to RUN and to be REPRODUCIBLY REBUILT
#      without network access -- `ggen.lock` (pins every pack's content
#      hash), the manufactured `src/` (Erlang), `lib/` (Elixir), `gleam/src/`
#      (Gleam), `schema/` (wire-format JSON Schema) trees, and the vendored
#      `vendor/ggen-marketplace/packs/beam4pm-process-model-pack` templates
#      the ontology is compiled against. Every file is discovered from the
#      real filesystem (no invented file list).
#   2. Computes a real `bundle_digest`: sha256 over a sorted
#      "<sha256(file)>  <relative path>\n" manifest line per real bundled
#      file, then sha256 of that whole manifest -- deterministic or the
#      script raises.
#   3. Verifies the bundle against that digest twice, both against a REAL
#      byte-for-byte copy of the real bundle in a scratch temp dir (never
#      mutates the actual repo):
#        - untampered copy  -> recomputed digest must match  -> :verified
#        - one real byte flipped in one real bundled file (`ggen.lock`)
#          -> recomputed digest must differ -> :refused
#      Both outcomes are asserted; the script exits non-zero if either
#      control fails, so this doubles as a real gate.
#   4. Constructs a REAL `BeamPM.Types.OfflineBundleEvidence.new/1` from the
#      just-observed result (subject_sha = real `git rev-parse HEAD`,
#      bundle_digest = the real computed digest, observed_result = the real
#      outcome of control (3a)) -- not the canned
#      `"sample_subject_sha"` / `:sample_atom` fixture that
#      `lib/beam4pm_roundtrip.ex`'s `sample(:offline_bundle_evidence, _)`
#      clauses use for GATE M5 codec roundtrip coverage. Those fixture
#      clauses remain untouched and still serve their own (unrelated)
#      purpose: proving the generated struct/codec round-trips a value,
#      any value. This script is the first thing in the repository that
#      calls the same constructor with values that came from actually
#      observing this exact checkout.
#
# What this script explicitly does NOT prove (honest scope disclosure
# against B4PMP-2103's full six-part `requiredEvidence` list):
#
#   - signature            -- NOT proven. Nothing here signs the bundle or
#                              the digest with any key; there is no
#                              private-key material or signing authority in
#                              this repo to exercise.
#   - SBOM                  -- NOT proven. No software-bill-of-materials is
#                              generated for the bundled files or their
#                              dependency closure.
#   - provenance             -- NOT proven beyond the bundle's own
#                              `subject_sha` (the exact git commit). No
#                              SLSA-style attestation, build-system identity,
#                              or supply-chain provenance format is produced.
#   - compatibility metadata -- NOT proven. No target-environment
#                              (OS/OTP/Elixir/Gleam version, architecture)
#                              compatibility check is performed or recorded.
#   - verifier instructions -- only RUDIMENTARY coverage: this script *is*
#                              runnable verifier instructions
#                              (`mix run scripts/offline_bundle_check.exs`),
#                              but nothing packages it, or a corresponding
#                              digest manifest, as an artifact shipped
#                              alongside a real distributed bundle.
#
# Net: this is a first real proof of concept for the artifact-integrity leg
# of air-gapped operation (VISION-2030 Section 17 / Section 24), not a full
# signed-offline-bundle / entitlement proof (B4PMP-2103's remaining five
# evidence components, and the marketplace/entitlement infrastructure they'd
# ultimately bind to, are not implemented anywhere in this repo).

defmodule Beam4PM.OfflineBundleCheck do
  @moduledoc false

  # Real, on-disk manufactured surface + the vendored pack it is compiled
  # against + the lock file pinning every pack's content hash. Candidates
  # named directly in this increment's own charter; nothing here is invented.
  @bundle_roots [
    "ggen.lock",
    "src",
    "lib",
    "gleam/src",
    "schema",
    "vendor/ggen-marketplace/packs/beam4pm-process-model-pack"
  ]

  # A file guaranteed present in every bundle build (checked at runtime) used
  # as the real tamper target for the negative control.
  @tamper_target "ggen.lock"

  def main(_argv) do
    repo_root = File.cwd!()

    IO.puts("== beam4pm offline bundle integrity check ==")
    IO.puts("VISION-2030 Section 17 / Section 24 -- B4PMP-2103 \"immutable artifact digests\" leg")
    IO.puts("repo_root: #{repo_root}\n")

    files = discover_bundle_files(repo_root, @bundle_roots)

    unless @tamper_target in files do
      die("tamper target #{@tamper_target} was not discovered in the bundle -- cannot run negative control")
    end

    IO.puts("bundle roots: #{Enum.join(@bundle_roots, ", ")}")
    IO.puts("bundle files discovered (real, on-disk): #{length(files)}\n")

    subject_sha = git_head_sha(repo_root)
    IO.puts("subject_sha (real `git rev-parse HEAD`): #{subject_sha}")

    bundle_digest_original = bundle_digest(repo_root, files)
    IO.puts("bundle_digest (real, computed in place): #{bundle_digest_original}\n")

    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "beam4pm_offline_bundle_check_#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(tmp_dir)

    try do
      copy_bundle(repo_root, files, tmp_dir)

      # Positive control: a real byte-for-byte copy of the real bundle,
      # verified against the digest computed at build time above.
      copy_digest = bundle_digest(tmp_dir, files)
      verify_untampered = verify(copy_digest, bundle_digest_original)
      IO.puts("verify(untampered copy)                          => #{inspect(verify_untampered)}")

      # Negative control: flip one real byte in one real bundled file and
      # recompute -- the digest must differ and verification must refuse.
      tamper!(tmp_dir, @tamper_target)
      tampered_digest = bundle_digest(tmp_dir, files)
      verify_tampered = verify(tampered_digest, bundle_digest_original)

      IO.puts(
        "verify(1 byte flipped in #{@tamper_target})" <>
          String.duplicate(" ", max(1, 33 - String.length(@tamper_target))) <>
          "=> #{inspect(verify_tampered)}"
      )

      mechanism_ok = verify_untampered == :verified and verify_tampered == :refused
      IO.puts("\ntamper-detection mechanism behaves correctly: #{mechanism_ok}")

      {:ok, evidence} =
        BeamPM.Types.OfflineBundleEvidence.new(%{
          evidence_id: "offline_bundle_check-#{subject_sha}-#{bundle_digest_original}",
          subject_sha: subject_sha,
          bundle_digest: bundle_digest_original,
          observed_result: verify_untampered
        })

      IO.puts("\nreal BeamPM.Types.OfflineBundleEvidence")
      IO.puts("(constructed from the observed verification above, not the")
      IO.puts(" lib/beam4pm_roundtrip.ex sample/2 fixture):\n")
      IO.inspect(evidence, pretty: true, width: 100)

      print_scope_disclosure()

      unless mechanism_ok do
        die("\ntamper-detection mechanism did not behave as required -- refusing")
      end

      IO.puts("\nOK: artifact-integrity leg of B4PMP-2103 demonstrated against a real bundle.")
    after
      File.rm_rf!(tmp_dir)
    end
  end

  defp discover_bundle_files(repo_root, roots) do
    roots
    |> Enum.flat_map(fn root ->
      abs = Path.join(repo_root, root)

      cond do
        File.regular?(abs) -> [root]
        File.dir?(abs) -> walk_dir(abs) |> Enum.map(&Path.relative_to(&1, repo_root))
        true -> die("bundle root does not exist on disk: #{root} (repo_root=#{repo_root})")
      end
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp walk_dir(dir) do
    dir
    |> File.ls!()
    |> Enum.flat_map(fn entry ->
      path = Path.join(dir, entry)

      cond do
        File.dir?(path) -> walk_dir(path)
        File.regular?(path) -> [path]
        true -> []
      end
    end)
  end

  defp bundle_digest(base_dir, files) do
    files
    |> Enum.sort()
    |> Enum.map(fn rel ->
      content = File.read!(Path.join(base_dir, rel))
      file_sha = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
      "#{file_sha}  #{rel}\n"
    end)
    |> Enum.join()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp copy_bundle(repo_root, files, dest_dir) do
    Enum.each(files, fn rel ->
      src = Path.join(repo_root, rel)
      dst = Path.join(dest_dir, rel)
      File.mkdir_p!(Path.dirname(dst))
      File.cp!(src, dst)
    end)
  end

  defp tamper!(dest_dir, rel) do
    path = Path.join(dest_dir, rel)
    <<first_byte, rest::binary>> = File.read!(path)
    File.write!(path, <<rem(first_byte + 1, 256), rest::binary>>)
  end

  defp verify(actual_digest, expected_digest) do
    if actual_digest == expected_digest, do: :verified, else: :refused
  end

  defp git_head_sha(repo_root) do
    case System.cmd("git", ["rev-parse", "HEAD"], cd: repo_root) do
      {out, 0} -> String.trim(out)
      {out, code} -> die("git rev-parse HEAD failed (exit #{code}): #{out}")
    end
  end

  defp print_scope_disclosure do
    IO.puts("""

    -- honest scope disclosure against B4PMP-2103's requiredEvidence --
    (contracts/beam4pm-pro/09-signed-offline-bundle.ttl, grounded in
     docs/jira/v26.8.29/07-security-airgap-compliance.md)

      proven here:     immutable artifact digests (real sha256, real tamper
                        detection over the real bundle above)
      rudimentary:      verifier instructions (this script itself)
      NOT proven here:  signature, SBOM, provenance (beyond subject_sha),
                        compatibility metadata

    This is the artifact-integrity leg of VISION-2030 Section 17 / Section 24
    air-gapped operation -- not a full signed-offline-bundle/entitlement
    proof.
    """)
  end

  defp die(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

Beam4PM.OfflineBundleCheck.main(System.argv())
