defmodule BeamPM.ContractsTest do
  use ExUnit.Case, async: true

  alias BeamPM.Contracts

  test "artifacts/0 names the real three files this manifest hashes" do
    assert Contracts.artifacts() == %{
             ontology: "ontology.ttl",
             types_schema: "schema/beam4pm_types.schema.json",
             ai_contracts_schema: "schema/beam4pm_ai_contracts.schema.json"
           }
  end

  test "manifest/0 hashes the exact real bytes on disk right now" do
    m = Contracts.manifest()

    expected =
      "ontology.ttl"
      |> File.read!()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    assert m.artifacts.ontology.sha256 == expected
    assert m.artifacts.ontology.path == "ontology.ttl"
  end

  test "manifest/0's contract_hash is a real, deterministic function of the three artifact hashes" do
    m1 = Contracts.manifest()
    m2 = Contracts.manifest()

    assert m1.contract_hash == m2.contract_hash
    assert is_binary(m1.contract_hash)
    assert String.length(m1.contract_hash) == 64

    combined = Enum.map_join(Enum.sort_by(m1.artifacts, fn {id, _} -> id end), fn {_id, %{sha256: sha}} -> sha end)
    expected_contract_hash = combined |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)

    assert m1.contract_hash == expected_contract_hash
  end

  test "manifest/0 carries the real beam4pm application version" do
    m = Contracts.manifest()
    assert m.version == to_string(Application.spec(:beam4pm, :vsn))
  end

  test "every hashed artifact actually exists on disk (no fabricated digest for a missing file)" do
    m = Contracts.manifest()

    Enum.each(m.artifacts, fn {_id, %{path: path}} ->
      assert File.exists?(path), "expected admitted artifact #{path} to exist on disk"
    end)
  end
end
