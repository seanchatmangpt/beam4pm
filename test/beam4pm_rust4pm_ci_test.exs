defmodule BeamPM.Rust4PMCIQualificationTest do
  @moduledoc """
  Portable CI qualification for the Rust4PM WASM boundary.

  The larger BeamPM.Rust4PMTest deliberately includes one machine-local
  canonical-scale corpus. This court uses only checked-in OCEL fixtures so CI
  and the container build can execute the WASM engine and RF4 differential
  checks on every change instead of treating an absent 29MB corpus as a reason
  to skip the whole engine surface.
  """

  use ExUnit.Case, async: false

  alias BeamPM.Rust4PM

  if not BeamPM.Rust4PM.wasm_built?() do
    @moduletag skip: BeamPM.Rust4PM.wasm_missing_reason()
  end

  @fixture Path.expand("qualification/fixtures/positive-self-authored.ocel.json")
  @rf4 Path.expand("native/rf4-oc-discovery-oracle/target/release/rf4-oc-discovery-oracle")

  setup_all do
    assert File.exists?(@fixture), "checked-in OCEL fixture missing: #{@fixture}"
    assert File.exists?(@rf4), "RF4 oracle missing: #{@rf4}"
    assert {:ok, _pid} = Rust4PM.start()
    :ok
  end

  defp oracle!(request) do
    payload =
      Path.join(System.tmp_dir!(), "beam4pm-rf4-ci-#{System.unique_integer([:positive])}.json")

    File.write!(payload, JSON.encode!(request))
    {raw, status} = System.shell("#{@rf4} < #{payload}")
    File.rm(payload)
    assert status == 0, "RF4 oracle failed with status #{status}: #{raw}"
    JSON.decode!(String.trim_trailing(raw, "\n"))
  end

  test "WASM OCEL JSON/XML and RF4 discovery agree with the native oracle" do
    assert {:ok, %{"ocel_handle" => handle}} = Rust4PM.import_ocel_json(File.read!(@fixture))

    for object_type <- ["Order", "Item"] do
      assert {:ok, %{"edges" => wasm_edges}} =
               Rust4PM.ocel_dfg_of_object_type(handle, object_type)

      %{"edges" => native_edges} =
        oracle!(%{"op" => "oc_dfg_discover", "ocel_path" => @fixture, "ob_type" => object_type})

      assert Enum.map(wasm_edges, &[&1["from"], &1["to"], &1["count"]]) ==
               Enum.map(native_edges, &[&1["source"], &1["target"], &1["frequency"]])

      assert {:ok, %{"variants" => wasm_variants}} =
               Rust4PM.ocel_variants_of_object_type(handle, object_type)

      %{"variants" => native_variants} =
        oracle!(%{
          "op" => "oc_variants_discover",
          "ocel_path" => @fixture,
          "ob_type" => object_type
        })

      assert Enum.map(wasm_variants, &[&1["activities"], &1["count"]]) ==
               Enum.map(native_variants, &[&1["trace"], &1["count"]])
    end

    assert {:ok, stats_before} = Rust4PM.ocel_stats(handle)
    assert {:ok, %{"content_b64" => encoded_xml}} = Rust4PM.ocel_to_xml(handle)
    assert {:ok, %{"ocel_handle" => xml_handle}} =
             encoded_xml |> Base.decode64!() |> Rust4PM.import_ocel_xml()

    assert {:ok, stats_after} = Rust4PM.ocel_stats(xml_handle)
    assert stats_after == stats_before

    assert {:ok, %{"freed" => true}} = Rust4PM.free_ocel(handle)
    assert {:ok, %{"freed" => true}} = Rust4PM.free_ocel(xml_handle)
  end
end
