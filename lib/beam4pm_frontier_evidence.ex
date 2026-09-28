defmodule BeamPM.FrontierEvidence do
  @moduledoc """
  Deterministic FrontierEvidence v1 projection for already-produced beam4pm results.

  This module does not invoke Ferroplan, execute a plan, dispatch A2A work, or grant
  downstream authority. It only binds planner/policy/conformance results that were
  produced elsewhere into a content-addressed SELECT-only evidence fragment that a
  downstream BRCE admission court may inspect.
  """

  @schema "frontier-evidence/v1"
  @producer "beam4pm"
  @authority_ceiling "SELECT"

  @spec from_results(term(), term(), term(), keyword()) :: map()
  def from_results(hddl_result, fond_result, conformance_result, opts \\ []) do
    producer_head = Keyword.fetch!(opts, :producer_head)
    standing = Keyword.get(opts, :standing, "CANDIDATE")

    evidence = %{
      hddl: normalize_result(hddl_result),
      fond: normalize_result(fond_result),
      conformance: normalize_result(conformance_result)
    }

    body = %{
      schema: @schema,
      producer: @producer,
      producer_head: producer_head,
      standing: standing,
      authority_ceiling: @authority_ceiling,
      evidence: evidence,
      refused: [
        "external_do",
        "actuation_authority",
        "causal_identification_claim",
        "receipt_standing_escalation"
      ]
    }

    Map.put(body, :artifact_hash, fingerprint(body))
  end

  defp normalize_result({:ok, value}), do: %{status: "ok", value: canonical_term(value)}
  defp normalize_result({:error, reason}), do: %{status: "error", reason: canonical_term(reason)}
  defp normalize_result(other), do: %{status: "observed", value: canonical_term(other)}

  defp fingerprint(term) do
    term
    |> canonical_term()
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> then(&("sha256:" <> &1))
  end

  defp canonical_term(%_{} = struct), do: struct |> Map.from_struct() |> canonical_term()

  defp canonical_term(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), canonical_term(value)} end)
    |> Enum.sort()
  end

  defp canonical_term(list) when is_list(list), do: Enum.map(list, &canonical_term/1)

  defp canonical_term(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.map(&canonical_term/1)

  defp canonical_term(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp canonical_term(other), do: other
end
