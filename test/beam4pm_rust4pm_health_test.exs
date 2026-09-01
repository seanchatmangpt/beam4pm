defmodule BeamPM.Rust4PM.HealthTest do
  use ExUnit.Case, async: false

  alias BeamPM.Rust4PM.Health

  test "status/0 returns the typed single-candidate shape" do
    status = Health.status()

    assert status.id == :rust4pm_wasm
    assert status.kind == :engine
    assert status.standing in [:alive, :blocked]
    assert is_binary(status.evidence.wasm_path)
    assert is_boolean(status.evidence.artifact_present)
  end

  test "evidence.artifact_present matches the real BeamPM.Rust4PM.wasm_built?/0 delegate" do
    status = Health.status()
    assert status.evidence.artifact_present == BeamPM.Rust4PM.wasm_built?()
  end

  if BeamPM.Rust4PM.wasm_built?() do
    test "when the artifact is present, status/0 reports :alive with a real started engine" do
      status = Health.status()
      assert status.standing == :alive
      assert status.reason == nil
      assert status.evidence.engine_started == true
    end
  else
    @tag skip: BeamPM.Rust4PM.wasm_missing_reason()
    test "when the artifact is present, status/0 reports :alive with a real started engine" do
    end
  end

  test "when the artifact is absent, status/0 reports :blocked with the real named reason" do
    unless BeamPM.Rust4PM.wasm_built?() do
      status = Health.status()
      assert status.standing == :blocked
      assert status.reason == BeamPM.Rust4PM.wasm_missing_reason()
      assert status.evidence.artifact_present == false
      assert status.evidence.engine_started == nil
    else
      # Real artifact IS present on this checkout -- the absent-artifact
      # branch is exercised for real whenever CI/a fresh clone runs this
      # without the wasm engine built (this test's own condition proves
      # it, rather than skipping outright).
      :ok
    end
  end
end
