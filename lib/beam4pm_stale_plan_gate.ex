# Hand-authored (not ggen-generated). Lane W3 (docs/jira/v26.9.25/_LANES-strategic-loop.md):
# first real enforcer for the generated StalePlanRefusal record semantics.
# Given the preimage hash a plan was admitted against and the preimage hash
# of the world actually observed, refuses stale execution with a typed
# refusal shape (lane map resolution 5) instead of letting drift pass.
defmodule BeamPM.StalePlanGate do
  @moduledoc """
  Stale-plan refusal gate over preimage hashes.

  `check/2` compares the `admitted_preimage_hash` a plan was admitted
  against with the `observed_preimage_hash` of the world actually observed:

    * equal (both well-formed 64-char lowercase hex) -> `{:ok, :fresh}`
    * unequal -> `{:error, {:stale_plan_refusal, %{admitted_preimage_hash:
      admitted, observed_preimage_hash: observed}}}` — the exact refusal
      shape pinned in lane map resolution 5, carrying both hashes as
      refusal evidence (what `BeamPM.Ash.Resources.StalePlanRefusal`
      persists; this gate is the decision, the caller decides to persist).
    * any non-binary, wrong-length, or non-lowercase-hex input ->
      `{:error, {:stale_plan_refusal, :malformed_hash}}` — a malformed hash
      can never be evidence of freshness, so it refuses closed.

  No authority semantics: this gate only refuses or passes; it never
  actuates.
  """

  @hash_format Regex.compile!("^[0-9a-f]{64}$")

  @spec check(term(), term()) ::
          {:ok, :fresh}
          | {:error, {:stale_plan_refusal, :malformed_hash}}
          | {:error,
             {:stale_plan_refusal,
              %{admitted_preimage_hash: String.t(), observed_preimage_hash: String.t()}}}
  def check(admitted_preimage_hash, observed_preimage_hash) do
    cond do
      not well_formed?(admitted_preimage_hash) or not well_formed?(observed_preimage_hash) ->
        {:error, {:stale_plan_refusal, :malformed_hash}}

      admitted_preimage_hash == observed_preimage_hash ->
        {:ok, :fresh}

      true ->
        {:error,
         {:stale_plan_refusal,
          %{
            admitted_preimage_hash: admitted_preimage_hash,
            observed_preimage_hash: observed_preimage_hash
          }}}
    end
  end

  defp well_formed?(hash) when is_binary(hash) do
    Regex.match?(@hash_format, hash)
  end

  defp well_formed?(_other), do: false
end
