defmodule BeamPM.FerroplanBridge.ProviderAdapter do
  alias BeamPM.ReplanRouter

  def invoke(provider, decision, handle, inputs, opts) do
    providers = Keyword.get(opts, :providers, %{})
    call_opts = Keyword.delete(opts, :providers)

    with {:ok, module} <- resolve(provider, providers) do
      module.execute(decision, handle, inputs, call_opts)
      |> normalize(provider)
    end
  rescue
    error ->
      {:error,
       %{
         provider: provider,
         reason: {:exception, error.__struct__, Exception.message(error)}
       }}
  catch
    kind, reason ->
      {:error, %{provider: provider, reason: {kind, reason}}}
  end

  def resolve(provider, providers) when is_map(providers) do
    case Map.get(providers, provider) do
      module when is_atom(module) -> {:ok, module}
      nil -> resolve_builtin(provider)
      other -> {:error, %{provider: provider, reason: {:invalid_provider_module, other}}}
    end
  end

  def normalize({:ok, value}, provider),
    do: {:ok, %{provider: provider, value: value}}

  def normalize({:recompile_required, evidence}, provider),
    do: {:ok, %{provider: provider, value: %{outcome: :recompile_required, evidence: evidence}}}

  def normalize({:error, reason}, provider),
    do: {:error, %{provider: provider, reason: reason}}

  def normalize(other, provider),
    do: {:error, %{provider: provider, reason: {:invalid_result, other}}}

  defp resolve_builtin(provider) when provider in [:ferroplan, "ferroplan"],
    do: {:ok, ReplanRouter}

  defp resolve_builtin(provider) when is_atom(provider) do
    if function_exported?(provider, :execute, 4),
      do: {:ok, provider},
      else: {:error, %{provider: provider, reason: :unsupported_provider}}
  end

  defp resolve_builtin(provider),
    do: {:error, %{provider: provider, reason: :unsupported_provider}}
end
