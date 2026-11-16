defmodule BeamPM.RepopTest do
  use ExUnit.Case, async: true

  alias BeamPM.Repop

  @frame_size 64

  # Real engine, no mocks: every test below executes the pinned
  # priv/repop/repop_kernel_wasm.wasm artifact inside wasmex and asserts the
  # LANDED artifact's actual typed behaviour (courts kill, not pre-think).

  setup do
    {:ok, session} = Repop.open()
    %{session: session}
  end

  describe "compile-time artifact pin" do
    test "pinned sha and size match the artifact on disk" do
      assert %File.Stat{size: size} = File.stat!(Repop.artifact_path())
      assert size == Repop.artifact_bytes()
      assert Repop.artifact_bytes() == 901

      on_disk = Base.encode16(:crypto.hash(:sha256, File.read!(Repop.artifact_path())), case: :lower)
      assert on_disk == Repop.artifact_sha()
      assert Repop.artifact_sha() == "3cc67f94d67927d3bed1c995a99538d9c0facb98a211ec4e911a134c21370e6b"
    end

    test "MANIFEST.json agrees with the pin" do
      manifest =
        Repop.artifact_path()
        |> Path.dirname()
        |> Path.join("MANIFEST.json")
        |> File.read!()
        |> JSON.decode!()

      assert manifest["sha256"] == Repop.artifact_sha()
      assert manifest["byte_size"] == Repop.artifact_bytes()
      assert manifest["abi_version"] == 1
      assert manifest["version"] == "0.1.0"
      assert "repop_solve" in manifest["exports"]
      assert manifest["imports"] == []
    end
  end

  describe "open/0" do
    test "compiles and instantiates with EMPTY imports" do
      {:ok, session} = Repop.open()
      assert %Repop.Session{} = session
    end
  end

  describe "identity exports" do
    test "abi_version/1 returns the real kernel's ABI version 1", %{session: session} do
      assert {:ok, 1} = Repop.abi_version(session)
    end

    test "version/1 decodes the PACKED u32 to 0.1.0", %{session: session} do
      assert {:ok, "0.1.0"} = Repop.version(session)
    end

    test "decode_packed_version/1 splits major.minor.patch" do
      assert Repop.decode_packed_version(256) == "0.1.0"
      assert Repop.decode_packed_version(0x010203) == "1.2.3"
    end
  end

  describe "solve/2 -- typed refusal paths of the LANDED artifact" do
    test "a zero frame fails real repop-abi decode -> :err_bad_intent", %{session: session} do
      zero_frame = <<0::size(8 * @frame_size)>>
      assert {:ok, :err_bad_intent} = Repop.solve(session, zero_frame)
    end

    test "a garbage frame fails decode -> :err_bad_intent (typed, never a trap)", %{session: session} do
      garbage = :crypto.strong_rand_bytes(@frame_size)
      assert {:ok, :err_bad_intent} = Repop.solve(session, garbage)
    end

    test "a VALID frame decodes -> :err_unwired (P2 solver not yet wired -- honest)", %{session: session} do
      valid_frame = valid_intent_frame()
      assert {:ok, :err_unwired} = Repop.solve(session, valid_frame)
    end

    test "wrong frame size is refused host-side before any wasm call", %{session: session} do
      assert {:error, {:bad_frame_size, 63}} = Repop.solve(session, <<0::size(8 * 63)>>)
      assert {:error, {:bad_frame_size, 65}} = Repop.solve(session, <<0::size(8 * 65)>>)
      assert {:error, {:bad_frame_size, 0}} = Repop.solve(session, <<>>)
    end

    test "solve does not accumulate scratch across calls (per-call reset)", %{session: session} do
      zero_frame = <<0::size(8 * @frame_size)>>
      {:ok, [before]} = call_export(session, "repop_scratch_remaining", [])

      for _ <- 1..5, do: Repop.solve(session, zero_frame)

      {:ok, [after_]} = call_export(session, "repop_scratch_remaining", [])
      assert after_ == before
    end
  end

  describe "CAS wrappers -- P3 placeholder passthrough" do
    test "cas_commit/4 returns :err_unwired for a well-formed 64B value", %{session: session} do
      assert {:ok, :err_unwired} = Repop.cas_commit(session, 1, 0, <<0::size(8 * @frame_size)>>)
    end

    test "cas_read/2 returns :err_unwired (registry not wired)", %{session: session} do
      assert {:ok, :err_unwired} = Repop.cas_read(session, 1)
    end

    test "cas_commit/4 refuses a wrong-size value host-side", %{session: session} do
      assert {:error, {:bad_frame_size, 8}} = Repop.cas_commit(session, 1, 0, <<0::size(64)>>)
    end
  end

  describe "status_name/1" do
    test "maps the pinned ABI status vocabulary" do
      assert Repop.status_name(0) == :ok
      assert Repop.status_name(1) == :err_bad_intent
      assert Repop.status_name(7) == :err_unwired
      assert Repop.status_name(99) == {:unknown_status, 99}
    end
  end

  # ---------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------

  defp call_export(%Repop.Session{} = session, name, args) do
    Wasmex.Utils.native_request(fn from ->
      Wasmex.Instance.call_exported_function(session.store, session.instance, name, args, from, 5_000)
    end)
  end

  # Build a frame the real repop-abi codec accepts. Decode law (frame.rs):
  # magic 0x4946 LE at 0..2, layout version 1 LE at 2..4, FNV-1a32 digest of
  # bytes [0,60) stored LE at 60..64, reserved word 58..60 == 0. Bytes
  # 4..58 are unconstrained by decode (validate's finite-f64 law is not part
  # of the placeholder's decode call), so an otherwise-zero frame decodes.
  @fnv1a32_offset_basis 2_166_136_261
  @fnv1a32_prime 16_777_619

  defp valid_intent_frame do
    body =
      <<0x4946::16-unsigned-little, 1::16-unsigned-little, 0::size(8 * 56)>>

    <<body::binary, fnv1a32(body)::32-unsigned-little>>
  end

  defp fnv1a32(bytes), do: fnv1a32_loop(bytes, @fnv1a32_offset_basis)

  defp fnv1a32_loop(<<b, rest::binary>>, acc) do
    import Bitwise, only: [bxor: 2, band: 2]
    fnv1a32_loop(rest, band(bxor(acc, b) * @fnv1a32_prime, 0xFFFF_FFFF))
  end

  defp fnv1a32_loop(<<>>, acc), do: acc
end
