defmodule BeamPM.DigestTest do
  use ExUnit.Case, async: false

  # async: false — the seam config is application env, mutated per test.

  describe "default" do
    test "SHA256 default is byte-identical to the former hardcoded call" do
      for input <- ["", "abc", "powl-op", <<0, 1, 2, 255>>] do
        assert BeamPM.Digest.hash(input) == :crypto.hash(:sha256, input)
      end
    end

    test "iodata input is flattened like the former call sites" do
      assert BeamPM.Digest.hash(["a", ?b, "c"]) == :crypto.hash(:sha256, "abc")
    end

    test "hex/1 is lowercase" do
      assert BeamPM.Digest.hex(BeamPM.Digest.hash("abc")) ==
               Base.encode16(:crypto.hash(:sha256, "abc"), case: :lower)
    end
  end

  describe "seam dispatch" do
    test "a configured module receives the input and its output is returned" do
      :ok = Application.put_env(:beam4pm, :digest_module, __MODULE__.MarkedDouble)

      assert BeamPM.Digest.hash("dispatched") == :crypto.hash(:sha256, "B3" <> "dispatched")

      # Dispatch proof is at the seam level; the converted call site's
      # byte-identical default is proven by beam4pm_powl_edges_test.exs.
    after
      Application.delete_env(:beam4pm, :digest_module)
    end

    test "deleting the env restores the byte-identical default" do
      :ok = Application.put_env(:beam4pm, :digest_module, __MODULE__.MarkedDouble)
      Application.delete_env(:beam4pm, :digest_module)

      assert BeamPM.Digest.hash("abc") == :crypto.hash(:sha256, "abc")
    end
  end

  defmodule MarkedDouble do
    @moduledoc """
    Test double proving seam dispatch only — NOT blake3. It is
    `:crypto.hash(:sha256, "B3" <> data)`, a trivial marked hasher; the real
    blake3 module arrives with the NIF decision (UNVERIFIED, Y14).
    """
    @behaviour BeamPM.Digest

    @impl true
    def hash(data), do: :crypto.hash(:sha256, "B3" <> IO.iodata_to_binary(data))
  end
end
