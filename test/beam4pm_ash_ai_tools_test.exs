defmodule BeamPM.AshAiToolsTest do
  @moduledoc """
  Real introspection coverage for the two read-only AshAi tools declared on
  BeamPM.Ash.Domain (via beam4pm_ash.ex.eex's `tools do` block) --
  transplanted from xaas's lib/xaas/operations.ex pattern. Proves they are
  actually registered, target the intended resource/action, and are
  read-only (no write tools declared).
  """
  use ExUnit.Case, async: true

  test "read_ocel_events and read_conformance_results are registered, targeting :read" do
    tools = AshAi.Info.tools(BeamPM.Ash.Domain)

    assert %{resource: BeamPM.Ash.Resources.OcelEvent, action: :read} =
             Enum.find(tools, &(&1.name == :read_ocel_events))

    assert %{resource: BeamPM.Ash.Resources.ConformanceResult, action: :read} =
             Enum.find(tools, &(&1.name == :read_conformance_results))
  end

  test "exactly two tools are declared, and both are read-only" do
    tools = AshAi.Info.tools(BeamPM.Ash.Domain)
    tool_names = Enum.map(tools, & &1.name) |> Enum.sort()

    assert tool_names == [:read_conformance_results, :read_ocel_events]
    assert Enum.all?(tools, &(&1.action == :read))
  end

  test "each tool carries a real, non-empty description" do
    for tool <- AshAi.Info.tools(BeamPM.Ash.Domain) do
      assert is_binary(tool.description)
      assert String.length(tool.description) > 0
    end
  end
end
