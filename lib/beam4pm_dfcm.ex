defmodule BeamPM.Dfcm do
  @moduledoc """
  Pure Design for Combinatorial Maximalism planning crown.

  DfCM preserves admitted alternatives, applies explicit fences, records every
  exclusion with a deterministic receipt and falsifier, and returns either a
  decision-relevant observation request or a SELECT candidate. It composes the
  WS2 FOND/HDDL contracts and deliberately has no DO surface.
  """

  @type observation_outcome :: :positive | :negative | :inconclusive
  @type option :: map()
  @type problem :: %{
          required(:options) => [option()],
          optional(:observations) => map(),
          optional(:fences) => [map()]
        }

  @phase_order [
    :preserve,
    :fence,
    :calculus,
    :exclusions,
    :falsifier,
    :extension,
    :construct_contingent_policy,
    :select
  ]

  @reversibility_rank %{
    unknown: 0,
    irreversible: 1,
    migratable: 2,
    compensatable: 3,
    reversible: 4
  }

  @fond_outcomes [:positive, :negative, :inconclusive]

  @spec authority_ceiling() :: :select
  def authority_ceiling, do: :select

  @spec phase_order() :: [atom()]
  def phase_order, do: @phase_order

  @spec fond_outcomes() :: [observation_outcome()]
  def fond_outcomes, do: @fond_outcomes

  @doc "Run one deterministic DfCM planning cycle; returns planning data only."
  @spec cycle(problem()) :: map()
  def cycle(%{options: options} = problem) when is_list(options) do
    observations = Map.get(problem, :observations, %{})
    fences = Map.get(problem, :fences, [])

    admitted =
      options
      |> Enum.map(&normalize_option/1)
      |> Enum.filter(&Map.get(&1, :admitted, true))

    preserved_ids = Enum.map(admitted, & &1.id)

    fence_exclusions = fence_exclusions(admitted, fences)
    fence_excluded_ids = ids(fence_exclusions)

    observation_exclusions =
      admitted
      |> Enum.reject(&(&1.id in fence_excluded_ids))
      |> observation_exclusions(observations)

    initial_exclusions = fence_exclusions ++ observation_exclusions
    initial_excluded_ids = ids(initial_exclusions)
    active = Enum.reject(admitted, &(&1.id in initial_excluded_ids))
    pending = decision_relevant_observations(active, observations)

    dominance_exclusions =
      if pending == [], do: dominance_exclusions(active), else: []

    exclusions = dedupe_exclusions(initial_exclusions ++ dominance_exclusions)
    excluded_ids = ids(exclusions)
    nondominated = Enum.reject(active, &(&1.id in excluded_ids))

    decision =
      case pending do
        [observation | _] ->
          %{
            kind: :observe,
            observation: observation,
            outcomes: @fond_outcomes,
            authority_ceiling: :select
          }

        [] ->
          select(nondominated)
      end

    %{
      authority_ceiling: :select,
      phase_order: @phase_order,
      preserved_options: preserved_ids,
      excluded_options: exclusions,
      nondominated_options: Enum.map(nondominated, & &1.id),
      pending_observations: pending,
      decision: decision,
      hddl_task_network: %{
        task: :dfcm_cycle,
        ordered_subtasks: @phase_order,
        terminal_authority: :select
      },
      fond_policy: fond_policy(decision)
    }
  end

  @doc "Apply one FOND observation outcome to the problem state."
  @spec observe(problem(), atom(), observation_outcome()) :: problem()
  def observe(problem, observation, outcome)
      when is_atom(observation) and outcome in @fond_outcomes do
    observations = Map.get(problem, :observations, %{})
    Map.put(problem, :observations, Map.put(observations, observation, outcome))
  end

  @doc "Materialize the next FOND policy branch set."
  @spec policy(problem()) :: map()
  def policy(problem) do
    case cycle(problem).decision do
      %{kind: :observe, observation: observation} ->
        branches =
          Map.new(@fond_outcomes, fn outcome ->
            next = problem |> observe(observation, outcome) |> cycle()
            {outcome, next.decision}
          end)

        %{
          kind: :strong_cyclic,
          observation: observation,
          fairness: :eventual_conclusive_observation,
          branches: branches,
          authority_ceiling: :select
        }

      decision ->
        %{kind: :terminal_select_state, decision: decision, authority_ceiling: :select}
    end
  end

  @doc "Pareto dominance across progress, reversibility, information, reuse and bounded cost."
  @spec dominates?(option(), option()) :: boolean()
  def dominates?(left, right) do
    left = normalize_option(left)
    right = normalize_option(right)
    left_dims = dimensions(left)
    right_dims = dimensions(right)
    pairs = Enum.zip(left_dims, right_dims)

    Enum.all?(pairs, fn {l, r} -> l >= r end) and
      Enum.any?(pairs, fn {l, r} -> l > r end)
  end

  @doc "A/B/C/X benchmark: A collapses C; B preserves C; C is valuable iff X is positive."
  @spec benchmark() :: problem()
  def benchmark do
    %{
      observations: %{x: :inconclusive},
      fences: [],
      options: [
        %{
          id: "A",
          goal_progress: 8,
          information_gain: 0,
          reuse: 5,
          reversibility: :irreversible,
          irreversible_loss: 1,
          consequence: 2,
          verification_cost: 0,
          destroys: ["C"]
        },
        %{
          id: "B",
          goal_progress: 8,
          information_gain: 0,
          reuse: 5,
          reversibility: :reversible,
          irreversible_loss: 0,
          consequence: 2,
          verification_cost: 1,
          preserves: ["C"]
        },
        %{
          id: "C",
          goal_progress: 10,
          information_gain: 0,
          reuse: 5,
          reversibility: :reversible,
          irreversible_loss: 0,
          consequence: 2,
          verification_cost: 1,
          requires_observation: :x,
          enabled_when: {:x, :positive}
        }
      ]
    }
  end

  defp normalize_option(option) do
    option
    |> Map.put_new(:admitted, true)
    |> Map.put_new(:goal_progress, 0)
    |> Map.put_new(:information_gain, 0)
    |> Map.put_new(:reuse, 0)
    |> Map.put_new(:reversibility, :unknown)
    |> Map.put_new(:irreversible_loss, 0)
    |> Map.put_new(:consequence, 0)
    |> Map.put_new(:verification_cost, 0)
  end

  defp fence_exclusions(options, fences) do
    for fence <- fences,
        option <- options,
        option.id in Map.get(fence, :excludes, []) do
      receipt(
        option.id,
        {:fence, Map.fetch!(fence, :id)},
        Map.get(fence, :evidence),
        Map.get(fence, :falsifier, {:remove_fence, Map.fetch!(fence, :id)})
      )
    end
  end

  defp observation_exclusions(options, observations) do
    Enum.flat_map(options, fn option ->
      case Map.get(option, :enabled_when) do
        {observation, expected} ->
          case Map.get(observations, observation) do
            outcome when outcome in [:positive, :negative] and outcome != expected ->
              [
                receipt(
                  option.id,
                  {:observation_disables, observation, outcome},
                  {:observed, observation, outcome},
                  {:observation_is, observation, expected}
                )
              ]

            _ ->
              []
          end

        nil ->
          []
      end
    end)
  end

  defp decision_relevant_observations(options, observations) do
    options
    |> Enum.flat_map(fn option ->
      case Map.get(option, :requires_observation) do
        nil -> []
        observation -> [observation]
      end
    end)
    |> Enum.uniq()
    |> Enum.filter(&(Map.get(observations, &1) not in [:positive, :negative]))
    |> Enum.sort()
  end

  defp dominance_exclusions(options) do
    Enum.flat_map(options, fn candidate ->
      case Enum.find(options, &(&1.id != candidate.id and dominates?(&1, candidate))) do
        nil ->
          []

        dominant ->
          [
            receipt(
              candidate.id,
              {:dominated_by, dominant.id},
              {:pareto_witness, dominant.id, candidate.id},
              {:invalidate_dominance_witness, dominant.id, candidate.id}
            )
          ]
      end
    end)
  end

  defp select([]),
    do: %{kind: :refuse, reason: :no_lawful_option, authority_ceiling: :select}

  defp select(options) do
    selected = Enum.max_by(options, &selection_score/1)

    %{
      kind: :select,
      selected_option: selected.id,
      selection_score: selection_score(selected),
      authority_ceiling: :select
    }
  end

  defp dimensions(option) do
    [
      option.goal_progress,
      Map.fetch!(@reversibility_rank, option.reversibility),
      option.information_gain,
      option.reuse,
      -option.irreversible_loss,
      -option.consequence,
      -option.verification_cost
    ]
  end

  defp selection_score(option), do: List.to_tuple(dimensions(option))

  defp receipt(option_id, reason, evidence, falsifier) do
    receipt_hash =
      :crypto.hash(:sha256, :erlang.term_to_binary({option_id, reason, evidence, falsifier}))
      |> Base.encode16(case: :lower)

    %{
      option_id: option_id,
      reason: reason,
      evidence: evidence,
      falsifier: falsifier,
      receipt_hash: receipt_hash
    }
  end

  defp ids(exclusions), do: Enum.map(exclusions, & &1.option_id)

  defp dedupe_exclusions(exclusions) do
    exclusions
    |> Enum.uniq_by(&{&1.option_id, &1.reason})
    |> Enum.sort_by(&{&1.option_id, inspect(&1.reason)})
  end

  defp fond_policy(%{kind: :observe, observation: observation}) do
    %{
      kind: :strong_cyclic,
      observation: observation,
      outcomes: @fond_outcomes,
      inconclusive_successor: :observe,
      terminal_authority: :select
    }
  end

  defp fond_policy(decision),
    do: %{kind: :terminal, decision: decision.kind, terminal_authority: :select}
end
