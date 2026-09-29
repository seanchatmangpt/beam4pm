defmodule Beam4pm.CastleCapabilityIntakeTest do
  use ExUnit.Case, async: true

  @path Path.expand("../ontology/castle-capability-intake.ttl", __DIR__)

  test "EX4PM is a kernel behind Beam4PM rather than a second runtime crown" do
    graph = File.read!(@path)

    assert graph =~ "50fdfa20c84205a80c6eb94e916cffbedc4b816e"
    assert graph =~ "seanchatmangpt/ex4pm"
    assert graph =~ "d1ff769ca7763168ff154b1def980dfaec0cb15c"
    assert graph =~ ~s(eco:ownerCapability "PROCESS_COORDINATION")
    assert graph =~ ~s(eco:runtimePlacement "PROCESS_KERNEL_BEHIND_RUNTIME_OWNER")
    assert graph =~ ~s(eco:projectionStanding "CANDIDATE")
    assert graph =~ ~s(eco:authorityCeiling "CONSTRUCT")
    refute graph =~ ~s(eco:authorityCeiling "DO")
    refute graph =~ ~s(eco:runtimePlacement "RUNTIME_CORE")
  end
end
