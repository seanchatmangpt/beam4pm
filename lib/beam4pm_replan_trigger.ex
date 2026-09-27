# Hand-authored (not ggen-generated). Lane W3 (docs/jira/v26.9.25/_LANES-strategic-loop.md):
# first real producer for the generated DynamicReplanTrigger /
# EventTriggeredPlanning Ash resources. Consumes a real
# `BeamPM.PowlConformance.check_conformance/3` result — the same result map
# `BeamPM.DeviationAdmission.admit_deviation/4` consumes — and turns a
# `conforms: false` outcome into a persisted replan trigger + telemetry
# signal, instead of letting the deviation terminate in an assertion.
defmodule BeamPM.ReplanTrigger do
  @moduledoc """
  Conformance deviation -> dynamic replan trigger.

  `from_conformance/2` is the producer the generated
  `BeamPM.Ash.Resources.DynamicReplanTrigger` resource never had: given a real
  `BeamPM.PowlConformance.check_conformance/3` result (the same map
  `BeamPM.DeviationAdmission.admit_deviation/4` reads), it persists one
  trigger row when the trace does NOT conform, emits
  `[:beam4pm, :ferroplan, :replan_triggered]` telemetry, and returns the
  created record. A conforming trace is a `{:ok, :conformant}` no-op.

  `episode/2` is the first minter of `EventTriggeredPlanning.episode_id`
  (nothing in the repo mints it today): it mints a bounded planning-episode
  identifier and persists one `BeamPM.Ash.Resources.EventTriggeredPlanning`
  row binding the admitted world event to the observed world-state hash.

  Seams (pinned in docs/jira/v26.9.25/_LANES-strategic-loop.md):

    * trigger_hash formula: `sha256(deviation_individual_name <>
      observed_at_iso8601)` — full lowercase hex, no truncation.
    * telemetry event: `[:beam4pm, :ferroplan, :replan_triggered]`, metadata
      `%{trigger_hash: hex, reason: :deviation}`.

  This module is deliberately a BESIDE-builder, not an editor, of
  `BeamPM.DeviationAdmission` (that file is another lane's seam boundary):
  when the caller already ran `admit_deviation/4`, pass its returned
  `process_deviation_*` individual name as the
  `:deviation_individual_name` opt; otherwise the name is derived with the
  same formula `admit_deviation/4` uses (first deviation move +
  reference/candidate trace ids + timestamp), so the trigger hash chains to
  the individual the ontology admission produced.
  """

  @telemetry_event [:beam4pm, :ferroplan, :replan_triggered]

  @typedoc "The subset of BeamPM.PowlConformance.conformance_result/0 consumed here."
  @type conformance_result :: %{
          optional(any()) => any(),
          conforms: boolean(),
          deviations: [[String.t()]]
        }

  @doc """
  Pinned trigger_hash formula (lane map resolution 3):
  `sha256(deviation_individual_name <> observed_at_iso8601)` as full
  lowercase hex.
  """
  @spec trigger_hash(String.t(), String.t()) :: String.t()
  def trigger_hash(deviation_individual_name, observed_at_iso8601)
      when is_binary(deviation_individual_name) and is_binary(observed_at_iso8601) do
    :crypto.hash(:sha256, deviation_individual_name <> observed_at_iso8601)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Turns a real `BeamPM.PowlConformance.check_conformance/3` result into a
  persisted `DynamicReplanTrigger`.

  Options:

    * `:plan_id` (required) — the plan whose assumption the deviation
      invalidates; stored as `DynamicReplanTrigger.plan_id`.
    * `:event_id` (required) — caller-supplied identifier for the observed
      deviation event; stored as `DynamicReplanTrigger.event_id`.
    * `:deviation_individual_name` (optional) — the `process_deviation_*`
      individual name returned by
      `BeamPM.DeviationAdmission.admit_deviation/4`. Wins when present.
    * `:reference_trace_id` / `:candidate_trace_id` (required together when
      no individual name is given) — used to derive the individual name with
      the same formula `admit_deviation/4` uses.
    * `:observed_at` (optional) — ISO8601 UTC timestamp string feeding the
      hash; defaults to `DateTime.utc_now/0` as ISO8601.

  Returns:

    * `{:ok, :conformant}` — the trace conformed; nothing to trigger.
    * `{:ok, trigger}` — the created
      `BeamPM.Ash.Resources.DynamicReplanTrigger` record; telemetry emitted.
    * `{:error, :no_deviation}` — `conforms: false` asserted with an empty
      deviations list (contract violation; mirrors `admit_deviation/4`).
    * `{:error, {:missing_opt, key}}` — a required opt is absent.
    * `{:error, :malformed_conformance_result}` — unrecognized result shape.
    * `{:error, reason}` — Ash create failure.
  """
  @spec from_conformance(conformance_result(), keyword()) ::
          {:ok, :conformant}
          | {:ok, BeamPM.Ash.Resources.DynamicReplanTrigger.t()}
          | {:error, term()}
  def from_conformance(result, opts) when is_list(opts) do
    case result do
      %{conforms: true} ->
        {:ok, :conformant}

      %{conforms: false, deviations: []} ->
        {:error, :no_deviation}

      %{conforms: false, deviations: [[log_side, model_side] | _]} ->
        build_trigger(opts, "#{log_side}/#{model_side}")

      # Non-map results and unrecognized shapes both refuse typed.
      _ ->
        {:error, :malformed_conformance_result}
    end
  end

  @doc """
  Mints a bounded planning-episode id and persists one
  `EventTriggeredPlanning` row binding `event_id` (the admitted world event)
  to `world_state_hash` (the observed world state that starts the episode).

  Episode id minting (stated per lane contract): `Uniq.UUID.uuid7/0` when
  the `:uniq` package is loadable in the dependency tree (UUIDv7,
  time-ordered), else 16 `:crypto` strong bytes as lowercase hex. Returns
  `{:ok, record}` or `{:error, reason}`.
  """
  @spec episode(String.t(), String.t()) ::
          {:ok, BeamPM.Ash.Resources.EventTriggeredPlanning.t()} | {:error, term()}
  def episode(event_id, world_state_hash)
      when is_binary(event_id) and is_binary(world_state_hash) do
    create_event_triggered_planning(%{
      event_id: event_id,
      world_state_hash: world_state_hash,
      episode_id: mint_episode_id()
    })
  end

  @doc """
  The episode-id minter proper: UUIDv7 via `Uniq.UUID` when loadable, else
  `:crypto.strong_rand_bytes(16)` lowercase hex.
  """
  @spec mint_episode_id() :: String.t()
  def mint_episode_id do
    if Code.ensure_loaded?(Uniq.UUID) and function_exported?(Uniq.UUID, :uuid7, 0) do
      apply(Uniq.UUID, :uuid7, [])
    else
      :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    end
  end

  ## Internals

  defp build_trigger(opts, deviating_move) do
    with {:ok, plan_id} <- required_opt(opts, :plan_id),
         {:ok, event_id} <- required_opt(opts, :event_id),
         {:ok, observed_at} <- observed_at_opt(opts),
         {:ok, individual_name} <- deviation_individual_name(opts, observed_at, deviating_move) do
      attrs = %{
        plan_id: plan_id,
        event_id: event_id,
        trigger_hash: trigger_hash(individual_name, observed_at)
      }

      with {:ok, trigger} <- create_dynamic_replan_trigger(attrs) do
        :telemetry.execute(@telemetry_event, %{}, %{
          trigger_hash: attrs.trigger_hash,
          reason: :deviation
        })

        {:ok, trigger}
      end
    end
  end

  defp required_opt(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} when is_binary(value) and byte_size(value) > 0 -> {:ok, value}
      {:ok, _other} -> {:error, {:invalid_opt, key}}
      :error -> {:error, {:missing_opt, key}}
    end
  end

  defp observed_at_opt(opts) do
    case Keyword.fetch(opts, :observed_at) do
      {:ok, value} when is_binary(value) and byte_size(value) > 0 -> {:ok, value}
      {:ok, _other} -> {:error, {:invalid_opt, :observed_at}}
      :error -> {:ok, DateTime.utc_now() |> DateTime.to_iso8601()}
    end
  end

  defp deviation_individual_name(opts, observed_at, deviating_move) do
    case Keyword.fetch(opts, :deviation_individual_name) do
      {:ok, name} when is_binary(name) and byte_size(name) > 0 ->
        {:ok, name}

      {:ok, _other} ->
        {:error, {:invalid_opt, :deviation_individual_name}}

      :error ->
        with {:ok, reference_trace_id} <- required_opt(opts, :reference_trace_id),
             {:ok, candidate_trace_id} <- required_opt(opts, :candidate_trace_id) do
          # Same derivation formula as
          # BeamPM.DeviationAdmission.admit_deviation/4 (lib/beam4pm_deviation_admission.ex:74-80):
          # "process_deviation_" <> first-16-hex-of
          # sha256(reference <> candidate <> "<log>/<model>" move <> timestamp).
          # With this call's observed_at, the derived name chains to the
          # ontology individual for the identical
          # (reference, candidate, first-move, timestamp) tuple.
          {:ok,
           derived_name(reference_trace_id, candidate_trace_id, deviating_move, observed_at)}
        end
    end
  end

  defp derived_name(reference_trace_id, candidate_trace_id, deviating_move, observed_at) do
    "process_deviation_" <>
      (:crypto.hash(:sha256, reference_trace_id <> candidate_trace_id <> deviating_move <> observed_at)
       |> Base.encode16(case: :lower)
       |> binary_part(0, 16))
  end

  defp create_dynamic_replan_trigger(attrs) do
    BeamPM.Ash.Resources.DynamicReplanTrigger
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create()
    |> case do
      {:ok, trigger} -> {:ok, trigger}
      {:error, error} -> {:error, {:create_failed, error}}
    end
  end

  defp create_event_triggered_planning(attrs) do
    BeamPM.Ash.Resources.EventTriggeredPlanning
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create()
    |> case do
      {:ok, record} -> {:ok, record}
      {:error, error} -> {:error, {:create_failed, error}}
    end
  end
end
