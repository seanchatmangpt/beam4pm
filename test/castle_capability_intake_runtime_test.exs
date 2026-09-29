defmodule Beam4pm.CastleCapabilityIntakeRuntimeTest do
  use ExUnit.Case, async: true

  alias Beam4pm.CastleCapabilityIntake

  test "EX4PM donor is queryable but cannot grant dispatch authority" do
    donor = CastleCapabilityIntake.donor()

    assert CastleCapabilityIntake.owner_capability() == "PROCESS_COORDINATION"
    assert CastleCapabilityIntake.authority_ceiling() == :construct
    assert donor.repository == "seanchatmangpt/ex4pm"
    assert donor.sha == "d1ff769ca7763168ff154b1def980dfaec0cb15c"
    assert donor.runtime_placement == :process_kernel_behind_runtime_owner
    refute CastleCapabilityIntake.dispatch_authority?(donor)
  end
end
