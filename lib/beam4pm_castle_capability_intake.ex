defmodule Beam4pm.CastleCapabilityIntake do
  @moduledoc """
  Runtime-readable CASTLE capability donor registry for Beam4PM.

  EX4PM is admitted only as a process-execution kernel behind Beam4PM's
  PROCESS_COORDINATION ownership. This module has no actuation path.
  """

  @projection_source "seanchatmangpt/ggen-ecosystem@50fdfa20c84205a80c6eb94e916cffbedc4b816e"
  @owner_capability "PROCESS_COORDINATION"
  @authority_ceiling :construct

  @ex4pm %{
    repository: "seanchatmangpt/ex4pm",
    sha: "d1ff769ca7763168ff154b1def980dfaec0cb15c",
    capability: :process_execution_kernel,
    disposition: :wrap,
    runtime_placement: :process_kernel_behind_runtime_owner
  }

  @spec projection_source() :: String.t()
  def projection_source, do: @projection_source

  @spec owner_capability() :: String.t()
  def owner_capability, do: @owner_capability

  @spec authority_ceiling() :: :construct
  def authority_ceiling, do: @authority_ceiling

  @spec donor() :: map()
  def donor, do: @ex4pm

  @spec dispatch_authority?(term()) :: false
  def dispatch_authority?(_), do: false
end
