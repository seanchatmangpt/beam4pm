defmodule BeamPM.Dfcm do
  @moduledoc """
  Design for Combinatorial Maximalism (DfCM) planning crown.

  This module composes the admitted WS2 planning contracts rather than
  introducing a parallel planner. It preserves lawful alternatives, applies
  explicit fences, records every exclusion with a deterministic receipt and
  falsifier, and returns either an observation request or a SELECT candidate.

  The authority ceiling is intentionally `:select`. This module has no DO
  surface and performs no external side effects.

  The decomposition order mirrors the HDDL crown:

      preserve -> fence -> calculus -> exclusions -> falsifier -> extension
      -> contingent_policy -> select

  Unresolved decision-relevant observations are represented as FOND branches.
  An inconclusive observation remains unresolved, yielding a strong-cyclic
  observation edge rather than collapsing the option frontier.
  """

  @type reversibility ::
          :reversible | :compensatable | :migratable | :irreversible | :unknown
  @type observation_outcome :: :positive | :negative | :inconclusive
  @type option_id :: String.t()
  @type option :: map()
  @type problem :: %{
          required(:options) => [option()],
          optional(:observations) => %{optional(atom()) => observation_outcome()},
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

  @doc "The DfCM authority ceiling. DfCM may SELECT; it never acquires DO."
  @spec authority_ceiling() :: :select
  def authority_ceiling, do: :select

  @doc "Canonical HDDL decomposition order for one DfCM cycle."
  @spec phase_order() :: [atom()]
  def phase_order, do: @phase_order

  @doc "FOND outcomes used by decision-relevant observation edges."
  @spec fond_outcomes() :: [observation_outcome()]
  def fond_outcomes, do: @fond_outcomes

  @doc """
  Runs one deterministic DfCM SELECT cycle over an admitted problem.

  The return value is descriptive planning data only. `:decision` is either an
  observation request, a selected option, or a refusal when no lawful option
  remains.
  """
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

    pending_observations = decision_relevant_observations(active, observations)

    dominance_exclusions =
      if pending_observations == [] do
        dominance_exclusions(active)
      else
        []
      end

    exclusions = dedupe_exclusions(initial_exclusions ++ dominance_exclusions)
    excluded_ids = ids(exclusions)
    nondominated = Enum.reject(active, &(&1.id in excluded_ids))

    decision =
      case pending_observations do
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
      pending_observations: pending_observations,
      decision: decision,
      hddl_task_network: hddl_task_network(),
      fond_policy: fond_policy(decision)
    }
  end

  @doc """
  Applies one FOND observation outcome and returns the next problem state.

  `:inconclusive` is deliberately retained as unresolved by `cycle/1`, which
  creates the strong-cyclic observe-again edge under the declared fairness
  assumption.
  """
  @spec observe(problem(), atom(), observation_outcome()) :: problem()
  def observe(problem, observation, outcome)
      when is_atom(observation) and outcome in @fond_outcomes do
    observations = Map.get(problem, :observations, %{})
    Map.put(problem, :observations, Map.put(observations, observation, outcome))
  end

  @doc """
  Materializes the FOND branches for the next unresolved observation.

  The `:inconclusive` branch must return another `:observe` decision; positive
  and negative branches may proceed to SELECT after the option frontier is
  recomputed.
  """
  @spec policy(problem()) :: map()
  def policy(problem) do
    current = cycle(problem)

    case current.decision do
      %{kind: :observe, observation: observation} ->
        branches =
          Map.new(@fond_outcomes, fn outcome ->
            next_problem = observe(problem, observation, outcome)
            {outcome, cycle(next_problem).decision}
          end)

        %{
          kind: :strong_cyclic,
          observation: observation,
          fairness: :eventual_conclusive_observation,
          branches: branches,
          authority_ceiling: :select
        }

      decision ->
        %{
          kind: :terminal_select_state,
          decision: decision,
          authority_ceiling: :select
        }
    end
  end

  @doc "Pareto dominance over the admitted DfCM calculus dimensions."
  @spec dominates?(option(), option()) :: boolean()
  def dominates?(left, right) do
    left = normalize_option(left)
    right = normalize_option(right)

    left_dims = maximize_dimensions(left) ++ minimize_dimensions(left)
    right_dims = maximize_dimensions(right) ++ minimize_dimensions(right)

    no_worse =
      Enum.zip(left_dims, right_dims)
      |> Enum.all?(fn {l, r} -> l >= r end)

    strictly_better =
      Enum.zip(left_dims, right_dims)
      |> Enum.any?(fn {l, r} -> l > r end)

    no_worse and strictly_better
  end

  @doc "A/B/C/X reference problem used by the executable FOND/HDDL fixture."
  @spec benchmark() :: problem()
  def benchmark do
    %{
      observations: %{x => :inconclusive},
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

  defp normalize_option(option) when is_map(option) do
    option
    |> Map.put_new(:admitted, true)
    |> Map.put_new(:goal_progress, 0)
    |> Map.put_new(:information_gain, 0)
    |> Map.put_new(:reuse, 0)
    |> Map.put_new(:reversibility, :unknown)
    |> Map.put_new(:irreversible_loss, 0)
    |> Map.put_new(:consequence, 0)
    |> Map.put_new(:verification_cost, 0)
    |> Map.put_new(:destroys, [])
    |> Map.put_new(:preserves, [])
  end

  defp fence_exclusions(options, fences) do
    for fence <- fences,
        option <- options,
        option.id in Map.get(fence, :excludes, []) do
      exclusion_receipt(
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
                exclusion_receipt(
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
    |> Enum.filter(fn observation ->
      Map.get(observations, observation) not in [:positive, :negative]
    end)
    |> Enum.sort()
  end

  defp dominance_exclusions(options) do
    options
    |> Enum.flat_map(fn candidate ->
      case Enum.find(options, fn other ->
             other.id != candidate.id and dominates?(other, candidate)
           end) do
        nil ->
          []

        dominant ->
          [
            exclusion_receipt(
              candidate.id,
              {:dominated_by, dominant.id},
              {:pareto_witness, dominant.id, candidate.id},
              {:invalidate_dominance_witness, dominant.id, candidate.id}
            )
          ]
      end
    end)
  end

  defp select([]) do
    %{
      kind: :refuse,
      reason: :no_lawful_option,
      authority_ceiling: :select
    }
  end

  defp select(options) do
    selected =
      options
      |> Enum.sort_by(
        fn option -> {selection_score(option), option.id} end,
        :desc
      )
      |> hd()

    %{
      kind: :select,
      selected_option: selected.id,
      selection_score: selection_score(selected),
      authority_ceiling: :select
    }
  end

  defp maximize_dimensions(option) do
    [
      option.goal_progress,
      Map.fetch!(@reversibility_rank, option.reversibility),
      option.information_gain,
      option.reuse
    ]
  end

  # Negated minimization dimensions let the same >= Pareto relation apply.
  defp minimize_dimensions(option) do
    [
      -option.irreversible_loss,
      -option.consequence,
      -option.verification_cost
    ]
  end

  defp selection_score(option) do
    {
      option.goal_progress,
      Map.fetch!(@reversibility_rank, option.reversibility),
      option.information_gain,
      option.reuse,
      -option.irreversible_loss,
      -option.consequence,
      -option.verification_cost
    }
  end

  defp exclusion_receipt(option_id, reason, evidence, falsifier) do
    payload = {option_id, reason, evidence, falsifier}

    receipt_hash =
      :crypto.hash(:sha256, :erlang.term_to_binary(payload))
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

  defp hddl_task_network do
    %{
      task: :dfcm_cycle,
      ordered_subtasks: @phase_order,
      terminal_authority: :select
    }
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

  defp fond_policy(decision) do
    %{
      kind: :terminal,
      decision: decision.kind,
      terminal_authority: :select
    }
  end
end
