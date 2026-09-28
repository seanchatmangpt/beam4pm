defmodule BeamPM.FerroplanBridge.IdentityWaveTest do
  use ExUnit.Case, async: true
  alias BeamPM.FerroplanBridge.{AuthorityFence, ExactSubject, Standing}
  test "exact identity and authority remain separate from standing" do
    assert {:ok, s} = ExactSubject.bind("o/r", String.duplicate("a", 40), "t")
    assert ExactSubject.same?(s, s)
    assert {:error, _} = AuthorityFence.require(:observe, :construct)
    refute Standing.may_execute?(:candidate)
  end
end
