defmodule BeamPM.Gall.ProcessIntelligence do
  @moduledoc """
  GALL-024..028 OBSERVE/ANALYZE courts.

  This module manufactures object-centric evidence, deltas, attribution, and
  multi-clock candidates. It has no CommandBus/authority dependency and cannot DO.
  """

  @delta_types ~w(missing_required_event unexpected_event ordering_violation cardinality_violation wrong_object_or_qualifier identity_mismatch)
  @horizons ~w(FAST MEDIUM SLOW)

  def observe(source, events, objects, relations) when is_map(source) do
    with :ok <- required(source, ~w(adapter_id adapter_version raw_evidence_digest)a),
         :ok <- validate_relations(relations) do
      evidence = %{
        schema: "beam4pm.gall.ocel-observation/v26.9.18",
        checkpoint: "GALL-024",
        source: source,
        events: canonical(events),
        objects: canonical(objects),
        relations: canonical(relations),
        authority: "none"
      }
      {:ok, Map.put(evidence, :digest, digest(evidence))}
    end
  end

  def compare(normative, observed, deltas) when is_map(normative) and is_map(observed) do
    with :ok <- validate_deltas(deltas) do
      result = %{
        schema: "beam4pm.gall.conformance/v26.9.18",
        checkpoints: ["GALL-025", "GALL-026"],
        normative_digest: digest(normative),
        observed_digest: digest(observed),
        deltas: canonical(deltas),
        normative_immutable: true,
        evidence_class: "candidate_finding",
        authority: "none"
      }
      {:ok, Map.put(result, :digest, digest(result))}
    end
  end

  def attribute(total, components, unit, tolerance \\ 0.0)
      when is_number(total) and is_list(components) and is_binary(unit) do
    with :ok <- same_units(components, unit) do
      attributed = Enum.reduce(components, 0.0, fn c, acc -> acc + c.value end)
      residual = total - attributed
      if residual < -tolerance do
        {:error, {:refused_attribution, :over_attributed}}
      else
        result = %{
          schema: "beam4pm.gall.attribution/v26.9.18",
          checkpoint: "GALL-027",
          unit: unit,
          total: total,
          components: canonical(components),
          unattributed_residual: residual,
          tolerance: tolerance,
          authority: "none"
        }
        {:ok, Map.put(result, :digest, digest(result))}
      end
    end
  end

  def horizon(finding, config, qualified_count) when is_map(config) do
    thresholds = Map.fetch!(config, :thresholds)
    selected =
      @horizons
      |> Enum.filter(fn h -> qualified_count >= Map.fetch!(thresholds, h) end)

    result = %{
      schema: "beam4pm.gall.multi-clock/v26.9.18",
      checkpoint: "GALL-028",
      finding_digest: digest(finding),
      config_digest: digest(config),
      qualified_count: qualified_count,
      eligible_horizons: selected,
      candidates: Enum.map(selected, &candidate(&1, finding)),
      authority: "none"
    }
    {:ok, Map.put(result, :digest, digest(result))}
  end

  defp candidate("FAST", finding), do: %{horizon: "FAST", class: "bounded_intervention", finding_digest: digest(finding)}
  defp candidate("MEDIUM", finding), do: %{horizon: "MEDIUM", class: "parameter_adaptation", finding_digest: digest(finding)}
  defp candidate("SLOW", finding), do: %{horizon: "SLOW", class: "process_redesign", finding_digest: digest(finding)}

  defp validate_relations(relations) do
    if Enum.all?(relations, fn r ->
         is_binary(r[:event_id]) and is_binary(r[:object_id]) and is_binary(r[:qualifier])
       end), do: :ok, else: {:error, {:partial_evidence, :unattributed_relation}}
  end

  defp validate_deltas(deltas) do
    case Enum.find(deltas, fn d -> to_string(d[:type]) not in @delta_types end) do
      nil -> :ok
      bad -> {:error, {:unsupported_delta, bad[:type]}}
    end
  end

  defp same_units(components, unit) do
    if Enum.all?(components, &(&1.unit == unit)),
      do: :ok,
      else: {:error, {:refused_attribution, :unit_mismatch}}
  end

  defp required(map, keys) do
    case Enum.find(keys, &(Map.get(map, &1) in [nil, ""])) do
      nil -> :ok
      key -> {:error, {:partial_evidence, key}}
    end
  end

  defp digest(value) do
    "sha256:" <>
      (:crypto.hash(:sha256, :erlang.term_to_binary(canonical(value), [:deterministic]))
       |> Base.encode16(case: :lower))
  end

  defp canonical(value) when is_map(value) do
    value |> Enum.map(fn {k, v} -> {to_string(k), canonical(v)} end) |> Enum.sort()
  end
  defp canonical(value) when is_list(value), do: value |> Enum.map(&canonical/1) |> Enum.sort()
  defp canonical(value), do: value

  def self_test do
    source = %{adapter_id: "otel", adapter_version: "1", raw_evidence_digest: "sha256:raw"}
    events = [%{id: "e1", activity: "do"}]
    objects = [%{id: "cmd-1", type: "command"}, %{id: "cap-1", type: "capability"}]
    relations = [
      %{event_id: "e1", object_id: "cmd-1", qualifier: "command"},
      %{event_id: "e1", object_id: "cap-1", qualifier: "capability"}
    ]
    {:ok, observed} = observe(source, events, objects, relations)
    true = length(observed.relations) == 2

    normative = %{rule: "receipt_precedes_do"}
    deltas = [%{type: "ordering_violation", rule: "receipt_precedes_do", event_id: "e1"}]
    {:ok, compared} = compare(normative, observed, deltas)
    true = compared.normative_digest == digest(normative)
    true = length(compared.deltas) == 1

    {:ok, attribution} =
      attribute(10.0, [%{unit: "reductions", value: 6.0}, %{unit: "reductions", value: 3.0}], "reductions")
    true = attribution.unattributed_residual == 1.0
    {:error, {:refused_attribution, :unit_mismatch}} =
      attribute(10.0, [%{unit: "joule", value: 1.0}], "reductions")

    config = %{thresholds: %{"FAST" => 1, "MEDIUM" => 3, "SLOW" => 10}}
    {:ok, one} = horizon(compared, config, 1)
    true = one.eligible_horizons == ["FAST"]
    {:ok, ten} = horizon(compared, config, 10)
    true = ten.eligible_horizons == ["FAST", "MEDIUM", "SLOW"]
    :ok
  end
end

case System.argv() do
  ["--self-test"] ->
    :ok = BeamPM.Gall.ProcessIntelligence.self_test()
    IO.puts("GALL-024..028 self-test: PASS")
  _ ->
    IO.puts(:stderr, "usage: mix run scripts/gall_process_intelligence_024_028.exs -- --self-test")
    System.halt(2)
end
