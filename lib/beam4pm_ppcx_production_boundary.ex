defmodule BeamPM.PPCXProductionBoundary do
  @moduledoc """
  Production ownership boundary for the PPCX planning/process-intelligence loop.

  `beam4pm` owns planning and conformance/control-plane intelligence. It does not
  acquire CMCA allocation authority, MFW selection/admission authority, or
  consequential DO authority by hosting the planner or process runtime.

  The module is intentionally declarative and side-effect free. It is used to
  reject local authority widening before any transport or adapter layer is added.
  """

  @typedoc "Production transition in the PPCX closure."
  @type transition ::
          :plan
          | :allocate
          | :select
          | :admit
          | :transport
          | :actuate
          | :verify_consequence
          | :conform

  @typedoc "Canonical production owner."
  @type owner ::
          :beam4pm
          | :bcinr
          | :mfw_auto_select
          | :mfw_admission
          | :rmcp_transport
          | :mfw_pcp_broker
          | :independent_verifier

  @typedoc "Typed refusal for an attempted local authority widening."
  @type refusal ::
          {:external_authority, transition(), owner()}
          | {:do_authority_external, :mfw_pcp_broker}

  @spec schema() :: String.t()
  def schema, do: "chatman.ppcx.beam4pm-production-boundary/v1"

  @spec owner(transition()) :: owner()
  def owner(:plan), do: :beam4pm
  def owner(:allocate), do: :bcinr
  def owner(:select), do: :mfw_auto_select
  def owner(:admit), do: :mfw_admission
  def owner(:transport), do: :rmcp_transport
  def owner(:actuate), do: :mfw_pcp_broker
  def owner(:verify_consequence), do: :independent_verifier
  def owner(:conform), do: :beam4pm

  @doc """
  Admit only transitions whose production authority belongs to `beam4pm`.

  This is a classification fence, not a workflow runner. `:ok` does not imply
  execution, standing, or a receipt; it means only that the transition belongs
  to the control-plane role.
  """
  @spec admit_local(transition()) :: :ok | {:error, refusal()}
  def admit_local(:plan), do: :ok
  def admit_local(:conform), do: :ok

  def admit_local(:actuate) do
    {:error, {:do_authority_external, :mfw_pcp_broker}}
  end

  def admit_local(transition) do
    {:error, {:external_authority, transition, owner(transition)}}
  end

  @doc """
  Canonical immutable production topology used by receipts, diagnostics, and
  cross-repository contract tests.
  """
  @spec topology() :: map()
  def topology do
    %{
      schema: schema(),
      planning_owner: :beam4pm,
      allocation_owner: :bcinr,
      selection_owner: :mfw_auto_select,
      admission_owner: :mfw_admission,
      transport_owner: :rmcp_transport,
      do_owner: :mfw_pcp_broker,
      consequence_verifier: :independent_verifier,
      conformance_owner: :beam4pm,
      ambient_do: false
    }
  end
end
