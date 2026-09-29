defmodule BeamPM.SA2A.ReplanConsumer do
  @moduledoc """
  Adapter from Beam4PM's exact runtime subject into the canonical SA2A
  replanning thin waist. Beam4PM keeps observation/planner mechanisms;
  AshA2A owns provider failure exclusion, bounded attempts and replay identity.
  """

  alias AshA2A.Replan.{Loop, ProviderRegistry}
  alias BeamPM.FerroplanBridge.ExecutionEnvelope

  @spec run(ExecutionEnvelope.t() | map(), [map()], atom(), non_neg_integer(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def run(%ExecutionEnvelope{} = envelope, edges, decision, handle, inputs, opts \\ []) do
    formalism = Keyword.get(opts, :formalism, formalism(decision, envelope.capability))
    providers = providers(edges, formalism, opts)

    request =
      inputs
      |> Map.put(:formalism, formalism)
      |> Map.put(:decision, decision)
      |> Map.put(:handle, handle)
      |> Map.put(:capability, envelope.capability)
      |> Map.put(:evidence, envelope.evidence)
      |> Map.put(:epoch, envelope.epoch)

    Loop.run(
      envelope.subject,
      request,
      providers,
      Keyword.put(opts, :max_attempts, Keyword.get(opts, :max_attempts, 3))
    )
  end

  def providers(edges, formalism, opts) do
    case Keyword.get(opts, :sa2a_providers) do
      providers when is_list(providers) ->
        providers

      nil ->
        allowed = edges |> Enum.map(&provider_id(Map.get(&1, :provider))) |> MapSet.new()

        ProviderRegistry.for(formalism)
        |> Enum.filter(fn {id, _module} -> MapSet.member?(allowed, id) end)
    end
  end

  def provider_id(id) when id in [:beam4pm, :ferroplan, :ash_pplan], do: id
  def provider_id("beam4pm"), do: :beam4pm
  def provider_id("ferroplan"), do: :ferroplan
  def provider_id("ash_pplan"), do: :ash_pplan
  def provider_id(other), do: other

  defp formalism(:hddl_replan, _capability), do: :hddl
  defp formalism(:follow_policy, _capability), do: :fond
  defp formalism(_decision, capability) when capability in [:hddl, :fond, :powl, :pddl], do: capability
  defp formalism(_decision, "hddl"), do: :hddl
  defp formalism(_decision, "fond"), do: :fond
  defp formalism(_decision, "powl"), do: :powl
  defp formalism(_decision, "pddl"), do: :pddl
  defp formalism(_decision, _capability), do: :hddl
end
