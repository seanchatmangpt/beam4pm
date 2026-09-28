defmodule BeamPM.PPCXProductionBoundaryTest do
  use ExUnit.Case, async: true

  alias BeamPM.PPCXProductionBoundary, as: Boundary

  test "beam4pm owns planning and conformance only" do
    assert :ok = Boundary.admit_local(:plan)
    assert :ok = Boundary.admit_local(:conform)

    assert {:error, {:external_authority, :allocate, :bcinr}} =
             Boundary.admit_local(:allocate)

    assert {:error, {:external_authority, :select, :mfw_auto_select}} =
             Boundary.admit_local(:select)

    assert {:error, {:external_authority, :admit, :mfw_admission}} =
             Boundary.admit_local(:admit)
  end

  test "consequential do is always external to beam4pm" do
    assert :mfw_pcp_broker = Boundary.owner(:actuate)

    assert {:error, {:do_authority_external, :mfw_pcp_broker}} =
             Boundary.admit_local(:actuate)

    refute Boundary.topology().ambient_do
  end

  test "topology keeps deterministic kernel transport and verifier distinct" do
    topology = Boundary.topology()

    assert topology.allocation_owner == :bcinr
    assert topology.selection_owner == :mfw_auto_select
    assert topology.admission_owner == :mfw_admission
    assert topology.transport_owner == :rmcp_transport
    assert topology.do_owner == :mfw_pcp_broker
    assert topology.consequence_verifier == :independent_verifier
    assert topology.conformance_owner == :beam4pm
  end
end
