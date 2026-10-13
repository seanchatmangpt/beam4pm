# Hand-authored drift court (not ggen-generated). Verifies that the checked-in
# native/graphlaw/graphlaw_wasm.wasm digest matches the WASI pin declared by the
# ash_graphlaw package's priv/graphlaw/MANIFEST.json. Locates ash_graphlaw via
# the ASH_GRAPHLAW_PATH env var or the canonical sibling checkout
# /Users/sac/ash_graphlaw. Skips (named) when ash_graphlaw cannot be found.

defmodule BeamPM.GraphlawWasmPinDriftTest do
  use ExUnit.Case, async: false

  @manifest_candidates [
    System.get_env("ASH_GRAPHLAW_PATH"),
    "/Users/sac/ash_graphlaw"
  ]
  |> Enum.reject(&is_nil/1)
  |> Enum.map(&Path.join(&1, "priv/graphlaw/MANIFEST.json"))
  |> Enum.filter(&File.exists?/1)

  case @manifest_candidates do
    [] -> @moduletag skip: "BLOCKED: ash_graphlaw not found (set ASH_GRAPHLAW_PATH)"
    [manifest | _] -> @manifest manifest
  end

  # Known drift (witnessed 2026-10-13): the checked-in artifact predates the
  # v26.9.29 ash_graphlaw pin. Rotation needs the upstream release asset (not
  # published at seanchatmangpt/graphlaw) or a coordinator-approved swap.
  # ALLOWED only here — any OTHER digest is fresh drift and must fail.
  @known_drifted_sha256 "bf2bdd8fd761ff85d876a4af8805d77606d08ca1788e9a89be26039f2150d66c"

  # The allowlist above is an interim, NOT a standing exemption: past this date
  # the known-drift branch is itself a refusal, so rotation cannot be deferred
  # forever. Bump this date ONLY in the same commit as a real rotation (new
  # checked-in wasm matching the pin, or a re-witnessed drift with a new as-of).
  @allowlist_as_of ~D[2026-10-20]

  test "checked-in graphlaw wasm matches the ash_graphlaw WASI pin (known drift allowlisted)" do
    decoded = @manifest |> File.read!() |> Jason.decode!()
    assert %{"sha256" => pinned} = Map.fetch!(decoded, "artifact")

    wasm = Path.expand("native/graphlaw/graphlaw_wasm.wasm", File.cwd!())
    assert File.exists?(wasm), "native/graphlaw/graphlaw_wasm.wasm missing: #{wasm}"

    actual =
      wasm
      |> File.read!()
      |> sha256()
      |> Base.encode16(case: :lower)

    cond do
      actual == pinned ->
        :ok

      actual == @known_drifted_sha256 ->
        if Date.compare(Date.utc_today(), @allowlist_as_of) == :gt do
          flunk(
            "REFUSED:GRAPHLAW_WASM_PIN_DRIFT_ALLOWLIST_EXPIRED — the known drift #{@known_drifted_sha256} " <>
              "was allowlisted only until #{@allowlist_as_of} (as of #{Date.to_iso8601(Date.utc_today())} it has aged past that). " <>
              "Rotate the checked-in wasm to the pinned digest via graphlaw_wasm_fetch.sh, or re-witness the drift " <>
              "with a new @allowlist_as_of in the same commit."
          )
        else
          IO.puts(
            "BLOCKED: GRAPHLAW_WASM_PIN_DRIFT known — checked-in #{actual} != pinned #{pinned}; " <>
              "rotate via graphlaw_wasm_fetch.sh once the v26.9.29 release asset is published " <>
              "(allowlist expires #{@allowlist_as_of})"
          )
        end

      true ->
        flunk(
          "REFUSED:GRAPHLAW_WASM_PIN_DRIFT new drift — checked-in sha256=#{actual} " <>
            "is neither the pinned #{pinned} nor the allowlisted known drift #{@known_drifted_sha256}"
        )
    end
  end

  defp sha256(bin), do: :crypto.hash(:sha256, bin)
end
